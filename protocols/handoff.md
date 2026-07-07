# Handoff Protocol

Use this protocol whenever work may continue in another harness or model.

## Before handoff

Update `.agent/memory/working/WORKSPACE.md` with:

- current objective
- files touched or inspected
- decisions made
- assumptions still open
- verification already run
- known failures or skipped checks
- recommended next step

## Receiving a handoff

- Read the workspace note before editing.
- Verify the current git status.
- Re-check any claim that affects destructive, remote, release, dependency, CI, or database work.
- Continue from the newest user request, not from stale workspace notes.

## Memory boundary

Keep handoff notes concise and secret-free. Do not store raw provider responses, API keys, private customer data, or production credentials.
