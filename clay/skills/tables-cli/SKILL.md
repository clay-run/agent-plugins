---
name: tables-cli
description: Clay tables — inspect, query, and export data from an existing table via the `clay tables` CLI (list, columns, rows, query-live, structured query). To investigate a table or record, use the focused `/tables-*` skills (analyze, trace, error-sweep, value-trace, capacity).
---

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

Clay tables are spreadsheet-like: columns (basic, formula, or enrichment), rows
(usually people or companies), and sources that add rows. This skill only **reads**
tables that already exist. For tool access or authentication problems, read the `clay` entry skill before continuing.

## Finding a table

Resolve it to a `t_...` id. Use `clay tables list --filter workbook.id=<wb_...>`
when the workbook is known (`clay workbooks list`), otherwise `clay tables list` and
pick by `.name` with `jq`. Do not use `--filter queryEnabled=true` unless you only want
query-synced tables — it hides the rest. If the user named no table or workbook,
ask rather than sweeping the workspace.

ID prefixes: `t_` table, `f_` column, `r_` row, `wb_` workbook.

## Not supported

- **Creating tables** (or adding fields/columns). Tell the user to create the table
  in the Clay app first; you can work with it once it exists.
- **Writing data.** These table operations cannot insert rows, update cells, or trigger enrichments.
  `clay tables update` only toggles whether a table is queryable (`--query-enabled`);
  it does not write data. Rows enter through the Clay app. The Public API is
  query/list-only as well.

## CLI: `clay tables`

Prefer `columns list|get` / `get` / `rows list|get` / `query-live` for everyday work; use
`clay tables query` when you need synced Enterprise joins/pagination. (`columns` and
`rows` are command groups — `clay tables columns <tableId>` is not a command.)

**Availability:** `clay tables query` requires **API table sync** (Enterprise).
Without sync, `clay tables query` fails with `auth_forbidden` and
`clay tables update --query-enabled true` with `plan_upgrade_required` (older CLI
versions report `auth_forbidden`), both saying "API table sync is not enabled for
this workspace" —
that's an account limitation, not a bug: don't retry or re-login. Fall back to
`columns` / `rows` / `query-live` (no sync required), and tell the user to contact
Clay about Enterprise access for synced `query`.

`clay tables --help` (and `clay tables <cmd> --help`) is the authoritative spec —
read it for exact flags, JSON shapes, and error codes.

### Reading rows vs. querying

Pick by how much querying power you need:

- **Read rows directly** — `clay tables get`, `columns`, `rows list/get`. Works on
  any table with no setup. Filtering is exact-match only (`rows list --filter col=value`,
  ANDed together). Best for quick lookups and pulling cell values as-is.
  `rows list` returns `data[].cells` keyed by column id — each cell is an object
  (`{ "cells": { "<f_id>": { "status": ..., "value": ... } } }`), not a flat
  `{ "<f_id>": <value> }` map (synced `query` cells are `{status, value}` objects too —
  see below). Pages with `--limit` (1-100, default 20) and `--cursor`.
- **Query live (ClayQL)** — `clay tables query-live`. Structured ClayQL against the
  table's live Postgres data — no Enterprise sync required. Use `columns get` / `get`
  to learn the schema before writing the query.
- **Query (synced)** — `clay tables query`. Richer: range / contains / OR filters,
  **joins across tables**, sorting, grouping, and paging past 100 rows. The table must
  first be **enabled for querying** (below); requires API table sync (Enterprise).

Reach for `query-live` or `query` the moment a plain `rows list --filter` can't
express what you need — a range or text match, an OR, a join, sorting, grouping, or
a large ordered pull. Prefer `query-live` when sync isn't enabled; use synced `query`
for multi-table joins and cursor paging (and for a complete large pull when sync is
available — `query-live` is capped at 100 rows per call; page with `LIMIT n OFFSET m`
in `--query`). Otherwise a direct `rows list` is faster and needs no setup.

**Bulk enrichment exception:** if `rows list` returns `truncated: true`, treat the result as one unfiltered, unordered sample of at most 20 currently retained passthrough rows. It accepts no cursor or filters, and completed rows may already have been deleted, so an empty sample is valid and the result is never a complete source listing. For migration, use `clay tables columns get` as the source of truth and inspect its sources to determine the origin. An Audiences-backed source includes `audience.entityType`, `segments[].id`, `isGlobal`, and `entityIdOnly`; a global Audience has `isGlobal: true` and no segment objects.

### Row ordering

Both `rows list` and `tables query` return rows in a stable, consistent order that
roughly tends to follow the order rows were created — but treat that as a loose
tendency only, never a guarantee. It's approximate, the two commands don't necessarily
order rows the same way as each other, and neither matches the order rows appear in
the Clay app. So don't rely on position for anything: don't map a row's position in
the output to what the user sees on screen, and don't read "the first / most recent
N rows" from position. To find a **specific record**, filter by an identifier
(`rows list --filter`, or a `tables query` / `query-live` filter) rather than relying
on position. Caller-controlled order is available on both query paths: `tables query`
via `order_by` (single page only — can't combine with cursor paging), and `query-live`
via ClayQL `ORDER BY` (also subject to the 100-row cap / `LIMIT`/`OFFSET` paging).

### List tables

Discover navigation-visible tables and their ids. Each row carries a `queryEnabled` flag
for whether the table is enabled for querying.

```bash
clay tables list                                              # navigation-visible tables
clay tables list --filter queryEnabled=true                   # query-sync-enabled only
clay tables list --filter workbook.id=wb_123                 # tables in one workbook
clay tables list --filter owner.id=1417322 --limit 50         # by owner
clay tables list --limit 50 --cursor cursor_abc123            # pagination
```

### Run a live ClayQL query

`clay tables query-live` runs ClayQL against the table's live Postgres data — no
Enterprise sync required. Learn column names with `columns get` / `get` first; omit
any `FROM` clause (the table comes from `<tableId>`):

```bash
clay tables columns get t_abc123
clay tables query-live t_abc123 --query 'SELECT {{Name}}, {{ARR}} ORDER BY {{ARR}} DESC LIMIT 10'
```

ClayQL is a whitelisted SQL subset — `clay tables query-live --help` lists the exact
supported grammar. The two most common traps: date ranges use literal ISO strings
(`{{Close date}} >= '2026-06-01'`) because `NOW()`, `INTERVAL`, and date arithmetic are
rejected, and `CAST` works only to `decimal`.

See `clay tables query-live --help` for output shape and errors. Output is
`{ query, queryName?, rowCount, results }` — rows live under **`results`**, not `data`.
Each call returns at most **100 rows**; page with `LIMIT n OFFSET m` in `--query` (bump
`OFFSET` until a page returns fewer than `n` rows). Prefer this over synced `query` when
API table sync isn't enabled, or for a quick single-table look. For a complete large
export when sync _is_ available, prefer synced `query` + cursor paging instead.

### Enable a table for querying

`clay tables query` can only read a table that's been **enabled for querying**. Toggle
it with `update`:

```bash
clay tables update t_abc123 --query-enabled true    # { id, queryEnabled: true }
clay tables update t_abc123 --query-enabled false
```

- **Not instant.** Enabling prepares the table in the background. A `query` run too soon
  may return no/partial rows; retry after a short wait. Larger tables take longer.
- **Limited per workspace.** Check `clay tables query-usage` (`{ used, limit }`); at the
  cap, disable a table before enabling another. A `limit` of 0 means API table sync isn't
  enabled for the workspace (see the availability note above).

### Run a structured query

`clay tables query` takes a **structured JSON query** that supports **joins across
multiple tables** and cursor pagination — so it's the right choice for complex queries
or reading past 100 rows. The query is read from a file or stdin via `--query`.

```bash
clay tables query --query ./query.json | jq '.data | length'
echo '{"tables":[{"id":"t_abc123"}]}' | clay tables query --query - --limit 100
clay tables query --query ./query.json --limit 100 --cursor cursor_abc123
```

- The `--query` payload is the query itself (what to fetch); pagination is separate.
  Minimal shape: `{ "tables": [{ "id": "t_..." }] }`. Beyond `tables`, it may include
  `filter`, `select`, `join`, `order_by`, `group_by`, and `field_mode`. Field references
  can use ids or names. See `clay tables query --help` for the most up to date information.
- Pagination is via flags: `--limit <n>` (1–100, default 50) and `--cursor <token>`.
  When more rows remain, the response includes a top-level `cursor` — pass it back via
  `--cursor` to fetch the next page.
- Output is `{ data: [ { "<fieldId>": <cell> } ], cursor?, fields? }`, where each `<cell>`
  carries a `status` (`success` / `error` / `running` / `queued` / `retry` /
  `rate_limited` / `awaiting_callback` / `empty`) plus its value.

Typical flow: `clay tables list --filter queryEnabled=true` to find the id → (if needed)
`clay tables update <id> --query-enabled true` → wait, then `clay tables query`. To
export, serialize the JSON `data` array to CSV with a real writer (see below).

### Saving query results to CSV

After a `query-live` or `query` run, save the results locally as a CSV so the user can
access them — **`.results`** for `query-live` (responses are capped, so page with
`LIMIT`/`OFFSET` and append until a page comes back short), **`.data`** for synced
`query`, projecting
each synced cell wrapper to its `value` with an explicit marker for error and pending
cells (they carry no `value`, and a blank would misread as empty). Serialize with a
keyed CSV writer (for example `csv.DictWriter`, with fieldnames seeded from the
response's `fields` plus any extra keys seen in rows), never by hand-writing delimiter
text, prefix string values starting with `=`, `+`, `-`, or `@`
with a single quote (leave numeric cells untouched), and write to a file like
`./query-results.csv`.

## Example: join across tables

"Join our Accounts and Contacts tables and pull the contacts at software companies":

**1. List tables to get their ids.**

```bash
clay tables list --filter queryEnabled=true | jq -r '.data[] | [.id, .name] | @tsv'
# t_accounts123   Accounts
# t_contacts456   Contacts
```

**2. Get each table's schema** so you know field ids, types, and the join key.

```bash
clay tables columns get t_accounts123
clay tables columns get t_contacts456
```

Say `Accounts` has `f_industry` (text) and `f_account_id`, and `Contacts` has
`f_company` that references the account.

**3. Enable querying if needed** (see above — not instant), then run the structured
query. Use the field ids from step 2.

```bash
clay tables update t_accounts123 --query-enabled true
clay tables update t_contacts456 --query-enabled true
```

```bash
echo '{"tables": [{ "id": "t_contacts456" }, { "id": "t_accounts123" }], "join": [{ "table": "t_accounts123", "on": { "left": "f_company", "right": "f_account_id" } }], "filter": { "field": "f_industry", "op": "contains", "value": "software" }}' | clay tables query --query - --limit 100 | jq '.data | length'
```

**4. Page past 100 rows** by passing the previous response's `cursor` back via
`--cursor` until the response no longer returns one:

```bash
echo '{"tables": [{ "id": "t_contacts456" }, { "id": "t_accounts123" }], "join": [{ "table": "t_accounts123", "on": { "left": "f_company", "right": "f_account_id" } }], "filter": { "field": "f_industry", "op": "contains", "value": "software" }}' | clay tables query --query - --limit 100 --cursor CURSOR_FROM_PREVIOUS_RESPONSE | jq -c '.data[]'
```

`clay tables query --help` lists the top-level query keys and pagination flags. Inner
shapes (filter ops, join `on`, `select` / `group_by`) are in the developer docs:
https://developers.clay.com/llms.txt

## Investigating tables

Beyond querying data, the CLI's read commands (`clay tables get`, `columns list|get`,
`rows list|get`) support diagnostic work. These need no query sync. Each investigation
is a focused skill:

| The user wants…                                                    | Skill                 |
| ------------------------------------------------------------------ | --------------------- |
| "what does this table do?" / "explain the {table} workflow"        | `/tables-analyze`     |
| "trace {id}" / "where is {id} and what state is it in?"            | `/tables-trace`       |
| "what's erroring in {table}?" / "show failed rows" (no identifier) | `/tables-error-sweep` |
| "why is {id} stuck/failing?" / "where did {value} come from?"      | `/tables-value-trace` |
| "why aren't new rows being added / why is the import stuck?"       | `/tables-capacity`    |

`/tables-analyze` and `/tables-value-trace` share the column-DAG extraction recipe in
`tables-cli/dependency-catalog.md`.

## Rebuilding a Table as a Workflow

If a user wants to convert their table logic into a Clay workflow (reusable, branching,
or scheduled), use the `workflows` skill to rebuild the enrichment pipeline as
connected nodes.
