---
name: table-error-sweep
description: Clay tables — sweep a table for errored rows and report grouped by root cause (not a specific record). Use when the user asks "what's erroring in {table}?", "show failed rows", or "is {action} failing?".
allowed-tools: Bash(clay *), Bash(jq *), Read
---

# Playbook: error sweep

**Use when:** "what's erroring in {table}?", "show failed rows", "is {action} failing?" — a table-level question with no specific record in hand. Goal: find the errored rows, read their messages, and report **grouped by root cause**, not row by row.

Only **`action`** columns can be in `error`. `basic` and `source` columns don't error (a formula-backed basic can, rarely), so the sweep is about action columns.

## 1. Understand the table first

Before sweeping, learn what *can* error.

1. Resolve the table to a `tbl_...` id — `clay tables list`, filtered client-side with `jq` on `.name` / `.workbook.name` (don't use `--query-enabled`; it hides non-synced tables). If the user named no table or workbook, ask rather than sweeping the workspace.
2. **`clay tables columns get $TABLE`** (shape in the command's `--help`). Build the picture:
   - Which columns are `type: "action"` — these are the ones that fail. Keep a `f_id → name` map for readable reporting.
   - For each action column, note `authAccountId` (auth-related failures), `conditionalRunFormulaText` (a gate — a skipped action usually shows as `empty`, not a failure), and `inputsBinding` (what feeds it — needed if a failure turns out to be a bad/missing input).
3. **If the table has no action columns**, errors are unlikely — say so, and confirm with a one-page scan (step 3) before concluding.

## 2. Settle the scope: one column or general

- **User named a specific action** ("is Enrich Company failing?") → map that name to its `f_id` from step 1 and scope the client-side filter (step 3) to that column.
- **User asked generally** ("what's erroring?") → sweep across **any** column in `error`.
- **Ambiguous name / multiple action columns match** → show the action columns and let the user pick, or default to the general sweep and break the results down by column.

## 3. Find the errored rows

Cell status isn't filterable server-side on either path, so a sweep pages through the rows and picks out the errored cells client-side. Choose the scan by whether the table is query-enabled:

**Query-enabled → scan with `tables query`.** Each cell comes back with its `status` and, on an error, its `error` message — so one pass finds the failures *and* their messages (skip step 4). Paginate via the top-level `cursor`:

```bash
echo '{"tables":[{"id":"'"$TABLE"'"}]}' \
  | clay tables query --query - --limit 100 \
  | jq '{next: .cursor,
         errored: [ .data[]
           | [ to_entries[] | select(.value.status == "error") | { col: .key, msg: .value.error } ]
           | select(length > 0) ]}'
```

**Not query-enabled → walk `clay tables rows list` pages** and filter client-side on cell `status` (list output carries every cell's status); the full messages then come from `rows get` (step 4). Don't enable sync just for a sweep — it's an escalation that costs a limited slot.

```bash
# One page: errored rows and which columns errored (add more pages via .cursor)
clay tables rows list $TABLE --limit 100 \
  | jq '{next: .cursor,
         errored: [ .data[]
           | { id, cols: (.cells | to_entries | map(select(.value.status == "error")) | map(.key)) }
           | select(.cols | length > 0) ]}'
```

Paginate via the top-level `cursor` (pass it back with `--cursor`) until it's absent. A listing covers the rows that existed when its first page was fetched, so the walk terminates even on an actively-importing table. Use `rowCount` from `clay tables get` to budget: a full sweep of a big table is `rowCount / limit` calls under the rate limit — for very large tables, sample pages first and say you sampled.

## 4. Read the error messages

Only needed for the `rows list` path — if you swept via `tables query`, the messages are already in that result, so skip to step 5. The `rows list` scan tells you *which* rows and columns erred, but its `error` strings are abbreviated labels; the full messages live on `clay tables rows get`:

```bash
clay tables rows get $TABLE $ROW \
  | jq '.cells
        | to_entries
        | map(select(.value.status == "error"))
        | map({col: .key, msg: .value.error})'
```

Respect the rate limits — batch `rows get` calls in small groups (≈3) and back off on exit 4 (`rate_limited`, honor `details.retryAfter`).

**Don't silently cap.** If there are many errored rows, you usually don't need to fetch all of them to characterize the failure — fetch until the set of *distinct* messages stabilizes (new rows stop introducing new messages), then state how many rows you sampled out of the total (`rowCount` from `clay tables get`, and the ids you collected). Never imply full coverage when you sampled.

A single row can have **multiple** errored action cells (general sweep). Capture each errored cell, and map `col` back to the column name from step 1.

## 5. Diagnose — group by root cause

Aggregate the `{col, msg}` pairs across rows. Group by message (normalize near-identical messages — strip row-specific values like emails or ids so "No email for john@x" and "No email for jane@y" collapse to one cause). For each group, infer the cause using what step 1 told you:

| Message pattern | Likely root cause | Direction |
|-----------------|-------------------|-----------|
| "rate limit", "429", "quota", "throttled" | Provider throttling on this action | Usually transient — retriable; check `customRateLimitRules` / `batchRunSettings` |
| "invalid api key", "unauthorized", "auth", "credential" | The action's connected account (`authAccountId`) is bad/expired | Reconnect the integration account |
| "no {x} found", "no input", "missing", empty-input | An **upstream** column produced nothing, so this action had no usable input | Trace the input (`inputsBinding` → upstream column) — hand to `/table-value-trace` |
| "run condition not met" / conditional gate | **Not a real failure** — `conditionalRunFormulaText` evaluated falsy and the action was intentionally skipped | Usually expected; note a gated skip more often shows as `empty` than as an errored cell |
| provider-specific error text | The downstream provider rejected the request | Read the message literally; often a data-quality issue in the input |

Separate **genuine failures** from **expected gating**. Don't let conditional skips inflate the failure count — call them out separately.

## 6. Report

Lead with the count and the breakdown by cause; put the analysis, not the raw rows, front and center.

```
Lead Enrichment — 37 rows with errored action cells (all 1,543 rows scanned; 12 fetched for messages).

By cause:
  • 28 — Enrich Company: "Rate limit exceeded for Clearbit API"
         → provider throttling. Transient/retriable; consider a rate-limit rule or smaller batches.
  • 6  — Enrich Person:  "No email found for input"
         → upstream "Find Email" returned nothing, so Enrich Person had no email to use.
            Root cause is upstream, not this action. (/table-value-trace Find Email to confirm.)
  • 3  — Enrich Person:  "Invalid API key"
         → the connected account for this action is expired. Reconnect it.

Root cause: the dominant failure (28/37) is Clearbit throttling on Enrich Company —
retriable and not a data problem. A secondary cluster traces back to Find Email
producing no email upstream.
```

If the sweep found no errored cells, report that nothing is currently erroring — and if the underlying complaint was "rows aren't appearing," redirect to `/table-capacity` (a full table looks like a failure but produces no errored cells).

## Hand-offs

- A specific errored row the user wants to understand end-to-end → `/table-trace`.
- An error that traces to a bad/missing **input** → `/table-value-trace` (walk `inputsBinding` upstream).
- "Rows aren't appearing" with no errors found → `/table-capacity`.
