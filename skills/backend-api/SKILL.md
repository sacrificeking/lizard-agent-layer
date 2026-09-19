---
name: backend-api
description: Backend API architecture, server endpoints, and service contract changes across REST, GraphQL, or gRPC. Use when modifying backend routing, controllers, middleware, or service boundaries.
---

# Backend API & Services

## Rules

- Define explicit, typed request/response contracts (DTOs / Schemas) for all API endpoints.
- Enforce strict input sanitization, parameter validation, and rate-limiting at boundary controllers.
- Use structured, consistent error envelopes without exposing internal stack traces, DB schemas, or sensitive system details to clients.
- Separate business domain logic from transport protocols (HTTP/REST, GraphQL, gRPC, Event Queues).
- Ensure authentication and authorization checks (RBAC/ABAC) are executed via verified middleware before route handlers execute.
- Validate backward-compatibility of API contracts before modifying public endpoints.

## Verification

- Add focused unit and integration tests for route handlers, schema validation, and status codes.
- Run typecheck, linting, and relevant test suites before finalizing API changes.
- Verify error response envelopes and boundary status codes against API contract specifications.

## Safety

- Do not expose internal server secrets, database credentials, or private stack traces in responses or logs.
- Guard against privilege escalation by enforcing strict permission and identity checks on protected routes.
- Avoid unversioned breaking changes to public endpoints; maintain backwards compatibility or provide deprecation grace periods.
