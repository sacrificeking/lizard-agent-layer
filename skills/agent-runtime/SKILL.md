---
name: agent-runtime
description: Runtime agent architecture, model routing, tool boundaries, memory policy, fallback behavior, guardrails, prompt interfaces, and evaluation harnesses. Use when implementing or reviewing agentic application runtime code.
---

# Agent Runtime

## Rules

- Separate orchestration, model provider clients, tools, memory, retrieval, and user-facing handlers.
- Keep model routing explicit by task role, risk level, latency, and cost.
- Define tool permissions before adding new tool calls.
- Prefer structured inputs and outputs for agent/tool boundaries.
- Add fallback behavior for provider failures, rate limits, malformed outputs, and missing environment variables.
- Keep prompt templates and runtime policy versioned.

## Verification

- Add focused tests for routing, fallback, tool permissions, and schema validation.
- Run typecheck and relevant runtime tests before finalizing.
- Include manual evaluation notes when behavior quality cannot be fully unit-tested.

## Safety

- Do not persist sensitive raw conversations unless the project explicitly opts in.
- Never let model output directly execute destructive actions without approval gates.
- Keep external tool access scoped to the minimum required behavior.
