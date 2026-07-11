# Secret Handling

- Do not read secrets unless the task explicitly requires checking their presence.
- Prefer environment variable names over values in logs and memory.
- Never copy `.env` contents into memory, docs, screenshots, issues, or commits.
- Keep generated reports metadata-only by default; do not duplicate existing project instructions into secondary artifacts unless the operator explicitly requests context-inclusive output.
- Use masked CI secrets for automation.
- If a secret appears in output, stop and ask for rotation guidance.
