---
name: public-api
description: Clay Public API — HTTP access for building services, apps, and integrations: structured-filter search over Clay's GTM database, structured table queries, and async routine and batch runs.
---

# The Clay Public API

Beyond the CLI, Clay exposes a Public API you can develop against directly over HTTP.
Reach for it when building a service, app, or integration — not for one-off agent tasks
in a shell (use the `cli` skill for those).

## What it offers

- **Search** — find people or companies in Clay's GTM database using **structured filters**. Discover
  valid filter fields with `GET /search/filters-mode/fields?source_type=people` (or `companies`), start a
  search with `POST /search/filters-mode`, then page through the results (see the API reference for the
  exact pagination route). The CLI
  equivalent is `clay search` — see the `search` skill. Prefer the CLI for one-off searches
- **Tables** — structured queries against Clay tables.
- **Routines / batches** — async routine and batch runs.

## Auth

The public API needs its **own** key — the credential from `clay login` is **not**
scoped for it. Issue a dedicated public-API key with the CLI:

```bash
clay api-keys create --name "<name>"   # → { ..., "apiKey": "<secret>" }
```

CLI-created keys are always scoped to the public API. The `apiKey` secret is returned
**only once**, at creation — store it immediately; it can't be retrieved later. Send it in the
`clay-api-key` request header against `https://api.clay.com/public/v0` — **not** as a `Bearer`
token (a `Bearer` header returns 401). Manage existing keys with
`clay api-keys list | update | delete`.

Smoke-test the key:

```bash
curl -H "clay-api-key: $CLAY_API_KEY" https://api.clay.com/public/v0/me
# → { "user": {...}, "workspace": {...} }
```

## Reference

Full developer documentation — Public API reference, CLI reference, concepts, and the
OpenAPI spec — lives at:

- https://developers.clay.com/llms.txt

Fetch that first to get exact endpoints, request/response shapes, pagination, and rate
limits before writing integration code.
