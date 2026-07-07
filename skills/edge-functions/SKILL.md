---
name: edge-functions
description: Edge function and API proxy implementation with CORS, auth, env vars, upstream failures, Deno checks, and safe response boundaries. Use for serverless functions, Supabase Edge Functions, proxy endpoints, CORS, upstream API calls, or edge runtime bugs.
---

# Edge Functions

## Rules

- Handle `OPTIONS` preflight explicitly.
- Keep secrets server-side.
- Do not forward private service keys to clients.
- Normalize upstream errors into safe client responses.
- Make missing env vars fail clearly.
- Verify local type checks where available.
