# Context Hygiene

- Give every stage the complete goal, success criteria, constraints, and relevant evidence.
- Keep working context narrow: include only files and outputs needed for the current stage.
- Reuse a prior file summary only while the file content hash is unchanged.
- Summarize large tool outputs and preserve links or hashes to the underlying evidence.
- Start a fresh verification context instead of passing the executor conversation verbatim.
- Follow `.agent/protocols/project-context.md` for any cross-harness handoff persistence.
- Never put secrets, credentials, raw customer data, or private logs into handoff or routing receipts.
