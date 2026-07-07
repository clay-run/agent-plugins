---
name: table-capacity
description: Clay tables — check the row-capacity ceiling when imports stall, before assuming a run/config/enrichment problem. Use when the user asks "why aren't new rows being added?", "why is the import stuck?", or "is this table full?".
allowed-tools: Bash(clay *), Bash(jq *), Read
---

# Playbook: capacity check

**Use when:** "why aren't new rows being added?", "why is the import stuck?", "is this table full?", or any question about rows failing to appear. Check capacity **before** assuming a run, config, or enrichment problem — a full table silently stops accepting rows, which looks like a broken import.

**Scope:** regular tables only. Archive tables are not subject to this ceiling — if the user points at an archive (`tbl_...` that came from another table's `archive.tableId`), say the check doesn't apply and redirect to the parent table.

## The rule

A Clay table stops accepting new rows once it reaches its **row ceiling**. The ceiling is **50,000 by default**, but it is plan- and table-dependent — plans can set it lower, and per-table overrides can raise it — and the CLI does not expose the effective value. The same ceiling logic applies to:

- **`rowCount`** — the table's own row total (`clay tables get`). At the ceiling, the table won't take new rows.
- **each source's `numSourceRecords`** — a source feeding the table, read from the table's `source` columns (`clay tables columns list` → `sources[]` on each source column). A capped source can't push more records in, even if the table itself has room.

So the table is constrained if **`rowCount` OR any source's `numSourceRecords`** is at its ceiling. Evaluate every source, not just the largest.

## Procedure

1. Resolve the table to a `tbl_...` id — `clay tables list`, filtered client-side with `jq` on `.name` / `.workbook.name` (don't use `--query-enabled`; it hides non-synced tables). If the user named no table or workbook, ask rather than sweeping the workspace.
2. Run **`clay tables get`** for `rowCount`, and **`clay tables columns list`** for the source counts (shapes in each command's `--help`). Two commands — no row scan needed.
3. Read the numbers against the default ceiling (source counts live on source columns):

```bash
ROWCOUNT=$(clay tables get $TABLE | jq '.rowCount')
clay tables columns list $TABLE \
  | jq --argjson rowCount "$ROWCOUNT" '
    [ .data[] | select(.type == "source") | .sources[] | {name, numSourceRecords} ] as $sources
    | {
        rowCount: $rowCount,
        sources: $sources,
        peak: (([$rowCount] + [$sources[].numSourceRecords]) | max),
        defaultCeiling: 50000
      }'
```

## Interpreting the numbers

- **At or above 50,000** (rowCount or any source) → the table has hit the default ceiling and new rows are being rejected. This is the answer.
- **Stuck at a suspiciously round number below 50k** (rowCount pinned at e.g. exactly 25,000 while an import is supposedly running) → likely at a **lower plan ceiling**. The CLI can't confirm the effective limit — report the pattern and say so, rather than ruling capacity out.
- **Below the ceiling and moving** → capacity is not the blocker; look elsewhere.

**Proximity is not urgency.** Don't classify "close to the ceiling" as a problem by itself — whether 47k matters depends entirely on how fast the table is filling. When the user needs a runway estimate, measure the fill rate: read `rowCount`, wait a few minutes, read it again, and report **time to ceiling** (`headroom / rate`), not percent-of-ceiling. If the counts aren't moving, there is no urgency to report — just state the headroom.

## Answering

Lead with the verdict, then the number that drives it. Name whether it's the table's own `rowCount` or a specific source.

**FULL — table's own rows:**
```
People — FULL (rowCount 50,000, the default ceiling).
The table has hit its row ceiling, so new rows are being rejected.
That's why the import isn't adding records — it's not a run or config issue.
Fix: split into another table, or remove rows to free capacity.
```

**FULL — a source is capped:**
```
Leads — FULL via source "Salesforce Import" (numSourceRecords 50,000).
rowCount is 41,200, so the table itself has room, but that source can't push more
records in. New rows from Salesforce won't appear until the source is under its cap.
```

**Not full — with headroom and, when asked, runway:**
```
Accounts — not at the ceiling (rowCount 47,300; 2,700 rows of headroom against the
default 50k). Measured fill rate ~600 rows/hour over the last 5 minutes → roughly
4-5 hours to the ceiling at the current pace. Worth splitting or pruning today.
```

```
Contacts — not at the ceiling (rowCount 12,400; ~37,600 rows of headroom). Capacity
isn't the problem here.
```

When capacity is ruled out, move on to whatever the real question was (an errored source, an enrichment that didn't run, etc.). If the user came in with "rows aren't appearing," hand off to `/table-error-sweep` or `/table-trace` from here.

## Notes

- **No source columns** → the check reduces to `rowCount` alone (the jq handles this).
- **Multiple sources** → report each source's count; the constraint is whichever one (or the table) is at its ceiling, so don't stop at the first.
- The ceiling is product behavior, not something the CLI returns — the commands only give you the counts, and 50,000 is the default, not a guarantee. Rejection behavior (counts pinned while an import runs) is the ground truth.
