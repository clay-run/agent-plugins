# Dependency catalog — the column-DAG extraction recipe

`/table-analyze` and `/table-value-trace` both reconstruct a table's column DAG the
same way. A Clay table is a column DAG: `source` and input `basic` columns are
roots; `basic` formula columns and `action` (enrichment) columns depend on the
`{{f_xxx}}` tokens in their settings. The dependency edges are the `{{f_xxx}}`
tokens inside the **camelCase** settings:

- `basic` → `settings.formulaText` (and `settings.formulaWaterfall`)
- `action` → each `settings.inputsBinding[].formulaText`, the values inside
  `settings.inputsBinding[].formulaMap` (a nested formula tree), and
  `settings.conditionalRunFormulaText` (the run gate)

Extract every field reference per column — `{{f_xxx}}` tokens in the formula
strings **and** `formulaMap` keys (which are field ids) — and resolve each to a
name. One pass over `clay tables columns get` (output is `.data[]`):

```bash
clay tables columns get $TABLE \
  | jq '
    def tokens: [scan("\\{\\{(f_[A-Za-z0-9_]+)\\}\\}")] | flatten | unique;
    .data as $cols
    | ($cols | map({key: .id, value: .name}) | from_entries) as $name
    | $cols
    | map(
        {
          id, name, type,
          integration: (.settings.authAccountId // null),
          gate: (.settings.conditionalRunFormulaText // null),
          # field refs on this column: {{f_}} tokens in every formula string
          # (incl. formulaWaterfall entries, which are string | {formula}) plus
          # formulaMap keys (field ids, action inputsBinding only):
          dependsOn: (
            (
              ( [ .settings.formulaText? ]
                + [ .settings.conditionalRunFormulaText? ]
                + [ (.settings.inputsBinding // [])[] | .formulaText? ]
                + [ (.settings.inputsBinding // [])[] | (.formulaMap // {}) | .. | strings ]
                + [ (.settings.formulaWaterfall // [])[] | if type == "string" then . else .formula end ]
              )
              | map(select(. != null)) | join(" ") | tokens
            )
            + [ (.settings.inputsBinding // [])[] | (.formulaMap // {}) | keys[] | select(test("^f_")) ]
            | unique
            | map($name[.] // .)        # id -> name; keep id if column is gone
          )
        }
      )
    | map(. + {
        role: (
          if   .type == "source"                      then "source (root)"
          elif .type == "action"                      then "enrichment"
          elif (.dependsOn | length) > 0              then "derived (formula)"
          else                                              "input"
          end)
      })'
```

Each entry: `{ id, name, type, role, integration, gate, dependsOn: [names] }`.
`dependsOn` are the upstream columns; `gate` (when set) is the condition under
which an action runs. A token that resolved to a bare `f_id` rather than a name = a
deleted/renamed column; note it. `{{f_xxx}}` **never crosses tables**, so the whole
graph is self-contained — every edge resolves within this column set.
