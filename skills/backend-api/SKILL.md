---
name: backend-api
description: Backend service architecture, REST/GraphQL/gRPC API contracts, serverless/edge functions, DTO validation, input sanitization, middleware, and error handling across Node/Nest, Java/Spring, Python/FastAPI, Go, and .NET.
---

# Backend API & Services

## Rules

- Define explicit, typed request/response contracts (DTOs / Schemas) for all API endpoints.
- Enforce strict input sanitization, parameter validation, and rate-limiting at boundary controllers.
- Use structured, consistent error envelopes without exposing internal stack traces, DB schemas, or sensitive system details to clients.
- Separate business domain logic from transport protocols (HTTP/REST, GraphQL, gRPC, Event Queues).
- Ensure authentication and authorization checks (RBAC/ABAC) are executed via verified middleware before route handlers execute.
- Validate backward-compatibility of API contracts before modifying public endpoints.
