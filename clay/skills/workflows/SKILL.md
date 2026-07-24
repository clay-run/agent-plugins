---
name: workflows
description: Clay workflows — build and edit automations made of Claygent (agent) and tool nodes, with triggers and runs. Read this before using any workflow MCP tool (`read`, `edit_node`, `validate_workflow`, `execute_clay_action`).
---

# Clay Workflow Editor

You are an expert helping users build and edit Clay workflows.

**Work transparently and collaboratively.** Building a workflow is a back-and-forth, not a fire-and-forget task — so:

- **Plan first, get approval before building.** Before you create or edit any nodes, present the plan for the workflow you intend to build (its trigger, nodes, and how data flows) and wait for the user to approve or adjust it. Do not jump straight into `edit_node`.
- **Narrate and visualize as you go.** After each meaningful change, say what you changed and why, and show the current graph — see "Show the user the graph" below.
- **Ask when there's a real choice to make.** Many Clay actions do nearly the same thing, and most steps can be built more than one way. When several actions or designs could satisfy a step, stop and ask the user which they want — refer to the options by their **human-readable names** (e.g. "Find Work Email (Clay)" vs "Waterfall Email Finder"), never internal `actionKey`s.

You build workflows out of two kinds of nodes:

- **Claygent (agent) nodes** — LLM loops with prompts. The default building block for reasoning, drafting, summarizing, and classifying.
- **Tool nodes** (`nodeType: "tool"`) — run a single Clay action directly (an enrichment, an HTTP call, a CRM write, etc.). Pick the action from the workspace's available action set. (The TC UI labels these "Enrich" or "Function"; both are `nodeType: "tool"`.)

You should also understand **triggers** — how a workflow gets launched (audience segments, schedules, webhooks, Clay tables). Triggers can be created and edited through the workflow MCP tools; Clay table triggers remain UI-only.

## Setup required

Anything that uses the `clay` CLI (running tests, searching actions, viewing snapshots, managing runs) requires the CLI on your PATH and a signed-in session (`clay login`; run the `setup` skill if `clay whoami` fails on auth). If a `clay` command returns `command not found`, do not conclude it's unavailable or fall back to other tools: retry once (a transient PATH-init race can briefly hide it), and if it's still missing, run the `setup` skill to install it. This only needs to be done once. The workspace is resolved from the stored session — there is no workspace id to set.

## Your capabilities

MCP tools:

- **Read workflows and nodes** (`read`)
- **Create, update, or delete nodes** (`edit_node`) — for `agent` and `tool` node types
- **Validate workflows** (`validate_workflow`)
- **Execute Clay actions one-off** (`execute_clay_action`)

CLI capabilities (via the `clay` CLI):

- Start, poll, and inspect workflow runs (see `testing.md`)
- Browse the Clay action catalog (`clay workflows actions`; use `/workflow-discover-actions`)
- Snapshots / version history (`clay workflows snapshots`; use `/workflow-snapshots`)

## How a Clay workflow is structured

Clay workflows are graph-based. A workflow is a directed graph of nodes connected by edges. The two node types are:

### Agent nodes (Claygents)

An agent node is an LLM loop with a prompt and a model. When the run reaches the node, the LLM:

1. Reads the prompt (with `{{variable}}` placeholders filled in from the immediately preceding node's output)
2. Does whatever the prompt asks
3. Picks one of its outgoing edges and transitions to that next node, filling that node's variables in the process

Agent nodes can have tools attached via the **Claygent configuration** (this is separate from the `tools` field that tool nodes use). Unfortunately, you cannot create Claygents with tools directly - but the user can do this in the UI themselves if they edit the Claygent directly. Treat agent nodes as Claygent prompts that do reasoning, summarization, drafting, classification, etc., and let tool nodes do the data lookup work.

### Tool nodes (`nodeType: "tool"`)

A tool node executes a single Clay action directly — no LLM reasoning. Configure it with exactly one tool in the `tools` field and it runs that action with inputs filled from upstream.

Do not back a tool node with the Use AI, ChatGPT schema mapper, Claude, Gemini, or Claygent actions — these LLM actions are rejected on tool nodes. When the work needs an LLM (summarizing, drafting, classifying, extracting), use an agent (Claygent) node instead.

Ask the user which Clay action they want to use. To learn an action's exact input/output shape, run it once with `execute_clay_action` before wiring it into the node — that confirms both that the workspace has the action available and what fields it expects.

### Conditional nodes (`nodeType: "conditional"`)

A conditional node selects exactly **one** outgoing edge and follows it.

**When to use which mode:**

| Situation | Use |
|-----------|-----|
| Branch on string/number/boolean field values — equality, comparison, contains, starts/ends with, empty/not-empty | `rules` mode |
| Multiple conditions combined with AND/OR | `rules` mode |
| Branching decision requires open-ended reasoning (e.g. "classify this support ticket as billing, technical, or general", "does this email sound interested or not?") | `agentic` mode |
| You need to compute or transform a value to decide the route, and that transformation can't be expressed as a field comparison (e.g. parse a JSON blob and branch on a nested value, compute a score from multiple fields) | `code` mode |

**`rules` mode** — supported operators:
- **String**: `Equal`, `NotEqual`, `Contain`, `NotContain`, `ContainAny` (value is an array), `StartsWith`, `NotStartsWith`, `EndsWith`, `NotEndsWith`, `Empty`, `NotEmpty`
- **Number**: `Equal`, `NotEqual`, `GreaterThan`, `GreaterThanOrEqual`, `LessThan`, `LessThanOrEqual`, `Empty`, `NotEmpty`
- **Boolean**: `True`, `False`, `Empty`, `NotEmpty`

Each rule is a `ConditionalExpressionGroup` — a tree of `BinOp` leaf nodes (a single field comparison) and `GroupOp` nodes (AND/OR of children). Rules are evaluated top-to-bottom; first match wins. Set `defaultTargetNodeId` for a fallback when no rule matches.

Example condition (headcount ≤ 50 AND title contains "CTO"):
```json
{
  "type": "GroupOp",
  "combinationMode": "And",
  "items": [
    { "type": "BinOp", "dataPath": ["headcount"], "operator": "LessThanOrEqual", "value": 50 },
    { "type": "BinOp", "dataPath": ["title"], "operator": "Contain", "value": "CTO" }
  ]
}
```

**`code` mode** — the Python handler can both compute values and route. Use when the routing decision requires transformation that rules can't express (e.g. parsing a nested structure, calling a helper, computing a derived value). The handler calls `context.transition_to('Node Name', 'label')` to pick a branch.

### Trigger nodes and leaf nodes

- Workflows start empty. Create a **trigger node** plus at least one trigger before the workflow can run end-to-end. A live **manual** trigger is the usual entry point for test/`clay` runs. Additional launch paths get their **own** trigger nodes — do not stack webhook/audience/scheduled onto the manual node.
- Creating a trigger via MCP (`surfaces_edit` / trigger surface) returns `workflowNodeId`. Wire the first action nodes with `incomingEdges` from that id.
- **Audience multi-segment sharing:** multiple `audience_segment` triggers (different `segmentId`s) may share one trigger node when they have the **same trigger type** and the **same outgoing edge**. Multiple `audience_scheduled` triggers may share a node when they also have the **same schedule**. Pass an explicit `workflowNodeId` to bind/share; omit it (or pass `createTriggerNode: true`) to get a new node. Do not mix `audience_segment` with `audience_scheduled` on one node. `audience_manual` is a run companion created by the UI/run path — do not create it via the surface.
- **Trigger edge constraint:** a trigger may have zero or one direct outgoing edge, never more. Before adding an edge from a trigger, inspect its `outgoingEdges`. If it already has a target, do not add another direct edge; add work downstream instead, or ask the user whether to rewire the workflow. Before validating or running, each trigger must be connected to one first executable node.
- **Leaf nodes** are nodes with no downstream connections. They are automatically treated as terminal — you do not need to mark them.

## Triggers — how workflows get launched

A workflow doesn't run by itself. It runs because a **trigger** kicks off a run. Use the workflow MCP tools to create or edit triggers when requested; configure Clay table triggers in the Clay tables UI:

- **Audience segment trigger** — every record in a Clay audience segment becomes a run input. Useful for batch-style enrichment over a known list.
- **Scheduled trigger** — fires one contextless workflow run per schedule tick. Provide `scheduleConfig` with either a simple or custom recurrence.
- **Audience scheduled trigger** — reruns all current members of an audience segment on each schedule tick. Provide `segmentId`, `entityType`, and `scheduleConfig`. May share a trigger node with other `audience_scheduled` triggers that use the same schedule and outgoing edge (pass their `workflowNodeId`).
- **Webhook trigger** — an external system POSTs to a URL and each request becomes a run (own trigger node).
- **Clay table trigger** — new rows added to a specific Clay table create runs automatically.
- **One-off / batch test runs** — the user (or the `clay` CLI) launches a single run or a batch for testing via a manual trigger (create one if the workflow does not have one yet).

When designing a workflow, ask the user how the workflow will be triggered, because that determines:

- What the trigger node's outputs look like (a row from a table? a webhook body? an audience record?)
- Whether the workflow should be optimized for one-at-a-time or high-volume runs
- Whether leaf node output goes back to a Clay table, a webhook response, etc.

If the user hasn't picked a trigger, recommend the simplest option that fits their use case and create it via the trigger surface.

## Required fields for new nodes

For every node:

- `name`, `nodeType`, `incomingEdges`

For agent nodes (`nodeType: "agent"`):

- `agentName`, `agentPrompt`, `agentModel`
- Always send `agentName`, `agentPrompt`, and `agentModel` together in a single `edit_node` call. Sending them separately can result in an agent with a blank prompt.
- **Model selection — use a two-phase approach:**
  1. **While building and testing:** use `gpt-5.4-nano` for `agentModel`. It's the fastest, which keeps the debug loop tight.
  2. **After the workflow works e2e:** graduate to whatever model is the best fit for the task.

For tool nodes (`nodeType: "tool"`):

- `tools` — exactly one entry. The `actionKey` is the Clay action you want to invoke (confirm it via `execute_clay_action` first)

## Adding a tool to a tool node

Use the `tools` field with a single-element array:

```json
[
  {
    "toolType": "clay_action",
    "actionKey": "<actionKey>",
    "actionPackageId": "<packageId>"
  }
]
```

Or reuse a workspace-configured tool by id:

```json
[{ "toolType": "clay_action", "toolId": "tct_abc123" }]
```

The user can tell you which `actionKey` and `actionPackageId` to use, or which existing `toolId` to reuse. Test the action with `execute_clay_action` before adding it to confirm it works on this workspace and to see its real output shape.

Wire the action's parameters with `inputMappingConfig` on the tool entry — each parameter maps to a `static` value or a `reference` expression. Nested/grouped parameters use `parent|sub` pipe keys:

```json
[
  {
    "toolType": "clay_action",
    "actionKey": "hubspot-lookup-object",
    "actionPackageId": "a2584689-...",
    "inputMappingConfig": {
      "objectTypeId": { "type": "static", "value": "0-2" },
      "fields|domain": { "type": "reference", "expression": "{{domain}}" },
      "fields|fieldsToFilterBy": { "type": "static", "value": ["domain"] }
    }
  }
]
```

**`inputMappingConfig` is stored on the tool, not the node, and is shared by every node bound to that tool.** Reusing a `toolId` (or an `actionKey` that already has a workspace tool) and setting a mapping re-syncs all those nodes — silently changing other nodes' inputs. Before mapping a reused/shared tool, `read` the workflow to check no other node uses it.

For actions whose fields depend on an earlier input (e.g. an object type that reveals a different field set), resolve the real `objectTypeId` values and `fields|<sub>` keys with `clay workflows actions dynamic-fields` before mapping — don't guess them.

See `data-passing.md` for `inputMappingConfig` types (`static` / `reference` / `llm` / `skip`), the `parent|sub` pipe convention, resolving dynamic fields, and both tool-node gotchas (shared-tool mappings, and dropped `inputSchema` variables).

## Enabling batching on a tool node

Some actions support batching multiple workflow runs into a single provider call, dramatically cutting cost/rate-limit pressure for high-volume workflows. Not every action supports it, and the action catalog doesn't flag which ones do — so treat batching as something you enable on request and let `edit_node` confirm support.

Set `batchRunSettings: { "enabled": true, "maxBatchSize": <n> }` on a tool node via `edit_node` to turn it on — `maxBatchSize` is optional and gets clamped to the action's real maximum. **Only set this when the user explicitly raises batching, rate limits, or handling large volumes of rows/runs — never proactively.** If the action doesn't support batching, `edit_node` rejects the request with an error — relay that to the user rather than retrying.

`batchRunSettings` can only be set on a tool node that already has its `tools` field configured — if you're creating the node and enabling batching in the same conversation turn, do it as two separate `edit_node` calls (create with `tools` first, then enable batching in a follow-up call).

## Passing data between nodes

Two methods are available:

### `{{variable}}` filling (default)

Put `{{variable_name}}` in an agent node's prompt, and the upstream LLM fills it in when transitioning. Works node-to-immediate-successor only. Best for free-form text.

### Pinned inputs (typed, deterministic)

For data that needs to be exact (numbers, structured fields, data from 2+ hops back), declare an `outputSchema` on the upstream node, then on the downstream **agent** node pin each input by putting `sourceNodeId` + `sourcePath` **inline on the `inputSchema` property** and set `automapInputs: false`:

```json
{
  "automapInputs": false,
  "inputSchema": {
    "type": "object",
    "properties": {
      "company_name": { "type": "string", "sourceNodeId": "wfn_upstream", "sourcePath": "$.company_name" },
      "score": { "type": "number", "sourceNodeId": "wfn_upstream", "sourcePath": "$.score" }
    }
  }
}
```

The reference is `sourceNodeId` + `sourcePath` inline on the property. Use `sourcePath`, not `path`. Path syntax is JSONPath (`$.field`, `$.nested.field`). Agent nodes access pinned inputs as `{{company_name}}` in the prompt; `automapInputs: false` stops the LLM from overriding them.

**Tool nodes are different** — their action parameters are wired in `tools[].inputMappingConfig` (`static` / `reference`), not in `inputSchema`. Do not add intermediate variables to a tool node's `inputSchema`; non-action-parameter properties are dropped on save. See `data-passing.md` for the full reference.

**Important — enrich (tool) node output paths:** An enrich (tool) node's Clay action fields are at
`$.result.<field>`, and its success flag is at `$.success`. Always check the node's
`recentOutputPaths` field (visible via `read`) or run `execute_clay_action` first to see which
fields the action returns — then prefix them with `$.result.`. For example: `$.result.name`,
`$.result.domain`.

## Recommended workflow for building

0. **Plan and get approval before building.** Ask the user what trigger they'll use (or recommend one), then lay out the proposed workflow — the nodes, what each does, and how data flows between them — as a short plan. Present it and **wait for the user to approve or adjust it before you touch `edit_node`.** For anything beyond a trivial one-node change, treat this as a hard gate.
1. **If you create a new workflow, share its link right away.** `clay workflows create` (and `clay workflows get`) return a `url` — post it as soon as the workflow exists so the user can open the editor and follow along live as you build. This matters most in a headless environment (Claude Code, Cursor, a shell), where the user has no Clay tab open; if you're the in-product assistant they're already viewing the workflow, so a link isn't needed.
2. Confirm the trigger so you understand the initial node's inputs
3. Decide which Clay action each tool node calls. Use `/workflow-discover-actions` to find candidates, then test the chosen one with `execute_clay_action` to confirm output shape before wiring. **When more than one action does roughly the same thing, don't pick silently — list the human-readable options (with what each is best at / its credit cost) and ask the user to choose.**
4. Build the workflow node-by-node with `edit_node`, wiring `incomingEdges` as you go. After each node, tell the user in one line what you added and how it connects.
5. Run `validate_workflow` with `prettier=true` to auto-layout and catch issues, then **show the user the resulting graph** (see "Show the user the graph" below)
6. Suggest the user kicks off a test run. When you narrate the run afterward, show a **status-annotated view** of the graph — mark each node completed / failed / running — so the user sees where in the flow each result came from (see `testing.md` and `presenting.md`)

## Show the user the graph

Users can't follow what you're building unless you show them, so narrate each
change in plain language and redraw the graph for changes that visually change
it (nodes or edges added, removed, or rewired). **`presenting.md` is the single
source of truth for how** — which diagram command to use in each environment,
when to redraw versus just narrate, when to summarize instead of dumping raw
output, and how to annotate the graph with per-node run status. Read it before
your first render.

## Best practices

1. Always read the workflow first to understand current state before editing — then summarize the current graph for the user (a `clay workflows diagram` render or a plain-language recap) before proposing changes
2. Plan the workflow and get the user's sign-off before building; don't start creating nodes from an unconfirmed plan
3. Create nodes sequentially with `edit_node`, using `incomingEdges` to wire them to existing nodes, narrating each change as you make it
4. Validate after making changes
5. After building or significantly modifying a workflow, run `validate_workflow` with `prettier=true` and show the user the updated graph
6. Use string-replace mode for small edits to prompts
7. When adding enrichment tools, try 2-3 alternative actions as fallbacks if the primary one might miss — and when the choice of primary action is ambiguous, ask the user which they prefer (by human-readable name) rather than guessing
8. After completing a workflow, suggest a test run and walk the user through what the run did (see `testing.md`)
9. If you make a mistake or the user asks to undo, use `/workflow-snapshots` to revert

## Reference docs in this skill

- `presenting.md` — How to narrate and visualize your work (diagrams, tables, run-status annotation) so the user can follow along
- `data-passing.md` — How `{{variables}}`, pinned inputs, and `inputMappingConfig` work in detail
- `testing.md` — `clay` CLI commands for running and inspecting workflow runs
- `audiences-actions.md` — Audience-specific actions
- `clay <command> --help` — Per-command JSON shape, flags, and error codes
