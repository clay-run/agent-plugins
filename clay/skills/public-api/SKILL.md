---
name: public-api
description: Clay Public API — HTTP access for building services, apps, and integrations: natural-language search over Clay's GTM database, structured table queries, and async routine and batch runs.
---

# The Clay Public API

Beyond the CLI, Clay exposes a Public API you can develop against directly over HTTP.
Reach for it when building a service, app, or integration — not for one-off agent tasks
in a shell (use the `cli` skill for those).

## What it offers

- **Search** — natural-language searches over Clay's proprietary GTM database
  (850m+ people, 60m+ companies).
- **Tables** — structured queries against Clay tables.
- **Routines / batches** — async routine and batch runs.

## Auth

The public API needs its **own** key — the `CLAY_API_KEY` that authenticates the CLI and
MCP server is **not** scoped for it. Issue a dedicated public-API key with the CLI:

```bash
clay api-keys create --name "<name>"   # → { ..., "apiKey": "<secret>" }
```

CLI-created keys are always scoped to the public API. The `apiKey` secret is returned
**only once**, at creation — store it immediately; it can't be retrieved later. Send it
as a Bearer token against `https://api.clay.com/public/v0`. Manage existing keys with
`clay api-keys list | update | delete`.

## Reference

Full developer documentation — Public API reference, CLI reference, concepts, and the
OpenAPI spec — lives at:

- https://claydevelopers.mintlify.app/llms.txt

Fetch that first to get exact endpoints, request/response shapes, pagination, and rate
limits before writing integration code.
