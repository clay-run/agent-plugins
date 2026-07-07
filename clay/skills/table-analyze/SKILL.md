---
name: table-analyze
description: Clay tables — analyze what a table does: reconstruct the column DAG, stage it, and narrate the workflow encoded in its columns. Use when the user asks "what does this table do?", "explain the {table} workflow", "walk me through this table", or "what's set up here?".
allowed-tools: Bash(clay *), Bash(jq *), Read
---

# Playbook: analyze table

**Use when:** "what does this table do?", "explain the {table} workflow", "walk me through this table", "what's set up here?" — a question about the table's **structure and the workflow encoded in its columns**, not about any single record.

A Clay table is a column DAG: `source` and input `basic` columns are roots; `basic` formula columns and `action` (enrichment) columns depend on the `{{f_xxx}}` tokens in their settings. Analyzing the table = reconstructing that graph, ordering it into stages, and narrating what it does. Cheap and read-only: ~3 commands (metadata + columns + a row sample).

**Finding the table:** resolve it to a `tbl_...` id with `clay tables list`, filtered client-side with `jq` on `.name` / `.workbook.name` — don't use `--query-enabled` (it hides non-synced tables). If the user named no table or workbook, ask rather than sweeping the workspace. (ID prefixes: `tbl_` table, `f_` column, `rec_` row, `wbk_` workbook.)

## 1. Frame the table — `clay tables get`

(The output is discriminated on `type` — shape in `clay tables get --help`.) Read off the frame the workflow sits in:

```bash
clay tables get $TABLE | jq .
```

- `type` — `"archive"` means this is an archive companion (its `parentTableId` points at the regular table); analyze the parent instead, the archive has no workflow of its own.
- `rowCount` — current size.
- `archive` — non-null means processed rows **flow out** to an archive, indexed on `archive.searchableFieldFormula`.

Where data **enters** and at what scale comes from the columns (step 2): `source` columns carry `sources[]` with each attached source's `numSourceRecords`.

## 2. Build the dependency catalog — `clay tables columns get`

This is where the graph lives. Run the token-extraction recipe in `tables/dependency-catalog.md` over `clay tables columns get $TABLE`. It yields one entry per column — `{ id, name, type, role, integration, gate, dependsOn: [names] }` — resolving every `{{f_xxx}}` edge (including those in `formulaWaterfall` and `formulaMap` keys) to a column name. `dependsOn` are the upstream columns; `gate` (when set) is the condition under which an action runs.

## 3. Stage the graph

Order the catalog into stages by dependency depth — roots first, then columns whose deps are all already placed, and so on:

- **Stage 0 (roots):** `source` columns and `input` basics (empty `dependsOn`). This is the raw data.
- **Each next stage:** columns whose `dependsOn` are all in earlier stages.
- `{{f_xxx}}` **never crosses tables**, so the whole graph is self-contained — every edge resolves within this column set. (A token that resolved to a bare `f_id` rather than a name = a deleted/renamed column; note it.)

This left-to-right order ≈ the column order in the Clay UI and gives you the pipeline.

## 4. Light health read — sample rows

`clay tables rows list … --limit 10` (no separate sample command) for a rough per-column status read — which columns mostly run vs sit idle or error:

```bash
clay tables rows list $TABLE --limit 10 \
  | jq '
    [ .data[].cells | to_entries[] ]
    | group_by(.key)
    | map({ col: .[0].key,
            n: length,
            statuses: (group_by(.value.status) | map({ (.[0].value.status): length }) | add) })'
```

Map `col` ids to names from the catalog. This is a **sample of ≤10 rows**, so treat it as indicative, not a true rate — say so. Statuses are lowercase (`success`, `empty`, `error`, `queued`/`running`/…). If a stage shows heavy `error`, offer to hand off to `/table-error-sweep` for the real picture. On a query-enabled table, `tables query` group-bys can add exact value distributions to the narrative — statuses still come from the sample (they aren't queryable).

## 5. Report — narrative + ASCII DAG

Lead with the source(s), show the staged DAG with each column's integration and gate, then a one-paragraph plain-English summary. Append the sampled health read.

```
People — 1,543 rows · source: CSV Import (1,543) · archives to tbl_xyz789 (on Email)

Stage 1  Domain        (basic, formula)      ← Company
Stage 2  Find Email    (action: Prospeo)     ← Domain
              gated: only runs if {{Domain}} is present
Stage 3  Enrich Person (action: Clearbit)    ← Find Email
Stage 4  Push to HubSpot (action: HubSpot)   ← Enrich Person
              gated: only runs if {{Find Email}} is present

→ This table takes companies from a CSV, derives each company's domain, finds a
  contact email via Prospeo (when a domain exists), enriches the person via
  Clearbit, and syncs the result to HubSpot when an email was found. Processed
  rows are archived by email. Integrations used: Prospeo, Clearbit, HubSpot.

Health (sampled, 10 rows): Domain 10/10 success · Find Email 8 success / 2 empty ·
  Enrich Person 7 success / 1 error / 2 empty · Push HubSpot 7 success / 3 empty.
  Indicative only (small sample) — run /table-error-sweep for true error counts.
```

Keep the narrative honest to the graph: only claim an edge the tokens actually show, and describe a gate exactly as its `conditionalRunFormulaText` reads (don't invent the condition).

## Hand-offs

- A specific value's origin / why one action didn't fire → `/table-value-trace` (uses the same token extraction, walking one column backward).
- Heavy errors in a stage → `/table-error-sweep`.
- "Rows aren't being added" surfaced by metadata → `/table-capacity`.
