# Secret Handling

- Do not read secrets unless the task explicitly requires checking their presence.
- Prefer environment variable names over values in logs and persisted project context.
- Never copy `.env` contents into project context, docs, screenshots, issues, or commits.
- Keep generated reports metadata-only by default; mask values (`SECRET=***`) in generated summaries.
- Use masked CI secrets for automation.
- If a secret appears in output, stop and ask for rotation guidance.

## User Pastes & Sensitive Stop
- If a user message, log, or attachment appears to contain raw credentials, customer/account PII, or unredacted production dumps: stop the task immediately and ask for a redacted repro.
- Do not echo, analyze, or persist the sensitive values. Name one category: `credential`, `customer-or-account`, `production-dump`, or `unsure-treat-as-dump`.
- Local development with `.env` files or environment variables is permitted; domain type names (`CustomerService`) never trigger refusal.
