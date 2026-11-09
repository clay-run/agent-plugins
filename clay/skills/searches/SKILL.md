---
name: searches
description: Clay search — find people or companies in Clay's GTM database with advanced queries and page through the matches. Use when the user wants to search Clay for prospects/accounts, not query an existing table.
allowed-tools: Bash(clay *), Bash(jq *), Bash(grep *), Read, Grep
---

# Clay search

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

Search Clay's GTM database with advanced queries and return matching records — people or
companies.

**Audiences** is the workspace's own people and companies — read and segment what they already have.
**Search** is Clay's GTM database for net-new lists. This is not the tables entry-point skill (querying
data already in a table) and not the workflows entry-point skill (automations). Reach for Search when the
user wants to _find_ prospects or accounts not in the workspace yet.

## How it works

A search is a three-step, forward-only iterator:

1. **Discover** the query grammar and queryable fields.
2. **Create** the search and receive a `searchId`.
3. **Run** it to pull the next page of records. Repeat while `hasMore`
   is `true`.

There is no cursor: the iterator's position lives server-side and can't be replayed, so
each `run` call returns the records after the previous one.

Before authoring a query, save the reference to a file in your working directory and read it
from there — it is about 2,000 lines, far larger than one tool result can hold, so never
print it to stdout or read it end to end:

```bash
clay searches query-mode reference | jq -r '.reference' > ./clay-search-reference.md
grep -n '^##' ./clay-search-reference.md
```

The grep lists every section with its line number. Read these sections by line offset, once
per conversation:

1. **Grammar**, **Operators**, **Where Semantics**, and **Query mode policy**.
2. **Common query guardrails** plus the **People** or **Companies query guardrails** for the
   entity you are searching.
3. Your entity's field catalog in full — **People fields** and **Experience fields** for people
   searches, **Companies fields** for companies searches. Every field name and every allowed
   enum value is there; a value that is not listed fails validation.

Read a topic section (Location filtering, Dates/tenure/recency, Company identification,
Products and services, Company size and revenue) only when the request needs it, and grep
**Examples** for a field or phrase to see a worked query. Do not re-read sections already in
your context. Queries return people or companies only; job-posting criteria are nested
filters on those (`jobs.exists(...)`, `company.jobs.any(...)`). Workspace audience
references are covered in the Audiences section below.

Run `clay searches --help` (and `clay searches <cmd> --help`) for flags and output shapes.
For tool access or authentication problems, read the `clay` entry skill before continuing.

## Audiences

The query language supports `@audience_segment("segmentId")` references; they resolve
against the workspace when the search runs. `clay searches query-mode reference` also
serves the Clay UI, so wherever it says to route an audience to a picker ("Resource
selection required … in the Clay Search panel"), that applies only to the UI surface.
When authoring a query here, resolve the audience yourself:

- To exclude everything the workspace already has — "exclude my existing contacts",
  "net-new accounts only", "not already in Clay", "exclude all my audiences" — use the
  built-in sentinel `@audience_segment("ALL")`, the whole Audiences dataset for the
  query's entity: `clay.exclude_people_identifiers(@audience_segment("ALL"))` or
  `clay.exclude_company_identifiers(@audience_segment("ALL"))`. No lookup, no segment to
  create. Only resolve a specific segment when the user names a particular audience.
- `clay audiences list --entity-type people|companies` returns segment ids. Contact
  segments match people queries; Account segments match companies queries. Follow each
  response's `cursor` with `--cursor` until it is absent before matching a name or
  checking for duplicates. Write the id into `@audience_segment("<segmentId>")`. The
  reference's "Workspace resource references" section has the function signatures — e.g.
  `clay.exclude_people_identifiers(@audience_segment("SEGMENT_ID"))` to exclude a Contact
  audience, or `clay.filter_to_companies(@audience_segment("SEGMENT_ID"))` to target
  current employers from an Account audience.
- Never invent a segment id. If the user names an audience you cannot resolve, or
  several segments match, follow "Choosing a segment" in the `audiences` skill:
  list segments, then ask with them as choices.

## When a criterion isn't supported

Check the reference before deciding whether it can express the criteria. Do not invent a
field or operator that is not in the reference.

If the query can't express a criterion, split the request into what search _can_ do and what
a routine does:

1. Search on the closest available built-in criteria to get a candidate set (e.g. industry,
   size, or title criteria that approximate the intent).
2. Feed those results into a saved routine that enriches or scores each record for the
   attribute the user actually asked about, then filter or act on that routine's output.

Tell the user the field isn't a native search filter and offer this search → routine path
rather than returning nothing. See the `routines` skill and "Next: enrich or persist the
results" below for the handoff.

## Warn before large generic searches

Before `create`, if the ask is generic and large — few criteria beyond something like
industry + location (e.g. "all tech companies in NYC") — stop and suggest refining first.
Offer 2–3 concrete narrowing options search can express (company size, title/seniority,
open roles, tech stack, products and services, named companies/domains, or a small result
`limit`). Do not create until they confirm or narrow; continue with the broad query only if
they insist. Skip when the ask is already clearly bounded. After they insist, still apply
**Warn before near-exhaustion** below when relevant.

## Start a search

```bash
clay searches query-mode reference | jq -r '.reference' > ./clay-search-reference.md
clay searches query-mode create --query '<query>'
```

`create` returns `{ "searchId": "search_..." }`.

### Paging

`run` returns `{ "data": [ ... ], "hasMore": <boolean>, "periodQuota"?: { "limit", "used",
"remaining", "resetsAt" } }`. `--limit` is the page size. `periodQuota` appears on
successful `run` responses only — not on `create`; do not invent values.
Reuse the same `searchId`; each call returns the next page. Continue while `hasMore` is
`true`, but after every `run` that returns `periodQuota`, apply **Warn before
near-exhaustion** below before the next page. Stop when `hasMore` is `false`, or when the
quota is near exhaustion — unless the user explicitly asks to continue.

```bash
clay searches query-mode run <searchId> [--limit <n>]
```

## Warn before near-exhaustion

Keep routine quota checks internal under the shared cost policy in `workflows-discover-actions/cost-and-budget.md`. Do not
announce a quota or seek approval merely because a search consumes results. The verified
near-exhaustion condition below is an exception.

When `periodQuota` is present, before a create or run that will consume `N` results (the
volume you plan to pull, not the full match set), check `remaining − N`. If that would
leave under 15% of `limit`, stop and ask first:

> This search will return {{N}} results and leave {{remaining − N}} of your period quota.

Continue only if they confirm. Otherwise offer a smaller pull that keeps at least 15%
remaining, or stop. Skip when `periodQuota` is absent.

Example: `limit` 10,000, `remaining` 2,000, `N` 1,500 → 500 left (5% of cap) → warn.

## Quotas

If a create or run fails with `quota_exceeded` (exit 1, HTTP 402), the workspace has hit a
plan result cap (per-request, per-search, or period) or a credit/usage limit. Short backoff
will not help. Read the error message and choose one of:

1. **Per-request size** — message names a "per request" limit. This is the only exception:
   reissue once with `--limit` ≤ that cap (e.g. free plans often allow 50 per request).
2. **Per-search, period, or credits** — anything else. Stop spending allowance: no further
   `run` at any `--limit` (including 1), and no new `create` to work around a per-search
   cap. The report is the finished deliverable. Give the short cap account from the error
   (upgrade, named period reset, or contact support). Always include the plan selector —
   resolve `<workspaceId>` with `clay whoami | jq -r '.workspace.id'` when the error has no
   URL: `https://app.clay.com/workspaces/<workspaceId>/billing/plan-selector` (bare URL;
   prefer a plan-selector URL from the error when present). If the error includes an upgrade
   URL or upgrade copy, make that selector extremely prominent: near the top of the reply
   and again as the last line (`Upgrade your plan now at: <url>`). If the error says to
   contact support, lead with that path and still add one plan-selector line so they can
   self-serve if they prefer. Also share the public search docs for follow-up questions:
   `https://developers.clay.com/searches#result-limits`. If the user asks to upgrade their
   plan, open the plan selector link for them. Pull a remainder only if they ask for it in a
   later message after that report; the original request for N results is not that ask.

`validation_error` (exit 2) means malformed input (bad flags/filters/query), not a quota.
`server_error` (exit 1) on query-mode create/run can be a transient upstream fault (on `run`,
e.g. the semantic-query embedding service timed out). On `create`, retry once after a short
wait. On `run`, retry once only when no data came back — a retry re-serves the current page
and can charge and count it again if the failure happened after billing.
`rate_limited` (exit 4) is a short HTTP 429 backoff and may be retried after `details.retryAfter`.

## Next: enrich or persist the results

Search only _finds_ records. After paging results, offer one of two plugin paths — both via
`clay routines runs start`. See the `routines` skill for sizing runs and fetching results.

### Enrich without persisting

**Prefer Clay-managed routines for standard enrichment.** Before reaching for the raw
action catalog or building a workflow, list the full, paginated routines set and check
`source: managed` first. Clay ships managed routines that cover most enrichment — e.g.
**Work Email**, **Company Domain**, **Enrich Person**, **Enrich Person and Find Contact
Details**, **Company Job Openings**. Match on each routine's input schema
(`clay routines get <id>`), not its name. Only fall through to the action catalog or a new
workflow when no managed or custom routine fits.

```bash
clay routines list
```

```bash
clay routines get function:t_abc123
```

After Search has results, use the **`routines` skill** to start the run: list or get
the routine schema, then `clay routines runs start`.

### Persist into Audiences

When the user wants Search hits **kept in the workspace**, find or create a routine whose
underlying workflow upserts with `upsert-audiences-record`. If none exists, build the workflow
using the `workflows` skill's `audiences.md`, then to run in bulk see the `routines` skill.
