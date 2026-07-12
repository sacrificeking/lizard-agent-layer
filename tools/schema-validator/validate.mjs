import fs from "node:fs";
import path from "node:path";
import process from "node:process";
import { fileURLToPath } from "node:url";
import Ajv2020 from "ajv/dist/2020.js";
import addFormats from "ajv-formats";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const defaultRoot = path.resolve(scriptDir, "..", "..");

function readJson(filePath) {
  try {
    const text = fs.readFileSync(filePath, "utf8").replace(/^\uFEFF/, "");
    return JSON.parse(text);
  } catch (error) {
    throw new Error(`JSON_READ_FAILED: ${filePath}: ${error.message}`);
  }
}

function walkFiles(root) {
  const files = [];
  for (const entry of fs.readdirSync(root, { withFileTypes: true })) {
    const full = path.join(root, entry.name);
    if (entry.isDirectory()) files.push(...walkFiles(full));
    else if (entry.isFile()) files.push(full);
  }
  return files;
}

function globRegex(glob) {
  const escaped = glob
    .replace(/[.+^${}()|[\]\\]/g, "\\$&")
    .replace(/\*\*/g, "::DOUBLE_STAR::")
    .replace(/\*/g, "[^/]*")
    .replace(/::DOUBLE_STAR::/g, ".*");
  return new RegExp(`^${escaped}$`);
}

function matchesAny(relativePath, globs = []) {
  return globs.some((glob) => globRegex(glob).test(relativePath));
}

function formatErrors(errors = []) {
  return [...(errors || [])]
    .sort((a, b) => `${a.instancePath}:${a.keyword}`.localeCompare(`${b.instancePath}:${b.keyword}`))
    .map((error) => ({
      instance_path: error.instancePath || "/",
      schema_path: error.schemaPath,
      keyword: error.keyword,
      message: error.message,
      params: error.params,
    }));
}

export function createValidator(root = defaultRoot) {
  const ajv = new Ajv2020({
    allErrors: true,
    allowUnionTypes: true,
    strict: true,
    validateFormats: true,
  });
  addFormats(ajv);
  const schemaDir = path.join(root, "schemas");
  const schemas = walkFiles(schemaDir)
    .filter((file) => file.endsWith(".schema.json"))
    .sort();
  for (const schemaPath of schemas) ajv.addSchema(readJson(schemaPath));
  return ajv;
}

export function validateInstance(ajv, root, schemaRelative, instanceRelative) {
  const schema = readJson(path.join(root, schemaRelative));
  const validate = ajv.getSchema(schema.$id);
  if (!validate) throw new Error(`SCHEMA_NOT_REGISTERED: ${schemaRelative}`);
  const instance = readJson(path.join(root, instanceRelative));
  const valid = validate(instance);
  return {
    schema: schemaRelative,
    instance: instanceRelative,
    valid: Boolean(valid),
    errors: formatErrors(validate.errors),
  };
}

function validateBindings(root, bindingsPath) {
  const bindings = readJson(bindingsPath);
  if (bindings.schema_version !== 1 || !Array.isArray(bindings.bindings)) {
    throw new Error(`BINDINGS_INVALID: ${bindingsPath}`);
  }
  const ajv = createValidator(root);
  const allFiles = walkFiles(root)
    .map((file) => path.relative(root, file).split(path.sep).join("/"))
    .sort();
  const results = [];
  for (const binding of bindings.bindings) {
    const instances = allFiles.filter((relative) =>
      matchesAny(relative, binding.include) && !matchesAny(relative, binding.exclude || []));
    if (instances.length === 0) throw new Error(`BINDING_EMPTY: ${binding.schema}`);
    for (const instance of instances) results.push(validateInstance(ajv, root, binding.schema, instance));
  }
  return results;
}

function decodePointerToken(token) {
  return token.replace(/~1/g, "/").replace(/~0/g, "~");
}

function applyMutation(document, mutation) {
  const tokens = mutation.path.split("/").slice(1).map(decodePointerToken);
  if (tokens.length === 0) throw new Error(`MUTATION_PATH_INVALID: ${mutation.path}`);
  let parent = document;
  for (const token of tokens.slice(0, -1)) {
    if (parent === null || typeof parent !== "object" || !(token in parent)) {
      throw new Error(`MUTATION_PATH_MISSING: ${mutation.path}`);
    }
    parent = parent[token];
  }
  const key = tokens.at(-1);
  if (mutation.op === "remove") {
    if (Array.isArray(parent)) {
      const index = Number.parseInt(key, 10);
      if (!Number.isInteger(index) || index < 0 || index >= parent.length) {
        throw new Error(`MUTATION_ARRAY_INDEX_INVALID: ${mutation.path}`);
      }
      parent.splice(index, 1);
    } else {
      delete parent[key];
    }
  }
  else if (mutation.op === "add" || mutation.op === "replace") parent[key] = mutation.value;
  else throw new Error(`MUTATION_OPERATION_INVALID: ${mutation.op}`);
}

function validateMutationCorpus(root, corpusPath) {
  const corpus = readJson(corpusPath);
  if (corpus.schema_version !== 1 || !Array.isArray(corpus.cases)) {
    throw new Error(`MUTATION_CORPUS_INVALID: ${corpusPath}`);
  }
  const ajv = createValidator(root);
  const results = [];
  for (const testCase of corpus.cases) {
    const schema = readJson(path.join(root, testCase.schema));
    const validate = ajv.getSchema(schema.$id);
    const instance = structuredClone(readJson(path.join(root, testCase.base)));
    for (const mutation of testCase.mutations) applyMutation(instance, mutation);
    const valid = validate(instance);
    const errors = formatErrors(validate.errors);
    const keywords = new Set(errors.map((error) => error.keyword));
    const passed = !valid && keywords.has(testCase.expected_keyword);
    results.push({ name: testCase.name, passed, valid: Boolean(valid), expected_keyword: testCase.expected_keyword, errors });
  }
  return results;
}

function parseArguments(argv) {
  const options = { root: defaultRoot, schema: null, instance: null, corpus: null };
  for (let index = 0; index < argv.length; index += 1) {
    const argument = argv[index];
    if (argument === "--root") options.root = path.resolve(argv[++index]);
    else if (argument === "--schema") options.schema = argv[++index];
    else if (argument === "--instance") options.instance = argv[++index];
    else if (argument === "--mutation-corpus") options.corpus = argv[++index];
    else throw new Error(`ARGUMENT_UNKNOWN: ${argument}`);
  }
  return options;
}

function printFailures(results) {
  for (const result of results.filter((entry) => entry.valid === false || entry.passed === false)) {
    if (result.passed === false && result.valid === false && result.errors.some((error) => error.keyword === result.expected_keyword)) continue;
    process.stderr.write(`${JSON.stringify(result)}\n`);
  }
}

function main() {
  const options = parseArguments(process.argv.slice(2));
  const root = options.root;
  let mode;
  let results;
  if (options.corpus) {
    mode = "mutation-corpus";
    results = validateMutationCorpus(root, path.resolve(root, options.corpus));
    const failures = results.filter((result) => !result.passed);
    printFailures(failures);
    if (failures.length > 0) process.exitCode = 1;
  } else if (options.schema || options.instance) {
    if (!options.schema || !options.instance) throw new Error("SCHEMA_AND_INSTANCE_REQUIRED");
    mode = "single-instance";
    const result = validateInstance(createValidator(root), root, options.schema, options.instance);
    results = [result];
    if (!result.valid) {
      printFailures(results);
      process.exitCode = 1;
    }
  } else {
    mode = "bindings";
    results = validateBindings(root, path.join(root, "tools", "schema-validator", "bindings.json"));
    const failures = results.filter((result) => !result.valid);
    printFailures(failures);
    if (failures.length > 0) process.exitCode = 1;
  }
  const passed = mode === "mutation-corpus"
    ? results.filter((result) => result.passed).length
    : results.filter((result) => result.valid).length;
  process.stdout.write(`Schema ${mode}: ${passed}/${results.length} passed.\n`);
}

try {
  main();
} catch (error) {
  process.stderr.write(`${error.message}\n`);
  process.exitCode = 1;
}
