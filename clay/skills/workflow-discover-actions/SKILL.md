---
name: workflow-discover-actions
description: Clay workflows — discover available actions for workflow nodes (email lookup, company enrichment, phone finders, etc.) and inspect their input schemas. Use while building a workflow.
allowed-tools: Bash(clay *), Bash(grep *), Bash(cat *), Bash(wc *), Bash(jq *), Read, Grep
---

# Discovering Clay actions

This skill helps you find available Clay actions for use in Clay workflow nodes,
via the `clay` CLI. (In Codex/Cursor, run the `setup` skill once if `clay` is not
yet on your PATH.)

Not to be confused with `clay routines` — that lists saved function/workflow
routines in the workspace, a different concept from workflow actions. For
workflow building blocks, use `clay workflows actions`.

## Actions catalog

The catalog is fetched live from the workspace's action catalog API. It includes all available actions with workspace-specific configuration (configured tools, app accounts, credit costs).

Each catalog entry has:

- `actionKey` — unique identifier for the action
- `packageId` — the package this action belongs to
- `displayName` / `name` — human-readable names
- `description` — what the action does
- `outputParameters` — what data the action returns
- `creditCost` — credits per execution (based on workspace billing plan)
- `dataStrengths` — what this action is best at (editorial metadata)
- `whyUseful` — when to use this action
- `configuredTools` — existing tool instances in this workspace, each with:
  - `toolId` — pass this to `edit_node` tools field to reuse an existing tool
  - `appAccountId` / `appAccountName` — bound credentials
- `availableAppAccounts` — app accounts the user has connected (for actions requiring API keys)
- `priorityTier` — lower is better (0 = functions, 1 = Clay first-party, 2 = has app account, 3 = Clay credits, 4 = requires key)
- `packageDisplayName` — human-readable provider name (e.g. "Salesforce"); **absent on workspace-function entries** (`priorityTier: 0`), so guard for it in jq (`.packageDisplayName // ""`)
- `actionLabels.type` — the action's capability type (e.g. `"Send Data"`); can be a single string **or an array of strings**, so match with both shapes in mind

The catalog has no input field names. **Before wiring any input, fetch the real
names with `clay workflows actions schema` (see below) — never guess them**, or
the node will silently fail to bind.

### Using catalog data when adding tools

When adding a tool to a node, you can either:

1. **Reuse an existing tool** — pass `toolId` from `configuredTools`:
   ```json
   { "toolType": "clay_action", "toolId": "tct_abc123" }
   ```
2. **Create a new tool** — pass `actionKey` + `actionPackageId`:
   ```json
   { "toolType": "clay_action", "actionKey": "find-email-from-name", "actionPackageId": "..." }
   ```
3. **Bind specific credentials** — pass `appAccountId` from `availableAppAccounts`:
   ```json
   { "toolType": "clay_action", "actionKey": "...", "actionPackageId": "...", "appAccountId": "app_xyz" }
   ```

Fetch the catalog with the command below. If it fails (e.g. missing
credentials), run the `setup` skill first.

```bash
clay workflows actions list > /tmp/clay-actions-catalog.json
```

## How to search

The catalog is one big JSON object (`{ "data": [...] }`), kept fully greppable.
Search it for actions matching the user's request (`$ARGUMENTS`) with grep, or
filter structurally with jq:

```bash
grep -i "email" /tmp/clay-actions-catalog.json
jq -r '.data[] | select(.name | test("email";"i")) | "\(.priorityTier) \(.packageId) \(.actionKey) — \(.displayName)"' /tmp/clay-actions-catalog.json | sort
```

Prefer actions with lower `priorityTier` values and existing `configuredTools`.

### Never tell the user a capability is missing without searching for it first

The catalog is the source of truth for this workspace. Before you say something
like "there's no native Salesforce write action" or "you'll have to do that with
a raw API call", you MUST actually search the catalog for it — do not answer from
memory or from the user's phrasing. Provider write actions are the most commonly
missed, because their `displayName`s are generic ("Create Record", "Upsert
Object") and their `description`s rarely contain words like "write" or "sync", so
a naive keyword grep misses them. Search two ways before concluding anything:

1. **By provider**, using `packageDisplayName` (**absent on workspace-function
   entries** — guard it with `// ""` or the `test()` call throws on the first
   function and aborts before printing any real matches):
   ```bash
   jq -r '.data[] | select((.packageDisplayName // "") | test("salesforce";"i")) | "\(.packageId) \(.actionKey) — \(.displayName) [\(.actionLabels.type // "")]"' /tmp/clay-actions-catalog.json | sort
   ```
2. **By capability** (see the write-action note below).

Only after both searches genuinely come up empty may you say the capability is
unavailable — and phrase it as "I don't see it in *this workspace's* catalog",
not "it doesn't exist" or "it isn't supported". When it's absent, give the user a
next step: suggest confirming the app/action is connected and enabled for the
workspace, and offer a concrete workaround rather than a flat no.

### Finding write / "send data" actions (CRM upserts, etc.)

Writing back to a CRM or other destination ("write to Salesforce", "create a
HubSpot contact", "update the record") is a native action — not something to
hand-roll with an HTTP call. These actions carry `"Send Data"` in
`actionLabels.type` (their tags usually include `CRM` and `EXPORT`). `type` can
be a single string or an array of strings — don't rely on `actionKey` naming to
spot them; each provider names its write actions differently (e.g. Salesforce's
`create-object`/`update-object`/`upsert-object`, HubSpot's
`hubspot-create-object`, Clay Labs' `upsert-audiences-record`). List every write
action available in the workspace with:

```bash
jq -r '.data[] | select(([.actionLabels.type] | flatten | index("Send Data"))) | "\(.packageDisplayName // ""): \(.actionKey) — \(.displayName)"' /tmp/clay-actions-catalog.json | sort
```

For Salesforce specifically the package is "Salesforce" and the write actions are
`create-object`, `update-object`, and `upsert-object`; `upsert-object` is usually
the right choice for "write back onto the record" (it needs an external ID
field). Confirm these are absent from the catalog before telling the user to pick
some other write-back mechanism.

### When several actions fit, ask the user — don't pick silently

The catalog almost always has multiple actions that do roughly the same job (several email finders, several company-enrichment providers, waterfalls vs. single providers, etc.). These differ in coverage, credit cost, and required credentials, and the "right" one is a judgment call the user should make. **When more than one candidate fits a step, present the shortlist and ask which they want before wiring it.**

- Refer to each option by its **human-readable `displayName`** (e.g. "Find Work Email (Clay)"), never the internal `actionKey`.
- For each option, surface the details that drive the decision: `whyUseful` / `dataStrengths`, `creditCost`, whether a `configuredTool` or `availableAppAccount` already exists, and `priorityTier`.
- Recommend a default (usually the lowest `priorityTier` with an existing configured tool) but let the user override it.

## Getting action input schemas

Run this for any action whose inputs you'll bind, and use the exact `name`
values it returns:

```bash
clay workflows actions schema <packageId> <actionKey>
```

Example:

```bash
clay workflows actions schema 56058efe-4757-4fe7-a44b-39c2d730c47a find-email-from-name
```

This returns the action's `packageId`, `actionKey`, `displayName`, and
`inputParameters` (the input parameter schema). Pipe to `jq '.inputParameters'`
to see just the parameters.

## Dynamic (input-dependent) fields

Some actions expose extra parameters only after an earlier input is chosen — e.g.
a CRM "create object" reveals a different field set per object type, and dependent
dropdowns whose options depend on a parent value. These are **not** in
`schema`'s `inputParameters`; resolve them with:

```bash
clay workflows actions dynamic-fields <packageId> <actionKey> <parameterPath> \
  --type select|input --account <appAccountId> --inputs '{"<driver>":"<value>"}'
```

`--type select` resolves a dependent dropdown's values; `--type input` resolves a
revealed field set (names come back pipe-namespaced, e.g. `fields|name`). It's
iterative — fill one input, re-run with it in `--inputs` for the next. See the
workflows skill's `data-passing.md` ("Discovering an action's dynamic fields")
for the full flow and how the results map into `inputMappingConfig`.
