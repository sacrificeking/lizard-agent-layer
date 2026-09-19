---
name: research-audit
description: Structured research, comparative analysis, third-party repo audits, and external technology evaluations. Use when conducting multi-source research or architectural option comparisons.
---

# Research Audit

## Rules

- Separate verified facts from inference.
- Cite sources for external claims.
- Call out uncertainty and stale information risks.
- Compare benefits, drawbacks, and implementation cost.
- Preserve project boundaries when reviewing third-party repositories.
- End with a clear recommendation when enough evidence exists.

## Verification

- Check source dates when recency matters.
- Prefer primary sources for technical claims.
- Summarize unresolved assumptions before recommending implementation.

## Safety

- Do not copy third-party code into a target project without license review.
- Treat benchmark repos as inspiration unless the user explicitly approves adoption.
- Avoid exposing private project details when comparing against public sources.
## Supporting material

- `references/source-evaluation.md`: source priority, recency, inference, and adoption checks.
- `tests/third-party-repo-audit.md`: scenario test for external repository benchmark tasks.
