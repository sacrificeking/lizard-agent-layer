# Loop Budget

Schema version: 1

## Caps

- Daily token cap: 2000000
- Max runs per day: 4
- Max sub-agents per run: 0
- Max attempts per item: 3
- On exceed: pause and ask for human review

## Model Routing

Cheap model roles:

- triage
- inventory
- state pruning
- run-log summary
- changelog draft
- CI log classification

Strong model roles:

- verifier
- security review
- finance/auth/supabase risk assessment
- release readiness verdict
- profile or pack adaptation

## Early Exit

If no high-priority or actionable items exist, write a short run-log entry and stop. Do not spawn verifier or implementation agents on empty watchlists.
