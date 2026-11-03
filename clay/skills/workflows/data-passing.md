# Data Passing in Clay Workflows

How you wire data between nodes depends on the node type. There are two
mechanisms; the shapes below are exactly what `clay workflows nodes create`/`update` accept and what `graph get` / `nodes get`
returns — wire data this way, then `nodes get` / `graph get --mode full` to confirm it saved.
You can edit by sending back the `node` from `nodes get` with your changes: a node read leaves out
fields that have no value, and `null` clears a field (a field that cannot be cleared rejects it).
Two exceptions: on an agent node, send only the fields you change, because sending its agent fields
back can move a node pinned to an older agent version onto the current one; and send a waterfall
node's `waterfallConfig` on its own, never alongside other fields.

## Method 1: Pinned inputs on agent nodes (typed, deterministic)

Use this when the data must be exact (a number, a boolean, a specific structured
field), or comes from another node.

The **upstream node** declares an `outputSchema` describing its structured output.
In its **flat shorthand** it is a map of field name → `{ "type", "description" }` —
allowed flat types are `string`, `number`, `boolean`, `email`, `url`, `select`. Every
flat field **requires a `description`** — the write is rejected without one
(`inputSchema` properties don't need descriptions). The JSON Schema form is covered
below:

```json
{
  "outputSchema": {
    "company_name": { "type": "string", "description": "Company display name" },
    "industry": { "type": "string", "description": "Primary industry" },
    "score": { "type": "number", "description": "Fit score, 0-100" }
  }
}
```

The **downstream agent node** pins each input by adding `sourceNodeId` +
`sourcePath` **directly onto the `inputSchema` property**:

```json
{
  "inputSchema": {
    "type": "object",
    "properties": {
      "company_name": {
        "type": "string",
        "sourceNodeId": "wfn_upstream",
        "sourcePath": "$.company_name"
      },
      "score": {
        "type": "number",
        "sourceNodeId": "wfn_upstream",
        "sourcePath": "$.score"
      }
    }
  }
}
```

The reference lives **inline on the property** (`sourceNodeId` + `sourcePath`).
Use `sourcePath`, not `path`.

Both schemas accept the flat shorthand (dropping the `type: "object"` + `properties`
wrapper) and the full JSON Schema form. The write side accepts exactly what the read side
returns: for every node without a Claygent (code, conditional, terminal, ...), `nodes get`
returns `outputSchema` as JSON Schema, and that value can be sent back unchanged through
`nodes update` or `edit_node`. `code test --output-schema` takes it too when the installed CLI's
`--help` mentions JSON Schema; older CLIs take only the flat map. Flat fields are all required;
JSON Schema keeps its own `required` list. Agent nodes read and write flat fields only.
Workflow function calls are the exception: their `outputSchema` comes from the published
function and any `outputSchema` edit is rejected.

**Schema validation happens in two stages.** A malformed schema is rejected when the node is
created or updated. A valid schema whose values do not match fails when a code or merge node
runs; other node types store the schema without run-time output checks.
Input/trigger JSON Schema describes an email as `{"type":"string","format":"email"}`;
`{"type":"email"}` is only a flat output-field type. Nullable type unions such as
`["string","null"]` are unsupported. Every flat output field becomes required;
`required:false` does not make it optional, and `null` is not a string. For code, use
`code test --output-schema` with the schema you will save (flat fields, or the JSON Schema from
`nodes get` when the installed CLI's help mentions it) and representative missing-data inputs before saving if the installed CLI offers the flag (`clay workflows code test --help`).
Otherwise, test the saved node with `nodes test`; an execution-only code test does not validate
the schema. Use `nodes test` to check the saved schema and mappings in either case.

**Accessing pinned inputs:** in an agent prompt, `{{company_name}}` resolves to
the pinned value.

**Accessing the current list item:** in a **repeating (list mode) agent** node,
`{{__item}}` is the whole item and `{{__item.field}}` one field. Pinned inputs on a
list-mode agent node resolve against the _whole_ upstream output, not the entry, so use
`{{__item...}}` for anything per-item.

**`sourcePath` syntax** is JSONPath: `$.field`, `$.nested.field`,
`$.array[0].name`, `$.results[0].properties.hs_email_domain`.

## Method 2: Action input mapping on tool nodes

Tool nodes (`nodeType: "tool"`) do **not** wire action inputs through
`inputSchema`. Each action parameter is mapped in the tool's `inputMappingConfig`:

```json
{
  "tools": [
    {
      "actionKey": "hubspot-lookup-object",
      "actionPackageId": "a2584689-...",
      "toolType": "clay_action",
      "inputMappingConfig": {
        "objectTypeId": { "type": "static", "value": "0-2" },
        "fields|domain": { "type": "reference", "expression": "{{domain}}" },
        "fields|fieldsToFilterBy": { "type": "static", "value": ["domain"] }
      }
    }
  ]
}
```

Each value is one of:

| `type`             | shape                                                                                         | meaning                                                                                                                |
| ------------------ | --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| `static`           | `{ "type": "static", "value": … }`                                                            | fixed value baked into the node                                                                                        |
| `reference`        | `{ "type": "reference", "expression": "{{var}}" }`                                            | pull from an available variable (upstream output / trigger input)                                                      |
| `coalesce`         | `{ "type": "coalesce", "candidates": [{ "type": "reference", "expression": "{{var}}" }, …] }` | use the first non-empty candidate, in order                                                                            |
| `item`             | `{ "type": "item", "path": "$.field" }`                                                       | the current list item, in list mode (`$` = whole item, `$.field` = one field)                                          |
| `reference` (item) | `{ "type": "reference", "expression": "https://{{__item.field}}/api" }`                       | mix the current list item into surrounding text (list mode); `{{__item}}` = whole item, `{{__item.field}}` = one field |
| `skip`             | `{ "type": "skip" }`                                                                          | leave the parameter unset                                                                                              |
| `map`              | `{ "type": "map", "entries": { "<key>": { "type": "static", "value": … } } }`                 | object-valued parameter (e.g. HTTP headers, a key→value map); each entry is its own `static` or `reference` mapping    |

**Object literals need `map`.** A `static` value only accepts a string, number,
boolean, or array of strings — passing an object literal (or a stringified one) is
rejected or mis-parsed. To build an object value key by key, use the `map` type
with one entry per key. To pass an object an upstream node already produced, keep a
single-expression `reference` (`{ "type": "reference", "expression": "{{headers}}" }`) —
it is type-preserving and passes the whole object, including dynamic keys.

### Coalesce mappings on tool nodes

Use a `coalesce` mapping when conditional branches converge on a Clay action and
one action parameter should take the value produced by whichever branch ran. Add
one `reference` candidate per branch, in the intended priority order:

```json
{
  "inputMappingConfig": {
    "email": {
      "type": "coalesce",
      "candidates": [
        { "type": "reference", "expression": "{{email_from_work_enrichment}}" },
        { "type": "reference", "expression": "{{email_from_crm}}" },
        { "type": "static", "value": "unknown@example.com" }
      ]
    }
  }
}
```

Candidates are ordered fallbacks. Resolution moves to the next candidate only
when the previous value is `null`, `undefined`, or an empty string; `false`,
`0`, empty arrays, and empty objects are values and do not fall through. A
candidate can be only `reference` or `static`; do not nest `coalesce`, `map`,
`item`, `skip`, or LLM mappings inside it.

Every referenced variable must already be available to the converged node
through its `inputSchema`/`inputRefs` or the upstream transition mapper. The
node must be reachable from every referenced branch. After saving, run
`clay workflows graph validate <workflowId>` and fix any "required input is not
available on every execution path" issue before testing.

Use an inline coalesce mapping only for a small number of direct values or simple
`{{variable}}` string templates consumed by one node. When the same coalesced
value is reused downstream, configure a merge node instead.

### Merge nodes

Use a merge node when multiple branches converge and downstream nodes need one
or more coalesced values. It is a reusable, named-output form of a coalesce
mapping: each merge output has its own ordered candidates, and downstream nodes
can reference the resolved output repeatedly.

Prefer a merge node whenever the desired operation can be expressed with
coalesce mappings. Use a code node only when the workflow also needs
computation, non-trivial transformation, or other custom behavior beyond
selecting a candidate value. Merge nodes may not be enabled for every
workspace. If creating one is rejected as unavailable or not enabled, do not
retry; use a code node to produce the same named outputs and reference those
outputs downstream.

For every value to coalesce:

1. Add a property with that output name to the merge node's `inputSchema`.
2. Add a same-named entry to `mergeInputMappingConfig`; it must be a `coalesce`
   mapping with candidates in preference order.
3. Wire every branch that can supply a candidate into the merge node. The merge
   node exposes its resolved input properties as downstream outputs.

For example, two trigger paths may each supply an email address and company
name. Configure a merge node with `email` and `company_name` inputs, then add
one coalesce mapping per output:

```json
{
  "nodeType": "merge",
  "inputSchema": {
    "type": "object",
    "properties": {
      "email": { "type": "string" },
      "company_name": { "type": "string" }
    }
  },
  "mergeInputMappingConfig": {
    "email": {
      "type": "coalesce",
      "candidates": [
        {
          "type": "reference",
          "expression": "{{email_from_trigger_a}}",
          "sourceBindings": {
            "email_from_trigger_a": {
              "sourceNodeId": "<trigger-a-node-id>",
              "sourcePath": "$.email"
            }
          }
        },
        {
          "type": "reference",
          "expression": "{{email_from_trigger_b}}",
          "sourceBindings": {
            "email_from_trigger_b": {
              "sourceNodeId": "<trigger-b-node-id>",
              "sourcePath": "$.email"
            }
          }
        }
      ]
    },
    "company_name": {
      "type": "coalesce",
      "candidates": [
        {
          "type": "reference",
          "expression": "{{company_from_trigger_a}}",
          "sourceBindings": {
            "company_from_trigger_a": {
              "sourceNodeId": "<trigger-a-node-id>",
              "sourcePath": "$.company_name"
            }
          }
        },
        {
          "type": "reference",
          "expression": "{{company_from_trigger_b}}",
          "sourceBindings": {
            "company_from_trigger_b": {
              "sourceNodeId": "<trigger-b-node-id>",
              "sourcePath": "$.company_name"
            }
          }
        }
      ]
    }
  }
}
```

Candidates are ordered fallbacks: resolution proceeds only when the previous
candidate is `null`, `undefined`, or an empty string. Add a static candidate
last only when there is an intentional fallback value. A merge node is not a
legacy fork/join node: it does not coordinate parallel execution; it coalesces
values from paths that have already converged.

Every candidate for one merged output must have the same data type, and that
shared type must match the declared type of the output field. For example, an
`email` output declared as a string cannot coalesce a known array or number
candidate. The canvas validates known candidate types before save; change the
output declaration or candidate mappings until the validation passes.

For each upstream `{{variable}}` in a reference candidate, add a
`sourceBindings` entry keyed by that exact variable name. Its value contains
the `sourceNodeId` and `sourcePath`. Sculptor converts these bindings into the
merge node's internal `inputRefs`; without a binding, the expression is treated
as a workflow-context variable instead of a reference to the named node output.

After saving, read the node back to confirm the schemas and mappings persisted,
then run `clay workflows graph validate <workflowId>`.

**Pipe keys (`parent|sub`):** grouped/nested action parameters are addressed
with a pipe. A `fields` group with `domain` and `fieldsToFilterBy` sub-fields is
mapped as `fields|domain` and `fields|fieldsToFilterBy`.

**Where `inputMappingConfig` is stored depends on the tool type.** A `clay_action`
stores it on the tool and re-syncs every node bound to that tool — which is why node
create/update gives each node its own tool instance. A `clay_function` has no tool
record, so its mapping is stored on the node instead. In both cases, pass the mapping
inside the `tools` entry and expect `nodes get` to return it there.

**Gotcha — don't invent inputSchema variables on tool nodes.** A property added to
a tool node's `inputSchema` that isn't a real action parameter is **silently
dropped on save**, so any `{{var}}` referencing it resolves to nothing. Put the
`reference` directly in `inputMappingConfig` instead (e.g.
`"fields|domain": { "type": "reference", "expression": "{{domain}}" }`), then
`nodes get` the node back to confirm it persisted.

**Wiring a specific upstream output into a parameter.** When the value isn't
already an input the node receives — it's a precise field of an upstream output,
or comes from a node 2+ hops back — give the tool node that input the same way an
agent node pins one (`sourceNodeId` + `sourcePath`) and reference it by name in
`inputMappingConfig`:

```json
{
  "inputSchema": {
    "type": "object",
    "properties": {
      "owner_name": {
        "type": "string",
        "sourceNodeId": "wfn_enrich",
        "sourcePath": "$.result.name"
      }
    }
  },
  "tools": [
    {
      "toolType": "clay_action",
      "actionKey": "hubspot-create-object",
      "actionPackageId": "a2584689-...",
      "inputMappingConfig": {
        "fields|name": { "type": "reference", "expression": "{{owner_name}}" }
      }
    }
  ]
}
```

The input is normalized to the action's own parameters on save, but the binding
is preserved as long as `inputMappingConfig` references it — so the `{{owner_name}}`
reference resolves. `nodes get` the node back and confirm both the input ref and the
mapping persisted.

### Output structure of enrich (tool) nodes

An enrich (tool) node's outputs are flat: the Clay action's returned fields are under `result`, and
its success flag is `success` — both at the top level. When writing `inputRefs` or `sourcePath`
expressions that point at an enrich (tool) node, address the action's fields under `$.result.*`:

```json
{ "sourceNodeId": "wfn_enrich_company", "sourcePath": "$.result.name" }
```

Everything the Clay action returned is inside `$.result.*`; `$.success` is the action's success flag.

To discover the exact field names, in order of preference:

1. Read `outputParameters` from `clay workflows actions schema <packageId> <actionKey>` — the
   action's declared output fields, available before the node has ever run. Each entry's
   `outputPath` is the field, so the path is `$.result.<outputPath>`.
2. Check the `recentOutputPaths` field on the node (populated from the most recent run), or
3. Run the action once with `clay workflows actions test <packageId> <actionKey> --inputs
<json|file|->` and look at the fields under `.result` — those keys will be available as
   `$.result.<field>`. Needed when the action declares no output schema, so `outputParameters`
   comes back empty.

Declared outputs include object and array containers as well as known child fields, with a
`type` for each entry. Every `outputPath` is absolute from the action payload, so prefix it
with `$.result.` as-is. A container with no declared children has unknown contents; it does
not promise an empty object or array. Array child paths use `[0]` as a first-element template.
For the full list, select the container path instead: `parent_companies` is the array,
while `parent_companies[0].name` describes one element's name.

**Example:** if `clay workflows actions test` returns
`{ "result": { "name": "Acme", "domain": "acme.com" } }`, the correct paths are `$.result.name`
and `$.result.domain`.

## Discovering an action's dynamic fields

Some actions only reveal their real parameters once an earlier input is chosen —
a CRM "create object" exposes a different field set per object type; a dependent
dropdown's options depend on a parent selection. The static action schema lists
their containers and `dynamicParameters` paths, but not their revealed fields.
Start with `clay workflows actions schema <packageId> <actionKey> --resolve-dynamic --account <appAccountId>`
to resolve all paths together and inspect
`resolvedInputParameters` and `resolvedDynamicParameters[].errors`. Resolution
hits the live integration, so pass a usable connected account when needed.
For a specific path, use:

```bash
# 1. resolve a dependent dropdown's values (the "driver")
clay workflows actions dynamic-fields pkg_abc123 hubspot-create-object objectTypeId --type select --account acct_abc123
#   → [{ "value": "2-36617481", "displayName": "Pet" }, ...]

# 2. with the driver chosen, resolve the fields it reveals
clay workflows actions dynamic-fields pkg_abc123 hubspot-create-object fields --type input --account acct_abc123 --inputs '{"objectTypeId":"2-36617481"}'
#   → field objects; each "name" is already pipe-namespaced: "fields|name", "fields|age", ...
```

- `--type select` resolves a dependent dropdown's values; `--type input` resolves
  the revealed field set. The `value`s and `name`s returned are exactly what go in
  `inputMappingConfig` (`objectTypeId` as a `static` value, `fields|<sub>` keys).
- It's iterative: fill one input, then re-run with it in `--inputs` to resolve the
  next dependent parameter.
- A revealed field can itself be a dynamic select. It isn't listed in
  `dynamicParameters`; resolve it at the container's path plus its key (revealed
  `excluded_reps|<key>` → `excluded_reps.<key>`). Parameter descriptions may name
  other derived paths — check them.
- When reading or editing an existing tool node, pass the node's current `static`
  `inputMappingConfig` values as `--inputs`, keyed exactly as stored (e.g.
  `fields|name`). Resolvers that depend on earlier selections return empty
  results, often with no error, when those inputs are missing or shaped differently.
- Preconditions: the driver must be a concrete value in `--inputs` (a
  `{{reference}}` won't resolve at design time), and `--account` is required for
  actions that authenticate. Reuse the selected account, or list accessible connections
  with `clay app-accounts list --filter type=<appAccountType>` when the provider's
  connection type is known. Pass the chosen account's `id` as `--account`.

## Choosing a method

| Scenario                                             | Method                                                                                                                                                  |
| ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Numeric scores, IDs, booleans into an **agent** node | Pinned inputs (`sourceNodeId`/`sourcePath`)                                                                                                             |
| Data from 2+ hops back into an **agent** node        | Pinned inputs                                                                                                                                           |
| Any input into a **tool** node                       | `inputMappingConfig` (`static` / `reference`)                                                                                                           |
| An input into a **repeating (list mode) tool** node  | Enable `listMode: true` + `listEntriesRef` on the node first (parent skill), then `inputMappingConfig` `item` (`{ "type": "item", "path": "$.field" }`) |
| An input into a **repeating (list mode) agent** node | `{{__item}}` / `{{__item.field}}` in the prompt                                                                                                         |
