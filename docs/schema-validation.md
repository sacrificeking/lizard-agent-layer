# Schema Validation

Published JSON Schemas are executable repository contracts. The validator uses Draft 2020-12 and pinned npm dependencies from `package-lock.json`.

## Run the gates

```powershell
npm ci
npm run schema:check
```

`schema:validate` validates all documents selected by `tools/schema-validator/bindings.json`. `schema:test` applies the invalid changes in `tools/schema-validator/mutation-corpus.json` and requires every mutation to fail with its expected JSON Schema keyword.

The canonical repository gate also runs both layers:

```powershell
pwsh -NoProfile -File .\scripts\ci.ps1
```

## Authoring contract

1. Keep each schema on Draft 2020-12 and give it a stable, unique `$id`.
2. Prefer `additionalProperties: false` for closed repository-owned documents.
3. Define required nested fields, enums, formats, and safe relative-path patterns explicitly.
4. Add or update a binding whenever a new declarative document family is introduced.
5. Add a mutation case for each new invariant that could otherwise fail silently.
6. Validate generated documents in the focused integration suite, not only static examples.

The validator accepts `--schema` and `--instance` for a single repository-relative fixture. Runtime integration tests use this mode for install manifests, worktree lifecycle envelopes, and verifier evidence.
