# Handoff Protocol

Use this protocol whenever work may continue in another harness or model.

## Before handoff

Consult `.agent/protocols/project-context.md`. Only when it permits a persistent handoff record, update the destination it names with:

- current objective
- files touched or inspected
- decisions made
- assumptions still open
- verification already run
- known failures or skipped checks
- recommended next step

## Receiving a handoff

- Read any permitted handoff record before editing.
- Verify the current git status.
- Re-check any claim that affects destructive, remote, release, dependency, CI, or database work.
- Continue from the newest user request, not from stale workspace notes.

## Persistence boundary

Keep handoff notes concise and secret-free. Do not store raw provider responses, API keys, private customer data, or production credentials. When project-context persistence is off, keep the handoff in the active user-visible conversation only.
