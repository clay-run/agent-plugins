---
name: table-trace
description: Clay tables — locate a record by identifier and snapshot its state: which table(s) hold it and each cell's status. Use when the user has an id and asks "trace {id}", "where is {id}?", "what enrichments ran for this lead?", or "is this record done?".
allowed-tools: Bash(clay *), Bash(jq *), Read
---

# Playbook: trace a record

**Use when:** you have an identifier and want to find the record and see its overall state — "trace 12345", "where is jane@acme.com?", "what enrichments ran for this lead?", "is this record done?". This is a **locate + snapshot**: which table(s) hold it, and each cell's status. It does **not** explain *why* a cell holds what it holds — that's `/table-value-trace`, which this playbook hands off to.

Treat each in-scope table independently. Tables may not share identifiers or have any relationship; presence (or absence) in one says nothing about another.

## 1. Settle scope

Resolve which table(s) to look in: `clay tables list`, filtered client-side with `jq` on `.name` / `.workbook.name` (don't use `--query-enabled` — it hides tables that aren't query-enabled), or a `tbl_...` id directly. If the user named no scope, **ask** — don't sweep the whole workspace. `{id}` is whatever the user gave (email, HubSpot ID, row id, etc.). (ID prefixes: `tbl_` table, `f_` column, `rec_` row, `wbk_` workbook.)

If `{id}` is already a `rec_...` row id and the table is known, skip discovery and go straight to **get the row** (step 4).

## 2. Per table: find the identifier's column and archive linkage

For each in-scope table:

- **`clay tables columns list $TABLE`** — find the column that holds this kind of identifier by matching names (`Email` for an email, `HSID`/`HubSpot ID` for a HubSpot id, etc.). Cache the `f_id → name` map and note column types. The match column must be `basic` to value-filter on it. If several columns could match, or none does, show the columns and ask which to search.
- **`clay tables get $TABLE`** — read `archive`. If `archive` is non-null, resolve `archive.searchableFieldFormula` (a `{{f_xxx}}`) to its column via the columns list. Plan to search the archive **only if** `{id}` is the value of that indexed column; otherwise the archive isn't searchable by this identifier.

## 3. Search for the record

**If the active table is `queryEnabled`, locate the record with `tables query`** — its server-side filter is more forgiving (`contains`, case-insensitive matching) and scales, so it's the primary tool when query is on. The result carries each matching row's full cell content — value, `fields`, `status`, and any `error` message — so it doubles as the state snapshot; no follow-up call needed:

```bash
echo '{"tables":[{"id":"'$TABLE'"}],"filter":{"field":"f_abc123","op":"contains","value":"jane@acme.com"}}' \
  | clay tables query --query - | jq .
```

**Otherwise, use `clay tables rows list`** with a value filter on the identifier column (shape in the command's `--help`):

```bash
clay tables rows list $TABLE --filter f_abc123="jane@acme.com" | jq .
```

`rows list --filter` is exact match, **case-sensitive**. If it comes back empty (`{ "data": [] }`), retry **once** with a single predictable variant (lowercase for emails/domains, trim whitespace, or the casing a row sample shows), then stop guessing — say it wasn't found in this table and ask the user to confirm exact spelling/casing.

Where the archive applies (step 2), search it with `rows list` — archives are never query-enabled, so `tables query` is not an option; they're searchable only on the fixed `f_archive_index` column. Filter it by its indexed value (single filter; single capped page, no cursor; values over 255 characters are rejected — pass the first 255):

```bash
clay tables rows list $ARCHIVE --filter f_archive_index="jane@acme.com" | jq .
```

Respect the rate limits — batch in small groups, back off on exit 4.

Capture each cell's `status` (and value or error) for the snapshot. A `tables query` result already includes `fields` and full `error` messages. On the `rows list` path, action cells show `fields: null` and abbreviated error labels — get the full detail in step 4. (`rows list` / `rows get` also carry the row's `id` and `updatedAt`, which `tables query` does not.)

## 4. Pull full state where it matters

If you located via `tables query`, you already have the full snapshot from step 3 — skip this. On the `rows list` path, follow up with **`clay tables rows get`** when:

- any cell is `error` — you need the full `error` message (list only carries an abbreviated label), or
- the user asked for actual values / enrichment output — `fields` (structured action output) is only populated on `rows get`.

```bash
clay tables rows get $TABLE $ROW \
  | jq '.cells | to_entries | map({col: .key, status: .value.status, value: .value.value, err: .value.error})'
```

Map `col` ids to names from step 2. (`err` is the message string, present only on `error` cells.)

## 5. Report — per table, independent findings

Lead with where it is and its overall state; list action/derived columns with status (and value or error where useful). Label each table **active** vs **archive**. Group statuses so the snapshot reads at a glance.

The `rec_` row id is an internal handle, not a report field — you found the record by its business identifier, so lead with that; only show a `rec_` id when you already have one (the `rows list` / `rows get` path). `updatedAt` isn't in `tables query` output either, so fetch it with a single `rows list --filter` on the identifier **only when freshness matters** — the active-vs-archive comparison below, or the user asking how recent the data is. Otherwise omit it.

```
Lead Enrichment — archive (updated 2026-04-10):
  Find Email     success  → "jane@acme.com"
  Enrich Person  success  → {name, title, company}
  Push HubSpot   success

Account Match — active (updated 2026-04-12):
  Match Account  queued
  Map Fields     empty
```

- **Found in both active and archive** → likely re-processed; compare `updatedAt` and say which is newer.
- **Not found** in an in-scope table → say so plainly; it may live in a table you didn't search, or the identifier may be off. Don't treat absence as proof of anything about another table.
- **An `error` or surprising/empty value** the user wants explained → that's where this playbook ends and `/table-value-trace` begins.

## Hand-offs

- Explain *why* a specific cell errored, is empty, didn't run, or holds the value it does → `/table-value-trace`.
- Table-wide failures rather than one record → `/table-error-sweep`.
- "It's not here and nothing's being added" → `/table-capacity`.
