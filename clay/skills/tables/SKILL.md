---
name: tables
description: Clay tables — inspect, query, and export data from an existing table, via either the `table` MCP tool (schema + natural-language query, CSV export) or the `clay tables` CLI (list tables, run structured JSON queries with pagination, toggle API query sync). To investigate a table or record, use the focused `/table-*` skills (analyze, trace, error-sweep, value-trace, capacity).
---

## About Clay Tables

Clay is a GTM (go-to-market) data and automation product. Clay tables are similar to Excel or Google Sheets. Each table contains:

- **Fields (columns)**: Can be basic fields (text, numbers, booleans), formula fields (JavaScript expressions), or action/enrichment fields (fetch data, call APIs, run AI agents)
- **Records (rows)**: Usually represent companies or people
- **Sources**: Add rows to tables from external data (APIs, CSV imports, webhooks, Clay's database of 850m+ people and 60m+ companies)

## Not supported:

- **Creating tables**: These surfaces only **read** from tables that already exist — inspect the schema, query data, and export it. **Creating a new table (or adding fields/columns to one) is not supported** via the `table` MCP tool or the `clay tables` CLI. If a user asks to create a table, tell them it isn't supported here and that they'll need to create the table in the Clay app first; you can then work with it once it exists.
- **Pushing data to tables**: These surfaces only **read** from tables — they cannot insert new rows, update cell values, or trigger enrichments. **Adding or updating records is not supported** via the `table` MCP tool, the `clay tables` CLI, or the Public API (its tables surface is query/list-only). `clay tables update` toggles whether a table is queryable (`--query-enabled`); it does not write data. If a user asks to load a list into a table or push results back into one, tell them it isn't supported here and that rows must enter through Clay app.

## Two ways to work with tables

There are two surfaces for reading table data. Pick based on how you're working:

| Surface               | Reach for it when                                                                                                                                                                                                                                                | How                                            |
| --------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- |
| **`table` MCP tool**  | You want a quick, ad-hoc answer from natural language on a **single** table, within the tool's limits (≤ 8 fields, ≤ 5 filters, ≤ 3 group-bys, ≤ 100 rows), plus rich schema/profile metadata.                                                                   | `table(tableId, mode: "schema" \| "query", …)` |
| **`clay tables` CLI** | The query is **complex** or exceeds the MCP tool's limits: **multi-table joins**, reading **more than 100 rows** (paging through a large result set), or richer `filter`/`select`/`order_by`/`group_by`/`field_mode` than natural language can express reliably. | `clay tables list \| query \| update`          |

Both read the same tables. The MCP tool turns natural language into a ClayQL query for you but is capped at a single table and 100 rows; the CLI takes a structured JSON query that supports **joins across multiple tables** and cursor pagination, so it's the right tool for complex queries or pulling large result sets. When in doubt for a quick single-table look, use MCP; for anything complex, joined, or larger than 100 rows, use the CLI.

**Availability:** the two surfaces are gated differently. The `table` MCP tool works on any table the workspace can access. The `clay tables` query surface requires **API table sync** to be enabled for the workspace — available on Enterprise plans. Without it, `clay tables query` and `clay tables update --query-enabled true` fail with `auth_forbidden` ("API table sync is not enabled for this workspace"). That's an account limitation, not a bug or an auth problem — don't retry or re-login; use the MCP tool where it fits, and tell the user to contact Clay about Enterprise access for the rest.

## MCP tool: `table`

Both modes use the `table` MCP tool with a `mode` parameter.

### Schema mode

Get the schema and structure of a Clay table — field names, types, configurations, metadata.

```
table(tableId: "the-table-id", mode: "schema")
```

Returns XML with:

- Table metadata (name, row count, workspace)
- All fields with their types, configurations, and data profiles
- Source information if applicable
- Field group information (waterfalls, etc.)

### Query mode

Query a table using natural language. Generates and runs a SQL (ClayQL) query.

```
table(tableId: "the-table-id", mode: "query", taskDescription: "Show top 10 deals by ARR")
```

Capabilities:

- Filter, group, sort, count, sum, average any field
- Can only get up to 8 fields at a time, with 5 wheres, and 3 group_bys
- Returns up to 100 rows
- Single table only — no joins or CTEs

Examples:

- "How many contacts are in Boston?"
- "Show companies with more than 50 employees sorted by funding"
- "Average deal size by stage"
- "Count of rows where email is not null"

### Saving query results to CSV

After running the `table` tool (mode: query), save the results locally as a CSV file so the user can access them. Convert the JSON results array to CSV format and write it using the Write tool.

Example flow:

1. Run the `table` tool (mode: query) to get results
2. Extract column headers from the first result row
3. Convert each row to comma-separated values (quote fields containing commas)
4. Write to a local file like `./query-results.csv`

## CLI: `clay tables`

The `clay` CLI is Clay's programmatic surface: JSON to stdout, typed errors, and per-command `--help` that documents the exact output shape. Authenticate with `clay login` (run the `setup` skill once if `clay` isn't found or `clay whoami` fails on auth); the workspace is resolved from the stored session.

`clay tables --help` (and `clay tables <cmd> --help`) is the authoritative spec — read it for exact flags, JSON shapes, and error codes.

### Reading rows vs. querying

The CLI reads a table two ways; pick by how much querying power you need:

- **Read rows directly** — `clay tables get`, `columns`, `rows list/get`. Works on any table with no setup. Filtering is exact-match only (`rows list --filter col=value`, ANDed together). Best for quick lookups and pulling cell values as-is.
- **Query** — `clay tables query`. Richer: range / contains / OR filters, **joins across tables**, sorting, grouping, and paging past 100 rows. The table must first be **enabled for querying** (below).

Reach for `query` the moment a plain `rows list --filter` can't express what you need — a range or text match, an OR, a join, sorting, grouping, or a large ordered pull. Otherwise a direct `rows list` is faster and needs no setup.

### Row ordering

Both `rows list` and `tables query` return rows in a stable, consistent order that roughly tends to follow the order rows were created — but treat that as a loose tendency only, never a guarantee. It's approximate, the two commands don't necessarily order rows the same way as each other, and neither matches the order rows appear in the Clay app. So don't rely on position for anything: don't map a row's position in the output to what the user sees on screen, and don't read "the first / most recent N rows" from position. To find a **specific record**, filter by an identifier (`rows list --filter`, or a `tables query` filter) rather than relying on position. `tables query` is the only place order is caller-controllable — pass `order_by` to impose one, but a custom `order_by` returns a single page (it can't be combined with cursor paging).

### List tables

Discover tables and their ids. Each row carries a `queryEnabled` flag for whether the table is enabled for querying.

```bash
clay tables list                       # { data: [{ id, name, description, workbook, queryEnabled }], cursor? }
clay tables list --query-enabled       # only tables enabled for querying
clay tables list --limit 50 --cursor cursor_abc123    # cursor_abc123 = the `cursor` token from a previous page
```

### Enable a table for querying

`clay tables query` can only read a table that's been **enabled for querying**. Toggle it with `update`:

```bash
clay tables update tbl_abc123 --query-enabled true    # { id, queryEnabled: true }
clay tables update tbl_abc123 --query-enabled false
```

Two things to know:

- **Not instant.** Enabling prepares the table for querying in the background, so it isn't queryable the moment `update` returns — larger tables take longer. A `query` run too soon may return no/partial rows; retry after a short wait.
- **Limited per workspace.** A workspace can only have so many tables enabled at once. Check where you stand with `clay tables query-usage` (returns `{ used, limit }`); at the cap, disable a table before enabling another. A `limit` of 0 means API table sync isn't enabled for the workspace at all (see the availability note above).

### Run a structured query

Unlike the MCP tool's natural language (single table, ≤ 100 rows), the CLI takes a **structured JSON query** that supports **joins across multiple tables** and cursor pagination — so it's the right choice for complex queries or reading past 100 rows. The query is read from a file or stdin via `--query`.

```bash
clay tables query --query ./query.json | jq '.data | length'
echo '{"tables":[{"id":"tbl_abc123"}]}' | clay tables query --query - --limit 100
clay tables query --query ./query.json --limit 100 --cursor cursor_abc123
```

- The `--query` payload is the query itself (what to fetch); pagination is separate. Minimal shape: `{ "tables": [{ "id": "tbl_..." }] }`. Beyond `tables`, it may include `filter`, `select`, `join`, `order_by`, `group_by`, and `field_mode`. Field references can use ids or names. See `clay tables query --help` for the most up to date information
- Pagination is via flags: `--limit <n>` (1–100, default 50) and `--cursor <token>`. When more rows remain, the response includes a top-level `cursor` — pass it back via `--cursor` to fetch the next page.
- Output is `{ data: [ { "<fieldId>": <cell> } ], cursor?, fields? }`, where each `<cell>` carries a `status` (`success` / `error` / `running` / `queued` / `retry` / `rate_limited` / `awaiting_callback` / `empty`) plus its value.

Typical flow: `clay tables list --query-enabled` to find the id → (if needed) `clay tables update <id> --query-enabled true` → `clay tables query`. To export, redirect or convert the JSON `data` array to CSV with the Write tool as above.

## Example: combine both surfaces to query across tables

A common pattern uses **both** surfaces together: the CLI to discover tables and run the query, the MCP `table` tool to learn each table's schema so you build the query with real field ids and types. For example, "join our Accounts and Contacts tables and pull the contacts at software companies":

**1. List tables via CLI to get their ids.**

```bash
clay tables list --query-enabled | jq -r '.data[] | [.id, .name] | @tsv'
# tbl_accounts123   Accounts
# tbl_contacts456   Contacts
```

**2. Get each table's schema via the MCP `table` tool.** Do this per table id so you know the exact field ids, types, and which field links the two (the join key). Schema mode also surfaces data profiles that help you write good filters.

```
table(tableId: "tbl_accounts123", mode: "schema")
table(tableId: "tbl_contacts456", mode: "schema")
```

Say the schemas show `Accounts` has `f_industry` (text) and `f_account_id`, and `Contacts` has `f_company` that references the account.

**3. Build a structured query from those field ids and run it via CLI.** The join and >100-row read are why this goes through the CLI rather than the MCP tool. Enable querying first if `queryEnabled` was `false` for either table — and note that a freshly enabled table isn't queryable instantly, so give it a moment (or retry) before the `query` returns full results.

```bash
clay tables update tbl_accounts123 --query-enabled true
```

```bash
clay tables update tbl_contacts456 --query-enabled true
```

A freshly enabled table isn't queryable instantly — give it time (or retry) before the query returns full results.

```bash
echo '{"tables": [{ "id": "tbl_contacts456" }, { "id": "tbl_accounts123" }], "join": [{ "table": "tbl_accounts123", "on": { "left": "f_company", "right": "f_account_id" } }], "filter": { "field": "f_industry", "op": "contains", "value": "software" }}' | clay tables query --query - --limit 100 | jq '.data | length'
```

**4. Page past 100 rows** by passing the `cursor` from the previous response's output back in via `--cursor`. Repeat with each new `cursor` until the response no longer returns one:

```bash
echo '{"tables": [{ "id": "tbl_contacts456" }, { "id": "tbl_accounts123" }], "join": [{ "table": "tbl_accounts123", "on": { "left": "f_company", "right": "f_account_id" } }], "filter": { "field": "f_industry", "op": "contains", "value": "software" }}' | clay tables query --query - --limit 100 --cursor CURSOR_FROM_PREVIOUS_RESPONSE | jq -c '.data[]'
```

`clay tables query --help` lists the top-level query keys (`filter`, `select`, `join`, `order_by`, `group_by`, `field_mode`) and the pagination flags; the exact inner shape — `join`'s `table` / `on.left` / `on.right`, and a filter's `field` / `op` / `value` — comes from the schema and the developer docs below. Use the field ids you read from the MCP schema in step 2 rather than guessing.

Full developer documentation (CLI reference, Public API reference, concepts) lives at:
https://developers.clay.com/llms.txt

## Investigating tables

Beyond querying data, the CLI's read commands (`clay tables get`, `columns list|get`, `rows list|get`) support diagnostic work: what a table's workflow does, what happened to a record, and why. These need no query sync — they read the table directly. Each investigation is a focused skill; match the question and use that skill:

| The user wants…                                                    | Skill                |
| ------------------------------------------------------------------ | -------------------- |
| "what does this table do?" / "explain the {table} workflow"        | `/table-analyze`     |
| "trace {id}" / "where is {id} and what state is it in?"            | `/table-trace`       |
| "what's erroring in {table}?" / "show failed rows" (no identifier) | `/table-error-sweep` |
| "why is {id} stuck/failing?" / "where did {value} come from?"      | `/table-value-trace` |
| "why aren't new rows being added / why is the import stuck?"       | `/table-capacity`    |

Each `/table-*` skill is self-contained. `/table-analyze` and `/table-value-trace` share one helper — the column-DAG extraction recipe in `tables/dependency-catalog.md`.

## Field Types in tables

1. **Basic fields**: Contain text, numbers, or boolean values
2. **Formula fields**: Single-line JavaScript expressions that auto-calculate (use Lodash as `_` and Moment.js)
3. **Action fields**: Run enrichments that fetch data, call APIs, or invoke AI. Each cell needs to be "run" and may cost credits
4. **AI fields**: Special action fields that run LLMs on data (OpenAI, Anthropic, Claygent for web research, Image Generation)
5. **Source fields**: Contain data imported from sources (Clay's company/people/jobs dataset, CSV, webhooks, Clay actions, signals)

## Key Concepts

### Sources

Sources add rows to tables. Types include:

- **Company / People / Jobs data**: Clay CPJ data
- **API Integration**: Clay actions that fetch data from external services
- **CSV Import**: Data imported from CSV files
- **Webhook**: Data received via webhook calls
- **Manual Entry**: Manually entered data
- **Event Monitor (Signals)**: Monitors for events like job changes, news, etc.

### Actions

Actions are enrichments that run on each row. They can:

- Fetch data from 100+ data providers (email, phone, firmographics, tech stack, funding)
- Call external APIs
- Run AI agents (Claygent can browse the web)
- Search Clay's database of 850m+ people and 60m+ companies

### Formulas

Formulas are single-line JavaScript expressions that:

- Use `_` for Lodash and `moment` for date handling
- Auto-calculate when referenced fields change
- Must use optional chaining (`?.`) for safe access
- Cannot use loops, if statements, spread syntax, or template literals

### Waterfalls

Waterfalls are groups of action fields that run in sequence:

- Each action runs only if previous ones failed
- Used to maximize data coverage (e.g., try multiple email providers)
- Have a merge field that combines results

## Rebuilding a Table as a Workflow

If a user wants to convert their table logic into a Clay workflow (e.g., to make it reusable, add branching, or run it on a schedule), use `/workflows` to build a workflow that replicates the table's enrichment pipeline as connected nodes.
