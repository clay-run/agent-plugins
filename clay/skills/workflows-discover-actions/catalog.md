# Discovering Clay actions

This skill helps you find available Clay actions for use in Clay workflow nodes,
via the `clay` CLI. For tool access or authentication problems, read the `clay` entry skill before continuing.

Not to be confused with `clay routines` — that lists saved function/workflow
routines in the workspace, a different concept from workflow actions. For
workflow building blocks, use `clay workflows actions`.

The actions catalog only discovers tool and function nodes. Claygents are dedicated
workflow nodes and do not need to appear in this catalog. When a step needs custom LLM
reasoning, research, drafting, or summarization, use the
`/workflows-claygent` skill instead of treating an absent Claygent action as an unavailable
capability.

The catalog also hides Use AI, which backs the Classify step. When a step sorts each record into
one of a fixed set of categories, or the user asks for Jev, insert a Classify step as described in
`clay workflows nodes insert --help` instead of a Claygent. Jev (`jev-1.13.0`) is a Classify
model only; never set it as a Claygent's `agentModel`.

## Actions catalog

The catalog is fetched live from the workspace's action catalog API. It includes all available actions with workspace-specific configuration (configured tools, app accounts, credit costs).

Each catalog entry has:

- `actionKey` — unique identifier for the action
- `packageId` — the package this action belongs to
- `displayName` / `name` — human-readable names
- `description` — what the action does
- `outputParameters` — what data the action returns
- `creditCost` — catalog base data-credit price for the workspace's billing plan,
  not a quote for the selected inputs and credentials. `usesPrivateKeyCost` is a
  separate private-key base price. Missing prices do not mean free. These fields
  alone cannot establish a configured action's cost or a workflow total.
- `dataStrengths` — what this action is best at (editorial metadata)
- `whyUseful` — when to use this action
- `configuredTools` — existing tool instances in this workspace, each with:
  - `toolId` — identifies an already-configured instance of the action. Passing it when creating
    or updating a node does **not** share that instance: unless the node already uses it, the
    edit creates a new tool with the same action and credentials
  - `appAccountId` / `appAccountName` — bound credentials
  - `appAccountAbilities` — your abilities on those credentials (`null` when the tool binds none).
    `appAccountAbilities.canAccess: false` means the workspace has withheld this connection from you: binding
    it will be rejected, so pick another tool or another account rather than retrying
- `availableAppAccounts` — app accounts connected in this workspace for the action's provider,
  each with `id`, `name`, and `abilities` (`canAccess` / `canUpdate` / `canDelete`). This is every
  account the workspace has, not only yours: `abilities.canAccess: false` entries exist and cannot
  be bound. Present only when the action needs an API key and no usable configured tool exists
- `priorityTier` — lower is better (0 = functions, 1 = Clay first-party, 2 = has app account, 3 = Clay credits, 4 = requires key)
- `packageDisplayName` — human-readable provider name (e.g. "Salesforce"); **absent on workspace-function entries** (`priorityTier: 0`), so guard for it in jq (`.packageDisplayName // ""`)
- `enabled: false`, `unavailableReason`, `unavailableMessage` — present only on actions the
  workspace can't use yet, listed after every usable action. `unavailableReason` is
  `plan_upgrade_required`: a workspace admin must upgrade the plan. Don't add these
  actions to a node. Tell the user the capability exists and relay `unavailableMessage`, rather
  than reporting that Clay can't do it
- `actionLabels.type` — the action's capability type (e.g. `"Send Data"`); can be a single string **or an array of strings**, so match with both shapes in mind

The catalog has no input field names. **Before wiring any input, fetch the real
names with `clay workflows actions schema` (see below) — never guess them**, or
the node will silently fail to bind. `schema` also returns the same `outputParameters`
the catalog entry above carries, so once you've picked an action, one `schema` call
covers both directions instead of returning to the catalog for outputs.

### Using catalog data when adding tools

Every tool node gets its own tool instance — input mappings live on the tool, so a shared instance
would make one node's mappings overwrite another's (including nodes in other workflows). Node edits
enforce this: they only keep a tool the node already has, and otherwise create a new one.

1. **Add the action** — pass `actionKey` + `actionPackageId`:
   ```json
   {
     "toolType": "clay_action",
     "actionKey": "find-email-from-name",
     "actionPackageId": "..."
   }
   ```
2. **Bind specific credentials** — pass `appAccountId` from `availableAppAccounts`, choosing one whose
   `abilities.canAccess` is `true`. Otherwise the new tool binds a private workspace account for that
   provider when one exists, and falls back to Clay's own credentials (which cost credits) when it
   doesn't:
   ```json
   {
     "toolType": "clay_action",
     "actionKey": "...",
     "actionPackageId": "...",
     "appAccountId": "app_xyz"
   }
   ```
   A tool read back from `clay workflows nodes get` carries its `appAccountId` only when it has one,
   and sending it back unchanged keeps the binding. Pass `"appAccountId": null` to remove the
   account from a tool, or to create one with no account; omit it to keep the current account.

Never load the full `clay workflows actions list` output into context; it can be megabytes.
Save it to a file or filter with `jq`, returning only relevant actions and fields.
Do not read the entire saved catalog.

Fetch the catalog with the command below. For tool access or authentication problems, read the `clay` entry skill before continuing.

```bash
clay workflows actions list > /tmp/clay-actions-catalog.json
```

## How to search

The catalog is one big JSON object (`{ "data": [...] }`), kept fully greppable.
Search it for actions matching the user's request (`$ARGUMENTS`) with grep, or
filter structurally with jq:

```bash
grep -i "email" /tmp/clay-actions-catalog.json
jq -r '.data[] | select(.enabled != false) | select(.name | test("email";"i")) | "\(.priorityTier) \(.packageId) \(.actionKey) — \(.displayName)"' /tmp/clay-actions-catalog.json | sort
jq -r '.data[] | select(.enabled == false) | select(.name | test("email";"i")) | "\(.packageId) \(.actionKey) — \(.displayName) [unavailable: \(.unavailableReason)]"' /tmp/clay-actions-catalog.json
```

`grep` matches every entry, including actions this workspace can't use yet. The first jq command
lists only usable actions; pick from those. The second jq command lists matching actions the
workspace can't use yet, so you can tell the user they exist (see `enabled` above).

Choose only among usable actions (`enabled` absent or `true`). `priorityTier` ranks an
unavailable action at its normal tier (HTTP API is tier 1), so a low tier does not mean you can
use it. Among usable actions, prefer lower `priorityTier` values and existing `configuredTools` — an action that
already has a configured tool usually has working credentials, which the new tool inherits. Skip
configured tools whose `appAccountAbilities.canAccess` is `false`: `priorityTier` does not account
for your access, so a tier-2 entry can still be one you are not allowed to bind.

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
   jq -r '.data[] | select((.packageDisplayName // "") | test("salesforce";"i")) | "\(.packageId) \(.actionKey) — \(.displayName) [\(.actionLabels.type // "")]\(if .enabled == false then " [unavailable: \(.unavailableReason)]" else "" end)"' /tmp/clay-actions-catalog.json | sort
   ```
2. **By capability** (see the write-action note below).

Only after both searches genuinely come up empty may you say the capability is
unavailable — and phrase it as "I don't see it in _this workspace's_ catalog",
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
jq -r '.data[] | select(([.actionLabels.type] | flatten | index("Send Data"))) | "\(.packageDisplayName // ""): \(.actionKey) — \(.displayName)\(if .enabled == false then " [unavailable: \(.unavailableReason)]" else "" end)"' /tmp/clay-actions-catalog.json | sort
```

For Salesforce specifically the package is "Salesforce" and the write actions are
`create-object`, `update-object`, and `upsert-object`; `upsert-object` is usually
the right choice for "write back onto the record" (it needs an external ID
field). Confirm these are absent from the catalog before telling the user to pick
some other write-back mechanism.

### People at a company is a Find leads node, not an action

Before recommending a "Find contacts at company" / "Find people at company" action for a step
that finds people at each company the workflow is handling, check whether the
`workflows-find-leads` skill is in your catalog. It owns that step and the cases where a catalog
action is the right fallback.

### When several actions fit, recommend a default

The catalog almost always has multiple actions that do roughly the same job (several email finders, several company-enrichment providers, waterfalls vs. single providers, etc.). Use the request, `priorityTier`, configured credentials, coverage, and supported pricing internally to recommend and wire the best-supported default when the choice is reversible and low-risk. Follow the shared cost policy in `workflows-discover-actions/cost-and-budget.md` for cost disclosure and spending confirmation. Ask about consequential coverage, credentials, destination, or semantics trade-offs that the request does not resolve.

- Refer to each option by its **human-readable `displayName`** (e.g. "Find Work Email (Clay)"), never the internal `actionKey`.
- For each option, explain its relevant strengths and whether a usable connection exists. Discuss pricing only under the shared cost policy in `workflows-discover-actions/cost-and-budget.md`; keep catalog ranking and routine price comparisons internal.
- When every account for a provider has `abilities.canAccess: false`, say so plainly and tell the user to ask a workspace admin to grant them access to the connection — don't report the provider as unconnected, and don't try to bind it anyway.
- Name the default you chose (usually the lowest `priorityTier` with an existing configured tool) and let the user override it as the build evolves.

## Getting action input and output schemas

Run this for any action whose inputs you'll bind or whose results a downstream node
will address, and use the exact `name` / `outputPath` values it returns:

```bash
clay workflows actions schema <packageId> <actionKey>
```

Example:

```bash
clay workflows actions schema 56058efe-4757-4fe7-a44b-39c2d730c47a find-email-from-name
```

This returns the action's `packageId`, `actionKey`, `displayName`, `inputParameters`
(the input parameter schema), and `outputParameters` (the declared output fields,
flattened to leaf paths — available before the node has ever run). An input's settings
are under `typeSettings`, including its select choices (`typeSettings.options`) and
autocomplete suggestions (`typeSettings.autocompleteOptions`). Choices and suggestions
are omitted by default because some actions carry thousands; the response's
`inputOptionsIncluded` says whether they are present. Pipe to `jq '.inputParameters'` or
`jq '.outputParameters'` to see just one side. When exact choices or suggestions are
needed for one input, request them and filter in the same command so the full arrays do
not enter the conversation:

```bash
clay workflows actions schema <packageId> <actionKey> --include-options \
  | jq '.inputParameters[] | select(.name == "<parameterName>")
        | { options: (.typeSettings.options // .options), autocompleteOptions: (.typeSettings.autocompleteOptions // .autocompleteOptions) }'
```

Check each input's `name`, `required`, and `type`; `requiredInputCombinations`, when
present, lists alternative sets of inputs (supply every member of at least one set).
For an authenticated action, find the connected account on the matching catalog entry:

```bash
jq '.data[] | select(.packageId == "<packageId>" and .actionKey == "<actionKey>") | [.availableAppAccounts[]? | select(.abilities.canAccess == true) | {id, name}]' /tmp/clay-actions-catalog.json
```

Pass an accessible `id` to `--account`. An account with `abilities.canAccess: false`
exists but cannot be used by this caller; if no usable account is listed, connect
one or request access from a workspace admin. Actions using Clay's shared credentials
may not need a connected account.

An enrich
(tool) node stores the action payload under `result`, so an output's wiring path is
`$.result.<outputPath>` — see the workflows entry-point skill's `data-passing.md`
("Output
structure of enrich (tool) nodes") for the full addressing rules. `outputParameters`
comes back empty for actions that declare no output schema; in that case, run the
action once and read the paths off its result — `clay workflows actions test`.

## Dynamic (input-dependent) fields

Some actions expose extra parameters only after an earlier input is chosen — e.g.
a CRM "create object" reveals a different field set per object type, and dependent
dropdowns whose options depend on a parent value. Static `inputParameters` contains
their containers, not the revealed fields. Start with `schema`'s `dynamicParameters`
(exact `parameterPath` and `type` for each resolver), then resolve all paths together:

```bash
clay workflows actions schema <packageId> <actionKey> --resolve-dynamic \
  --account <appAccountId> --inputs '{"<driver>":"<value>"}' \
  | jq '{resolvedInputParameters, resolvedDynamicParameters}'
```

`--inputs` uses exact input names from the schema or previously revealed fields.
Check `resolvedDynamicParameters[].errors` for blocking failures, including
`MISSING_ACCOUNT`; re-run after selecting an upstream option to reveal cascading
fields. The schema does not list each resolver's prerequisite inputs or all possible
branches. For one specific path, use:

```bash
clay workflows actions dynamic-fields <packageId> <actionKey> <parameterPath> \
  --type select|input --account <appAccountId> --inputs '{"<driver>":"<value>"}'
```

`--type select` resolves a dependent dropdown's values; `--type input` resolves a
revealed field set (names come back pipe-namespaced, e.g. `fields|name`). It's
iterative — fill one input, re-run with it in `--inputs` for the next. See the
workflows entry-point skill's `data-passing.md` ("Discovering an action's dynamic
fields")
for the full flow and how the results map into `inputMappingConfig`.
