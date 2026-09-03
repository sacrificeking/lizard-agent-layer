# Working With Lizard Agent Layer in This Project

This guide explains how to use AI coding assistants in this repository.

## 1. Daily Prompts

- Type ordinary work requests: specify the relevant area/files, what is needed or broken, and how to verify completion (e.g. run a test or typecheck).
- Before medium/high-risk edits (migrations, auth, security, CI, dependency upgrades, large refactorings), instruct the assistant to run a premortem first.
- Keep your current IDE model. You do not need to operate routing scripts, model pickers, or loop commands manually.

## 2. Untrusted Pastes & Secrets

- **Never paste raw credentials, customer PII (credit cards, IBANs), or uncleaned production dumps into chat.**
- The AI provider may already receive whatever is entered into the chat window. Redact data locally before sending.
- Local development with `.env` files and environment variables is fully supported. Secret values are masked in generated summaries.

## 3. Reviewing AI Changes

- Always inspect generated diffs before merging.
- Ensure the changes match existing code conventions and tests pass.
- If you cannot explain or verify the change, do not merge or deploy it.

## 4. Repository Champion / Setup Checklist

If you are setting up or updating the layer for this repository:
1. Generate and inspect an installation plan (`install.ps1 -WritePlan`).
2. Apply the verified plan with human approval (summary mode default: `-Apply -ApprovedPlanPath ... -HumanApproved`, or with `-ApprovedPlanSha256` in digest mode).
3. Run diagnostic health verification (`doctor.ps1 -Strict`).
4. Review and merge any generated sidecars (`merge-suggestions.ps1`) before onboarding team members.
