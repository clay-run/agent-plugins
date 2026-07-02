# Data Passing in Clay Workflows

How you wire data between nodes depends on the node type. There are three
mechanisms; the shapes below are exactly what `edit_node` accepts and what `read`
returns — wire data this way, then `read` the node back to confirm it saved.

## Method 1: LLM Variable Filling (default)

When an agent node finishes, it picks one outgoing edge and fills in
`{{variable_name}}` placeholders in the downstream node's prompt based on its
understanding of the work it just did.

**Example:**

```
Node A prompt: "Research the company {{company_name}} and determine their industry."
Node B prompt: "Write an email to {{contact_name}} at {{company_name}} in the {{industry}} industry."
```

When Node A transitions to Node B, the LLM fills in `company_name`,
`contact_name`, and `industry` based on its research.

**Best for:** Flexible, prompt-to-prompt text. Simple workflows where the
immediately preceding agent node has all the context needed.

**Limitations:**
- Non-deterministic — the LLM may fill values slightly differently each run
- No type validation — everything is a string
- Only works node-to-immediate-successor — for data from 2+ hops back, pin the input (Method 2)

## Method 2: Pinned inputs on agent nodes (typed, deterministic)

Use this when the data must be exact (a number, a boolean, a specific structured
field), comes from a node that is NOT the immediate predecessor, or you want a
guarantee instead of LLM-mediated filling.

The **upstream node** declares an `outputSchema` describing its structured output:

```json
{
  "outputSchema": {
    "type": "object",
    "properties": {
      "company_name": { "type": "string" },
      "industry": { "type": "string" },
      "score": { "type": "number" }
    }
  }
}
```

The **downstream agent node** pins each input by adding `sourceNodeId` +
`sourcePath` **directly onto the `inputSchema` property**, and turns off automap
so the LLM can't override the pinned value:

```json
{
  "automapInputs": false,
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

`inputSchema`/`outputSchema` also accept a **shorthand** that drops the
`type: "object"` + `properties` wrapper — `{ "score": { "type": "number" } }` is
equivalent to the full form above. Either works; the shorthand is terser.

**`automapInputs`** (boolean, top-level):
- `true` (default) — the LLM fills any inputs at runtime and may override pins
- `false` — inputs resolve only from their `sourceNodeId`/`sourcePath`; pin every input you care about

**Accessing pinned inputs:** in an agent prompt, `{{company_name}}` resolves to
the pinned value (not LLM-filled).

**`sourcePath` syntax** is JSONPath: `$.field`, `$.nested.field`,
`$.array[0].name`, `$.results[0].properties.hs_email_domain`.

## Method 3: Action input mapping on tool nodes

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
        "objectTypeId":            { "type": "static",    "value": "0-2" },
        "fields|domain":           { "type": "reference", "expression": "{{domain}}" },
        "fields|fieldsToFilterBy": { "type": "static",    "value": ["domain"] }
      }
    }
  ]
}
```

Each value is one of:

| `type`      | shape                                              | meaning |
|-------------|----------------------------------------------------|---------|
| `static`    | `{ "type": "static", "value": … }`                 | fixed value baked into the node |
| `reference` | `{ "type": "reference", "expression": "{{var}}" }` | pull from an available variable (upstream output / trigger input) |
| `llm`       | `{ "type": "llm" }`                                 | let the LLM fill it at runtime |
| `skip`      | `{ "type": "skip" }`                               | leave the parameter unset |

**Pipe keys (`parent|sub`):** grouped/nested action parameters are addressed
with a pipe. A `fields` group with `domain` and `fieldsToFilterBy` sub-fields is
mapped as `fields|domain` and `fields|fieldsToFilterBy`.

**Gotcha — `inputMappingConfig` lives on the tool, not the node, and is shared.**
`edit_node` reuses an existing tool whenever it can — a reused `toolId`, **or an
`actionKey` that already has a workspace-scoped tool** — and there's no flag to
force a node-local one. Setting `inputMappingConfig` updates that tool and
**re-syncs every node using it**, so a mapping you intend for one node can silently
change others. Before mapping, `read` the workflow; if the tool is shared, wire the
value through the node's own inputs instead.

**Gotcha — don't invent inputSchema variables on tool nodes.** A property added to
a tool node's `inputSchema` that isn't a real action parameter is **silently
dropped on save**, so any `{{var}}` referencing it resolves to nothing. Put the
`reference` directly in `inputMappingConfig` instead (e.g.
`"fields|domain": { "type": "reference", "expression": "{{domain}}" }`), then
`read` the node back to confirm it persisted.

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
      "owner_name": { "type": "string", "sourceNodeId": "wfn_enrich", "sourcePath": "$.toolResult.result.name" }
    }
  },
  "tools": [
    {
      "toolType": "clay_action", "actionKey": "hubspot-create-object", "actionPackageId": "a2584689-...",
      "inputMappingConfig": { "fields|name": { "type": "reference", "expression": "{{owner_name}}" } }
    }
  ]
}
```

The input is normalized to the action's own parameters on save, but the binding
is preserved as long as `inputMappingConfig` references it — so the `{{owner_name}}`
reference resolves. `read` the node back and confirm both the input ref and the
mapping persisted.

### Output structure of enrich (tool) nodes

Enrich (tool) nodes wrap their action result in a `toolResult` envelope at runtime. The raw action
outputs are nested under `toolResult.result`, not at the top level. When writing `inputRefs`
or `sourcePath` expressions that point at an enrich (tool) node, you must account for this envelope:

```json
{ "sourceNodeId": "wfn_enrich_company", "sourcePath": "$.toolResult.result.name" }
```

The actual top-level keys of an enrich (tool) node's outputs are always `toolResult` (and `usage`).
Everything the Clay action returned is inside `toolResult.result.*`.

To discover the exact field names, either:
1. Check the `recentOutputPaths` field on the node (populated from the most recent run), or
2. Run the action once with `execute_clay_action` and look at the returned fields — those keys
   will be available as `$.toolResult.result.<field>`.

**Example:** if `execute_clay_action` returns `{ "name": "Acme", "domain": "acme.com" }`, the
correct paths are `$.toolResult.result.name` and `$.toolResult.result.domain`.

## Discovering an action's dynamic fields

Some actions only reveal their real parameters once an earlier input is chosen —
a CRM "create object" exposes a different field set per object type; a dependent
dropdown's options depend on a parent selection. These are **not** in the static
action schema (`clay workflows actions schema`). Resolve them with the CLI — it
hits the live integration, so pass the connected account:

```bash
# 1. resolve a dependent dropdown's values (the "driver")
clay workflows actions dynamic-fields <packageId> <actionKey> objectTypeId \
  --type select --account <appAccountId>
#   → [{ "value": "2-36617481", "displayName": "Pet" }, ...]

# 2. with the driver chosen, resolve the fields it reveals
clay workflows actions dynamic-fields <packageId> <actionKey> fields \
  --type input --account <appAccountId> --inputs '{"objectTypeId":"2-36617481"}'
#   → field objects; each "name" is already pipe-namespaced: "fields|name", "fields|age", ...
```

- `--type select` resolves a dependent dropdown's values; `--type input` resolves
  the revealed field set. The `value`s and `name`s returned are exactly what go in
  `inputMappingConfig` (`objectTypeId` as a `static` value, `fields|<sub>` keys).
- It's iterative: fill one input, then re-run with it in `--inputs` to resolve the
  next dependent parameter.
- Preconditions: the driver must be a concrete value in `--inputs` (a
  `{{reference}}` won't resolve at design time), and `--account` is required for
  actions that authenticate. Get `<packageId>`/`<actionKey>` and the connected
  account from `clay workflows actions list`.

## Choosing a method

| Scenario | Method |
|----------|--------|
| Free-form text from the immediately preceding agent | LLM variable filling |
| Numeric scores, IDs, booleans into an **agent** node | Pinned inputs (`sourceNodeId`/`sourcePath` + `automapInputs: false`) |
| Data from 2+ hops back into an **agent** node | Pinned inputs |
| Any input into a **tool** node | `inputMappingConfig` (`static` / `reference`) |

You can mix on an agent node: pin the critical typed inputs and let the LLM fill
supplementary text variables in the same prompt (`automapInputs: true`).
