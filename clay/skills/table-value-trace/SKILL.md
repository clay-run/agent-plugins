---
name: table-value-trace
description: Clay tables — explain one cell by walking a column backward through its dependencies and run-gate to the origin or root cause. Use when the user asks "where did this value come from?", "why did {action} error?", "why didn't {action} run?", or "why is this value empty?".
allowed-tools: Bash(clay *), Bash(jq *), Read
---

# Playbook: value-trace

**Use when:** you have a record and want to explain **one cell** — "where did this email come from?", "why did Enrich Person error?", "why didn't Push to HubSpot run?", "why is this value empty?". This walks a single column **backward** through its dependencies to find the origin or the root cause. Causation, not state — `/table-trace` gives you the state snapshot first.

The method combines two things:
- **Structure** — column settings tell you the edges: who feeds whom (`{{f_xxx}}` tokens in `formulaText` / `inputsBinding` / `formulaMap`), and the run gate (`conditionalRunFormulaText`).
- **This row's data** — `clay tables rows get` tells you what each cell on *this specific row* actually holds and its status.

Structure gives the edges; the row gives the values along them. You need both.

`{{f_xxx}}` references **never cross tables**, so the entire walk stays within the row's own table.

## 1. Anchor to the row and the target cell

You need this row and the target column. If you don't have the row yet, locate it first (`/table-trace`, or a single value search — `tables query` when the table is query-enabled, else `rows list --filter`). Identify the **target column** — the one whose value, error, or non-run you're explaining — and its `f_id`. The explanation needs the row's full cell data — every cell's `status`, `value`, `fields`, and `error`; a `tables query` result already carries all of that, and `rows get` provides it when you hold a `rec_...` id (step 3).

## 2. Get the structure — `clay tables columns get`

On the table the row lives in. Build the dependency catalog with the token-extraction recipe in `tables/dependency-catalog.md` — it yields `{ id, name, type, role, integration, gate, dependsOn }` per column. You only need to walk the target column and its transitive `dependsOn`, but computing the whole catalog once is cheap and lets you resolve every edge by name.

## 3. Get this row's data

You need every cell's `status`, `value`, `fields`, and `error` on this row. If you located the row via `tables query`, its result already carries all of that — use it directly. Otherwise (the `rows list` path, or you already hold a `rec_...` id), fetch it with `clay tables rows get`:

```bash
clay tables rows get $TABLE $ROW | jq .
```

For any column you visit, read `status`, `value`, `fields`, and `error` (a message string) per cell — under `.cells["f_xxx"]` in a `rows get` result, or `["f_xxx"]` directly in a `tables query` row.

## 4. Walk backward from the target

Start at the target cell and follow `dependsOn` upstream, reading each upstream cell's actual state from the row, until you reach the cause (or a `basic`/`source` root). Branch on what the target cell shows:

### Explaining a value ("where did X come from?")
- **`basic` formula column** → the value is computed from `formulaText`; its `dependsOn` are the inputs. Read those upstream cells' values (`.value`), and recurse into any that are themselves derived, until you reach roots (`source` / input `basic`). Report the chain that produced the value.
- **`action` column** → the value is the action's output. Read its `fields` (the structured payload, populated on `rows get`) for what it actually returned, and its `inputsBinding` for what fed it; resolve each input's `{{f_xxx}}` to the upstream cell and show the value that went in.

### Diagnosing `error`
- Read `error` (the message string) on the target cell. Classify the cause (same patterns as `/table-error-sweep` step 5: provider throttling, auth via `integration`/`authAccountId`, bad/missing input, provider rejection).
- Then check whether the cause is **upstream**: look at the cells this column `dependsOn`. If an input cell is empty, `error`, or hasn't run, the failure likely cascades from there — keep walking back. Distinguish "this action genuinely failed" from "this action got bad/no input because an upstream column did."

### Diagnosing `empty` (hasn't run / no value)
- **Check the gate first.** If the column has a `gate` (`conditionalRunFormulaText`), evaluate it against this row's actual cell values. A falsy gate is the usual reason an action sits at `empty` with no error — report the condition and which input made it falsy (e.g. "gated on `{{Domain}}`, and Domain is empty on this row"). (A gated skip can also surface as an `error` whose message names the run condition — treat that the same way.)
- **No gate, still empty** → an upstream input is `queued`/`running`/`empty`, so this column hasn't been reached yet. Walk back to find the first column that hasn't produced, and report that as the bottleneck.

### `queued` / `running` / `retry` / `rate_limited` / `awaiting_callback`
- Still processing (or waiting on an upstream that's processing). Note it and, if useful, point at the upstream cell it's waiting on.

## 5. Report — lead with the cause, then the chain

State the answer first (the origin, or the root cause), then show the backward chain that supports it with the actual per-cell values/statuses on this row.

**Value origin:**
```
"Enrich Person" → company "Acme Inc" came from Clearbit, keyed off the email.
  Push HubSpot ← Enrich Person.company = "Acme Inc"
  Enrich Person (Clearbit) ← Find Email = "jane@acme.com"
  Find Email (Prospeo)     ← Domain = "acme.com"
  Domain (formula)         ← Company = "Acme" (CSV import)
```

**Root cause of a failure / non-run:**
```
"Push to HubSpot" didn't run because it's gated on an email, and there isn't one.
  Push to HubSpot   empty   gate: only if {{Find Email}} present
  Find Email        success but empty value ("no email found")   ← Domain
  Domain            success = "acme.com"
Root cause: Find Email returned no email for this domain, so the HubSpot push
was correctly skipped. The fix is upstream (email discovery), not the push.
```

Keep the chain honest: only show edges the tokens actually establish, quote a gate exactly as its `conditionalRunFormulaText` reads, and ground each step in the value that cell really holds on this row.

## Hand-offs

- Want the full per-cell snapshot or to confirm where the record lives → `/table-trace`.
- The same failure across many rows, not just this one → `/table-error-sweep`.
- Understand the whole table's workflow, not one value → `/table-analyze`.
