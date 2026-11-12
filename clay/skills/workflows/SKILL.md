---
name: workflows
description: Clay workflows — plan, review, build, and edit automations with the Clay CLI. Use when planning or working on a Clay workflow, including putting one on a schedule or pausing its schedule.
---

# Building Clay workflows with the CLI

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

When the conversation includes selected workflow nodes from a widget, read the
current authoritative workflow graph before editing. Reconcile the workflow and
workspace IDs, revision, and selected node IDs; names and selection order do not
identify a connection. For “between these”, use the directed edge identity and
branch/source index. A unique direct connection is straightforward. Ask a focused
question for multiple edges or paths, disconnected or deleted nodes, or incomplete
topology. A truncated preview cannot establish that no other path exists. Never
infer configuration or execution inputs from the display-only context.

Supporting files in this directory: `publishing.md`, `testing.md`, `data-passing.md`,
`presenting.md`, `audiences.md`, `account-agents.md`, `run-analysis.md`, `node-groups.md`,
`csv-triggers.md`, `table-primitives.md`, `table-waterfalls.md`, `industry-mapping.md`,
`repeat-function-calls.md`.

Read this skill before proposing a workflow plan, even when the user asks for no workspace
queries or changes. For Audiences destinations or field mappings, also read `audiences.md`
before answering. Reading skill guidance does not query or change the workspace.

When working in an existing workflow, read it with `clay workflows get <workflowId>` before
planning edits, unless the user prohibits queries; then plan from the supplied draft and field
catalog. Do not ask for a workflow ID just to discuss a complete supplied draft. If its `type`
is exactly `audience_enrichment`, read the complete
`/workflows-audience-enrichment` skill and follow it together with this skill. Do not apply that
specialized skill to a workflow whose type is null, absent, or any other value.

For requests to create, inspect, edit, enable, disable, or delete a workflow alert rule, or to
subscribe to a workflow's alert emails, read and follow the `/workflows-alerts` skill.

## Domain and working style

You are helping users build and edit Clay workflows.

- **Name new workflows first.** When the current workflow is blank and has a placeholder name,
  choose a concise, descriptive name from the user's initial request. Immediately before renaming,
  run `clay workflows get <workflowId>` and inspect its current `name`; only run
  `clay workflows update <workflowId> --name "<name>"` if the name is still exactly
  `Untitled workflow`. Preserve any name that has already replaced the placeholder. Do this before
  asking follow-up questions or editing the graph. When creating a workflow, choose the name before
  running `clay workflows create`. Do not rename an existing non-blank workflow unless the user asks
  you to.
- Follow the host agent's planning, user-input, and approval policies when building or editing workflows.
- **Do not add Audiences writeback to an Audiences export workflow.** For workflows that
  start with an Audiences-related trigger and export its records, omit Write to Audiences
  to avoid a redundant no-op loop. This takes precedence over the default writeback guidance
  below; see `audiences.md`.
- **Choose Audiences writeback from the whole workflow and the user's intent.** Inspect the
  source, upstream steps, outputs, and existing destinations. Enrichment of existing Audiences
  records should write results back; for new records from searches or CSV uploads, recommend
  saving to Audiences and confirm before adding it unless already requested. Honor explicit
  destinations and no-save requests, and reuse existing writeback nodes. Read `audiences.md`
  for the decision and field-mapping rules: map obvious existing fields directly without
  offering duplicate fields, clarify ambiguous mappings, and create needed fields without
  asking permission. A missing compatible field is a reason to create one, not a decision
  to hand back to the user. In a plan, state that creation and mapping as the next steps.
  Building a node does not authorize running or publishing.
- **Ground provider names in the workspace catalog.** Until you search the current workspace's
  action catalog, describe capabilities generically (for example, "intent data enrichment"). Do
  not introduce provider or action names from general knowledge. You may name one when the user
  already named it or the catalog verified it. Never proactively mention G2 or 6sense; if the user
  asks for either, search the catalog and recommend verified alternatives instead of presenting it
  as a supported Clay action.
- **Narrate and visualize as you go.** After each meaningful change, say what changed and show the
  graph (`presenting.md`).
- **Ask when there's a real choice** — refer to actions by human-readable names, never bare
  `actionKey`s.
- **Qualify the person's role, not just title keywords.** Require the right function and
  decision-making seniority. Mentioning a function may mean selling to, recruiting for, or
  assisting its leaders. Use compatible structured function/seniority fields or unambiguous
  rules; when titles need judgment, use a small Claygent classification of supplied inputs
  before paid contact enrichment. Select existing candidate IDs and reuse the decision
  downstream; don't generate people or research externally when supplied fields suffice.
- **Classify company verticals with Clay's industry mapping.** When a step decides a company's
  vertical from its `industry` field (for example "is this a software company?") and the
  vertical is in `industry-mapping.md`, use its `industry` values instead of writing your own
  keyword match. For any other vertical, choose the matching values from the labels the records
  actually carry (`clay audiences fields list-values industry --entity-type companies`), and
  use a small Claygent classification when the label alone can't decide.

Common node types (not just agent/tool — pick the type that fits the step):

- **Classify steps** — a Use AI tool node with `useCase` `decision` that sorts each record into
  one of 2–255 fixed categories, with branch-ready `$.result.categoryId`. Use it for fixed-category
  labels from supplied data and whenever the user asks for Jev (`jev-1.13.0`). There is no
  `classify` nodeType; follow the recipe in `clay workflows nodes insert --help`.
- **Claygent (agent) nodes** (`nodeType: "agent"`) — LLM loops with prompts (reasoning,
  research, drafting, summarizing, open-ended classification). Read and follow the complete `/workflows-claygent`
  skill before creating, editing, or running one.
  - **Create:** send `agentName` and `agentPrompt` **together in the same** `--input` —
    separate calls can persist a blank prompt. Omit `agentModel` to use the workspace default
    (Auto where enabled), or set it to the specific model the user requests. One exception: a node
    you are about to make an account agent is created bare — see account agents below.
  - **Reuse:** `clay claygents list --search <text>` returns regular Claygents (`agentType: null`)
    and account agents (`agentType: "account"`). Read regular Claygents with `clay claygents get <id>`.
    Send only `agentClaygentId` (the returned `id`) to attach either kind, then inspect the linked
    agent with `clay workflows nodes get <workflowId> <nodeId>`. Do not send `agentName` / prompt / model — `agentName` can rewrite that
    shared prompt. For account agents, follow `account-agents.md` for selection and input wiring.
- **Tool nodes** (`nodeType: "tool"`) — run a single Clay action or Clay function. (UI may
  label these "Enrich" or "Function".) `tools` may be omitted while drawing an outline; before
  validate/test/publish, set exactly one `tools` entry — either
  `{ "toolType": "clay_action", "actionKey": …, "actionPackageId": … }` for an enrichment action,
  or `{ "toolType": "clay_function", "tableId": "<functionId>" }` for a Clay function subroutine.
  Both come from `clay workflows actions list`. For the input shape, pass an action's ids to
  `clay workflows actions schema` or a function's id to `clay functions get`.
- **Message nodes** (`nodeType: "tool"` with `message`) — a message template with input variables
  and optional AI-written text. See "Message nodes" below.
- **Rep task nodes** (`nodeType: "tool"` with `repTask`) — create a task in Reps for a rep to work,
  such as an email to review and send. See "Rep task nodes" below.
- **Conditional nodes** (`nodeType: "conditional"`) — pick exactly one outgoing branch
  (`rules` / `agentic` / `code` via `conditionalMode`).
- **Code nodes** (`nodeType: "code"`) — deterministic Python transforms (no LLM), for shaping
  and filtering; use an agent when the step needs LLM judgment. The handler goes in top-level
  `code`. Code runs on the Python standard library only, with no network access and no Clay
  actions, and each run is stopped after 1 second: use a tool node for enrichment or HTTP calls
  and a delay node to wait, never `time.sleep()`. Standard-library modules that need networking,
  processes, threads, files, or time zone data are unavailable (`socket`, `http`,
  `urllib.request`, `subprocess`, `threading`, `asyncio`, `logging`, `pathlib`, `zoneinfo`). Use
  `print()` instead of `logging`, and a fixed UTC offset instead of `zoneinfo`. Prefer
  `clay workflows code test` before wiring. Wire inputs and outputs as `data-passing.md`
  Method 3 describes: named outputs, with inputs pinned from the node that produced them, not a
  state object passed from code node to code node.
- **Merge nodes** (`nodeType: "merge"`) — coalesce ordered candidate values into named outputs
  for downstream reuse. Prefer these when branch convergence or fallback selection is only
  coalescing; use a code node when computation or a non-trivial transformation is also needed.
  Read `data-passing.md` before configuring a merge node. If creating a merge node is rejected
  because the workspace does not have merge nodes enabled, do not retry; use a code node to
  produce the same named outputs.
- **Delay nodes** (`nodeType: "delay"`) — pause a run before the next step without producing
  data. Set `delay` and `delayUnit` (`"seconds"`, `"minutes"`, `"hours"` or `"days"`) in the create
  or update `--input`, up to 45 days in total. To wait for a duration computed upstream instead, add
  a `delay` property to `inputSchema` with type `number`, `sourceNodeId`, and `sourcePath`; it
  overrides `delay` and is read in `delayUnit`, so set `delayUnit` too. To wait until the next
  occurrence of a recurring time, set `delayUntil` (the duration is ignored while it is set, and
  `"delayUntil": null` clears it). Times are 24-hour `HH:mm` in an IANA timezone:
  - `{"kind": "weekday", "weekday": 1, "time": "09:00", "timezone": "America/New_York"}` (0 = Sunday)
  - `{"kind": "day_of_month", "day": 21, ...}`: `day` is 1–31 or `"last"`, and late days land on a
    short month's last day
  - `{"kind": "nth_weekday", "nth": 2, "weekday": 5, ...}`: `nth` is 1–4 or `"last"`
- **Map / reduce / collect** (`nodeType: "map"` / `"reduce"` / `"collect"`) are retired: `nodes create`
  rejects them and existing ones fail when they run. For per-record work over a list, use list mode
  (see "List mode (Repeat)"); to aggregate the results, add a node downstream of the Repeat node,
  which receives the whole list.
- **Trigger nodes** (`nodeType: "trigger"`) — canvas entry points. Create/bind them with
  `clay workflows triggers …` (see Triggers below); do not invent a bare trigger node
  without a trigger row.

Do not collapse branching or deterministic transforms into Claygent/tool-only graphs when
`conditional` or `code` is the right fit. Node type is fixed at create — choose before
`nodes create` because it cannot be changed later. Read an existing node of the same type
(`nodes get`) and copy writable fields from `.node` when the shape is unfamiliar; a read leaves
out fields the node does not set, which this skill and `data-passing.md` describe.

Wiring a node's inputs — `inputSchema` with `sourceNodeId`/`sourcePath`, and `inputMappingConfig`
on tool nodes — is covered in `data-passing.md`. Read it before wiring the first input, and
before reading or editing a tool node whose action has dynamic fields (resolving them needs
the node's current static inputs).

### Conditional nodes

A conditional node selects exactly one outgoing edge. Set the top-level `conditionalMode` to
`rules`, `agentic`, or `code`. Pass `rulesConditionalConfig` or `agentConditionalConfig` as a JSON
object, never as stringified JSON.

- Use `rules` for string, number, or boolean comparisons and AND/OR groups.
- Use `agentic` for open-ended classification that requires LLM judgment.
- Use `code` when routing requires a deterministic Python transform.

**Rules mode:** set `conditionalMode: "rules"`. Declare every field the rules read in top-level
`inputSchema` with `sourceNodeId` and `sourcePath`, then reference that field name from each
`BinOp`'s `dataPath`. Wrap conditions in a root `GroupOp`, even when there is only one condition.
Rules run top-to-bottom and the first match wins.

Supported operators:

- String: `Equal`, `NotEqual`, `Contain`, `NotContain`, `ContainAny`, `StartsWith`,
  `NotStartsWith`, `EndsWith`, `NotEndsWith`, `Empty`, `NotEmpty`, `GreaterThan`,
  `GreaterThanOrEqual`, `LessThan`, `LessThanOrEqual`. The four comparisons coerce the
  text with `Number()`; equality still compares the raw text.
- Number: `Equal`, `NotEqual`, `GreaterThan`, `GreaterThanOrEqual`, `LessThan`,
  `LessThanOrEqual`, `Empty`, `NotEmpty`
- Boolean: `True`, `False`, `Empty`, `NotEmpty`

```json
{
  "nodeType": "conditional",
  "name": "Has work email?",
  "inputSchema": {
    "type": "object",
    "properties": {
      "email": {
        "type": "string",
        "sourceNodeId": "wfn_source",
        "sourcePath": "$.result.email"
      }
    }
  },
  "conditionalMode": "rules",
  "rulesConditionalConfig": {
    "rules": [
      {
        "id": "has_email",
        "name": "Email found",
        "condition": {
          "type": "GroupOp",
          "combinationMode": "And",
          "items": [
            {
              "type": "BinOp",
              "dataPath": ["email"],
              "operator": "NotEmpty"
            }
          ]
        }
      }
    ]
  }
}
```

Wire each rules destination by the matching rule id, in that destination node's `incomingEdges`.
On `nodes update`, `incomingEdges` **replaces** the node's full incoming-edge set — an entry you
omit (including the trigger connection) is silently removed, so read the node first and resend
existing edges plus the new one. `ruleId`, `routeId`, `transitionId`, and `isDefaultRoute` are
edge fields — they are only read inside an `incomingEdges` entry, never at the top level of the
node:

```json
{
  "incomingEdges": [
    { "sourceNode": "<conditionalNodeId>", "ruleId": "has_email" }
  ]
}
```

Always give a conditional a no-match fallback, in all three modes: create the destination and mark
its edge `isDefaultRoute: true`. That edge is the only thing the run reads — setting
`rulesConditionalConfig.defaultTargetNodeId` instead saves and validates, then fails the run with
"no default route connected" the first time nothing matches. If the run should stop instead of
routing onward, set `rulesConditionalConfig.endRunOnNoMatch` (rules mode only) and leave the
fallback edge off. Do not use a bare edge from a conditional unless it is truly the default route.

**Agentic mode:** set `conditionalMode: "agentic"` and include at least one stable route in
`agentConditionalConfig.routes`. A prompt without routes is rejected. When updating the prompt,
re-include the complete routes array.

```json
{
  "conditionalMode": "agentic",
  "agentConditionalConfig": {
    "prompt": "Decide whether the review is positive or negative.",
    "routes": [
      {
        "id": "positive",
        "name": "Positive",
        "description": "Praise or a good experience"
      },
      {
        "id": "negative",
        "name": "Negative",
        "description": "Complaints or a bad experience"
      }
    ]
  }
}
```

Create the destination nodes first, then wire each one with `incomingEdges` whose `routeId`
matches the route's `id`:

```json
{
  "incomingEdges": [
    { "sourceNode": "<conditionalNodeId>", "routeId": "positive" }
  ]
}
```

**Code mode:** set `conditionalMode: "code"` and put the Python handler in top-level `code`.
Call `context.transition_to("Destination Node Name", "branch_id")` with both arguments, then wire
the destination with the matching `transitionId`:

```json
{
  "incomingEdges": [
    { "sourceNode": "<conditionalNodeId>", "transitionId": "branch_id" }
  ]
}
```

For agentic and code conditionals, create placeholder destinations first, create the conditional
with stable route/transition ids, then attach each destination with the matching edge id.

### Message nodes

A Message node (`nodeType: "tool"` with `message`) writes a message, such as an email or LinkedIn
note, from fixed text, `{{input}}` variables and optional AI text written at run time. Use a Claygent
node instead when the whole message needs research or tools: a Message node's AI text sees only its
instructions, the node's inputs and the previous messages it includes.

Declare every variable in `inputSchema`, wired with `sourceNodeId`/`sourcePath`, in the same call:

```json
{
  "name": "Intro email",
  "nodeType": "tool",
  "inputSchema": {
    "company": {
      "type": "string",
      "sourceNodeId": "wfn_lead",
      "sourcePath": "$.result.company"
    }
  },
  "message": {
    "subject": "Quick idea for {{company}}",
    "body": "Hi team,\n\n{{ai:opener}}\n\nWorth a quick chat?",
    "aiText": {
      "opener": {
        "label": "Opener",
        "instructions": "One sentence on why **{{company}}** came to mind."
      }
    }
  },
  "incomingEdges": [{ "sourceNode": "wfn_lead" }]
}
```

`body` is Markdown, except:

- Each line is a line of the message and an empty line is a blank line, so use `\n\n` only for a
  gap. `<br>`, or `\` ending a line that another line follows, breaks a line inside a paragraph.
- Supported: `**bold**`, `_italic_`, `<u>underline</u>`, `[label](https://…)` links, and `- ` /
  `1. ` lists (indent to nest). Headings, quotes, code and other HTML are rejected.
- `{{ai:<id>}}` is AI text; give its `label` and `instructions` (Markdown, may use variables) under
  `aiText.<id>`, and keep the ids you read back. Write a literal `{` or `}` as `\{` or `\}`.
- `subject` is one line of plain text with variables and AI text, or `null` for none.

An update replaces `subject`, `body` and `aiText` together, so read the node first.
`previousMessageNodeIds` lists upstream Message nodes the AI text may read (omit to keep them, `[]`
to clear). Outputs: `$.result.subject`, `$.result.bodyMarkdown`, `$.result.bodyHtml` and
`$.result.bodyPlainText`. Message nodes have no list mode. If creation is rejected because message
nodes are not enabled, use a Claygent node.

### Rep task nodes

A rep task node (`nodeType: "tool"` with `repTask`) creates a task in Reps for a rep to work, and the
run continues without waiting for it. `repTask.taskType` picks the kind of task:

- `"email"` (the default): a drafted email that the rep reviews and sends. Clay does not send it.
- `"call"`: a call the rep places from their task list and logs.

Its inputs have fixed names. Declare the ones you use in `inputSchema`, wired with
`sourceNodeId`/`sourcePath`:

- Email: `recipient_email` and `body_text` (plain text) are required; `subject` and `body_html` are
  optional.
- Call: `phone_number` (a real number starting with `+` and its country code, such as `+14155550134`;
  spaces, dashes and brackets are fine, extensions are not) and `title` are required; `talk_track` is
  optional.
- `assignee` when `repTask.assignee` is `{ "type": "input" }`: a Clay user ID or a member's email.
- `due` when `repTask.due` reads an input: an amount for `after_input`, or an ISO date
  (`YYYY-MM-DD`) or date-time for `at_input`.

```json
{
  "name": "Rep follow-up",
  "nodeType": "tool",
  "inputSchema": {
    "recipient_email": {
      "type": "string",
      "sourceNodeId": "wfn_lead",
      "sourcePath": "$.result.email"
    },
    "subject": {
      "type": "string",
      "sourceNodeId": "wfn_intro_email",
      "sourcePath": "$.result.subject"
    },
    "body_text": {
      "type": "string",
      "sourceNodeId": "wfn_intro_email",
      "sourcePath": "$.result.bodyPlainText"
    },
    "body_html": {
      "type": "string",
      "sourceNodeId": "wfn_intro_email",
      "sourcePath": "$.result.bodyHtml"
    },
    "assignee": {
      "type": "string",
      "sourceNodeId": "wfn_route",
      "sourcePath": "$.result.assigned_rep.clay_user_id"
    }
  },
  "repTask": {
    "assignee": { "type": "input" },
    "due": { "kind": "after", "amount": 2, "unit": "days" }
  },
  "incomingEdges": [{ "sourceNode": "wfn_route" }]
}
```

- `assignee` is `{ "type": "user", "userId": <Clay user id> }` for one member, or `{ "type": "input" }`
  to read it per run, for example from the rep routing action's `$.result.assigned_rep.clay_user_id`.
  Viewers can't be assigned tasks.
- `due` is `null` for no due date, or one of:
  - `{ "kind": "after", "amount": 2, "unit": "days" }`: units are minutes, hours, days or weeks,
    as elapsed time.
  - `{ "kind": "after_input", "unit": "hours" }`: the amount comes from the `due` input.
  - `{ "kind": "until", "until": … }`: the next matching day and time, in the same shape as a
    delay node's `delayUntil`.
  - `{ "kind": "at_input" }`: the time comes from the `due` input, as an ISO 8601 date or date-time.
- Each `repTask` write replaces `assignee` and `due`; omit `priority` to keep it, and omit `taskType` to
  keep the node's type. `mode` follows the type and can be left out.

A run creates one task per node visit, and a rerun creates another. Rep task nodes have no list mode.
Outputs: `$.result.taskId`, `$.result.status`, `$.result.created`, `$.result.assigneeUserId` and
`$.result.dueAt`. If creation is rejected because rep task nodes are not enabled, tell the user;
there is no substitute.

### Triggers, audiences, and draft vs live

**Triggers** start a workflow (signals, audience segments, schedules, webhooks, Clay tables, CSV
uploads, Find leads searches). Create/edit them with `clay workflows triggers …`. Clay table
triggers remain UI-only. A Find leads trigger (`triggerType: "action_source_scheduled"`) runs a
Clay search and starts one run per record it finds; if a Find leads skill (`workflows-find-leads`)
is in your catalog, follow it for the `dataSource` shape and how to run the trigger.

**Running a workflow from a CSV** (one run per row): a CSV trigger keeps the file linked to the
trigger node, so the same rows can be run again later. Use the `clay workflows triggers csv`
commands, including for a CSV the user dropped in chat (at `/mnt/session/uploads/<filename>`).
See `csv-triggers.md`. For an ad-hoc run over a CSV's rows, run the workflow as a routine
instead. A routine needs a manual trigger whose inputs match the CSV headers, so add one if the
workflow lacks it (see "Running a workflow as a routine" below).

**Choose the trigger from context.** When the choice is clear and the user requested
a draft, create it without asking for confirmation again. When signals, segments, or other sources could
match the request, use the user's intended event, population, cadence, and prior
discussion to distinguish them. A shared keyword does not favor any trigger type.
If the choice remains ambiguous, ask the user to choose between the plausible sources
and wait before binding the trigger. Do not pick a default and merely ask to proceed. Read
`trigger-selection.md` for selection rules and examples.

**Audiences inside a workflow** (`upsert-audiences-record`, `audience_segment` trigger):
`audiences.md`.

**Ad lead form triggers** (`ad_lead_form`, Meta or LinkedIn lead gen forms) are created only in
the workflow editor. When a workflow has one, or the user wants ad leads saved to Audiences, read
the complete `/workflows-ad-lead-forms` skill and follow it together with this skill.

**Draft vs live** and how test runs relate to publish: see `publishing.md` and `testing.md`.

**Investigating run data** (failures, traffic, durations, credits, searching run content):
`clay workflows analysis …` — see `run-analysis.md`.

## Command reference

Every command's `--input`/`--inputs` accepts inline JSON, a file path, or `-` for stdin — pick
whichever is easiest to construct for the payload at hand. Run `clay workflows <command> --help`
for the exact output shape, error codes, and examples before using a command for the first time;
don't guess at flags.

### Creating and loading a workflow

- Create: `clay workflows create --name "My Workflow"` — returns `{ id, name, url }`. Share `url`
  as `[Open workflow](<url>)` (see `presenting.md`).
- Get: `clay workflows get <workflowId>` — same shape. Share `url` the first time you load an
  existing workflow.
- Update name: `clay workflows update <workflowId> --name "New name"` — returns the updated
  workflow.
- Delete: `clay workflows delete <workflowId>` — admin-only, deletes the workflow and its triggers,
  and has no undo operation. Run it only when the user explicitly asks to delete the
  workflow. A repeated delete returns `not_found` rather than succeeding again.

### Reading a workflow

- `clay workflows graph get <workflowId> [--mode summary|full]` — `--mode full` returns per-node
  configuration; omit for a lighter summary (nodes, edges, triggers).
- `clay workflows nodes get <workflowId> <nodeId>` — cheaper than a full-graph read when
  you only need one node. Returns `{ "node": <object> }` — the writable fields live under `.node`,
  not the top-level envelope.

### Editing nodes

- Insert at a selected target: `clay workflows nodes insert <workflowId> --input <json|file|->` — when
  the current context names a workflow insertion target, pass its `type`, `nodeId`, and optional
  `handleId` through as `target` and describe the new node as `step`. Use this instead of manually
  creating and rewiring a node. The command reads the current graph and atomically preserves the
  downstream path. Native waterfall candidates use `step.kind: "waterfall"` and `waterfallConfig`;
  follow `/workflows-discover-actions` to map inputs and preserve provider order.
  Configure other node fields afterwards with `nodes update`.
- Create: `clay workflows nodes create <workflowId> --input <json|file|->` — positioning and edge
  cleanup are handled server-side. Read an existing node first (`nodes get`) and take fields from
  `.node` for the writable shape — it's dynamic per node type. Feeding the whole get envelope into
  `--input` is a validation_error.
- Update: `clay workflows nodes update <workflowId> <nodeId> --input <json|file|->` —
  only the fields in `--input` change. For native waterfalls, read `node.waterfallConfig`, modify
  its shared inputs or provider input overrides, and send the complete `{ "waterfallConfig": ... }`
  as a separate update. Preserve template selection, provider order, and provider IDs. This uses
  the waterfall save path without executing providers; do not edit the generated call bindings
  or hidden child nodes directly.
- Delete: `clay workflows nodes delete <workflowId> <nodeId>` — edge cleanup handled
  server-side.
- Test one node: `clay workflows nodes test <workflowId> <nodeId> --source-run <runId>`
  or `--inputs <json|file|->` — starts a partial run of only that node, then terminates.
  Nothing downstream of the node runs, so this is for debugging a node, never for recovering
  failed runs — see "Recovering failed runs" in `testing.md` for that. Returns immediately (does
  not poll); inspect with `clay workflows runs get`. Pass `--source-run`, `--inputs`, or both;
  with both, `--inputs` replaces the matching inputs recorded in the source run.
- Account agents (agent nodes backed by a platform-managed Claygent with account context):
  `clay workflows nodes create-account-agent <workflowId> <nodeId> [--name <name>]` links a new
  one, from the platform template, to an agent node that has no linked agent — create the node
  bare (name and edges, no agent fields), run this with a specific `--name`, then set the prompt
  and tasks on the linked node. `clay workflows nodes upgrade-to-account-agent` converts a node
  already backed by a regular Claygent, and is one-way. Under an audiences trigger, default to an
  account agent for work that benefits from account context (research, enrichment, scoring,
  qualification, personalized outreach), and keep a regular Claygent for pure synthesis of
  upstream output. Account agents created from a workflow cannot search the web, so give
  public web research to a regular Claygent, downstream of the account agent when the step
  also needs account context (see `account-agents.md`). Include a downstream write-to-audiences node for account-agent results,
  reusing an existing node when possible; follow `audiences.md` for mappings and explicit
  destination or no-save instructions.
- **Read `account-agents.md` in full before any account-agent work** (linking, upgrading,
  swapping, editing prompt/tasks, or changing `accountId` wiring). Preconditions, `accountId`
  wiring, the ambiguous `auth_forbidden`, timeout-retry semantics, and what an account agent
  already sees live there; `--help` carries exit codes and examples.

### Canvas node groups

Read `node-groups.md` before planning or building a workflow that will have more than
8–10 nodes, and when reviewing one that already does. Follow its grouping policy: group
new large graphs as you build; suggest grouping existing large ungrouped graphs and wait
for the user before changing them.

### Validating and formatting

- `clay workflows graph validate <workflowId>` — structural checks only. Read-only: it neither
  repositions nodes nor persists a snapshot.
- `clay workflows graph format <workflowId>` — validates and re-runs auto-layout. Unlike
  `graph validate` this persists a snapshot, so it needs edit access.

### Running a workflow

- `clay workflows runs test <workflowId> [--inputs <json|file|->] [--audience-segment <id> --limit <n>] [--trigger <triggerId>]`
  starts a run (`--limit` is required with `--audience-segment`; `--inputs`, `--audience-segment`,
  and `--trigger` are mutually exclusive). `--trigger` runs a source trigger — Find leads, CSV
  upload, or audience segment — and starts one run per record; the trigger must be live, which
  for Find leads and segment triggers means publishing the workflow first (a CSV trigger is live
  from creation). `runs get`, `runs steps`, `runs list`, `runs pause`, `runs resume` inspect and control
  runs, and `clay workflows publish <workflowId>` ships the draft. Flags, the `--wait` poll, and
  which runs exercise draft vs live are in `testing.md` and `publishing.md`.
- `clay workflows runs rerun <workflowId> <runId...>` recovers failed runs: each one restarts at
  the node it failed on and continues through the rest of the workflow, on the published version.
  It spends credits, so run it with `--dry-run` first and confirm `rerunCount` and
  `estimatedCredits` with the user. The estimate is approximate; see `testing.md` for when it
  runs low. See "Recovering failed runs" in `testing.md`.

### Running a workflow as a routine

Register a workflow as a routine when the user wants to run it on demand over records they
supply (CSV rows, a pasted list) or call it from Clay MCP or the API. An unregistered workflow
isn't visible there:

```bash
clay routines create workflow <workflowId> --name "<what it does, e.g. Route inbound leads>"
```

- The routine's inputs are the workflow's manual trigger `inputSchema`, so the workflow needs a
  manual trigger, and its property names are the keys each run item must use.
- Keep those properties to `string`, `number`, `integer`, or `boolean`. A routine with any
  other input type is hidden from Clay MCP.
- Name it for its use case. Agents choose routines by name and description.

Then run it with `clay routines runs start` (see `routines`).

### Testing actions and code

- `clay workflows actions test <packageId> <actionKey> [--inputs <json|file|->]` — consumes
  credits. Returns `{ "result": <json|null>, "metadata"?: <object> }` — action fields live under
  `.result` (use those for `$.result.<field>` wiring); `metadata` is credit/refund accounting when
  the runner reports it. A `result` of `null` with `metadata.status` `SUCCESS_NO_DATA` means the
  action ran fine and found nothing — that is a valid result, not an error.
  Discover `packageId`/`actionKey` with `/workflows-discover-actions`, and the input shape
  with `clay workflows actions schema`.
- `clay workflows code test --file <path|-> [--inputs <json|file|->] [--output-schema <json|file|->]`
  — runs Python in the code-node runtime to test code before adding it to a node. The file must
  define `handler(context)` returning a dict. `--inputs` backs named calls such as
  `context.get_input("email")`; `get_input()` requires a key and has no zero-argument form. The
  same limits as code nodes apply: standard library only (without the modules listed under code
  nodes), no network, 1 second. **Before saving code with declared outputs, pass
  `--output-schema` with the `outputSchema` you will save on the node — flat fields or the
  JSON Schema returned by `nodes get`.**
  If output-schema validation is unavailable, test the saved node with `clay workflows nodes test` instead.
  Without output-schema validation, success only means execution succeeded. Exits 0 even on handler
  or schema failure — require `.isError != true and .outputSchemaValidated == true` for a schema
  test.

Both are single-shot previews. External CLI users have per-user daily caps (defaults ~25 action
tests and ~10 code tests, overridable per workspace). Clay's hosted agents are exempt.
Use them to confirm an input/output shape,
never to enrich or process a batch of records: for that use a managed routine
(`clay routines runs start`), a table column, or a workflow node, none of which are subject to
those caps.

`rate_limited` (HTTP 429, exit 4) includes daily caps and temporary throttling. If the message
says the daily allowance is exhausted, stop testing; do not sleep or retry in this session.
`details.retryAfter` gives the delay in seconds.

### Workflow run allowance

When the server reports that a workflow has reached its run limit, explain the limit rather
than retrying or treating it as invalid workflow input. The CLI may label this response
`validation_error`; use the message to distinguish it from other validation failures.

- Where enabled, Free/Trial workspaces have a lifetime allowance of 100 runs per workflow,
  not per workspace or per month. Paid plans do not have this cap. Use the server response
  as the source of truth; do not assume the limit is enabled for every workspace.
- Successful and unfinished runs count, including hidden or deleted runs. Failed and
  cancelled runs do not count. Do not calculate remaining allowance from the visible run
  history, which may be filtered or limited by the plan's history window.
- Tests that create workflow runs consume this allowance too. Standalone action/code
  previews have the separate daily caps described above. Credits and API rate limits are
  separate from the workflow run allowance.
- Explain that upgrading allows more runs; do not suggest copying a workflow or deleting
  runs to bypass the limit. After a confirmed upgrade, allow up to about a minute for the
  plan to refresh instead of asking the user to upgrade again. If it still blocks after
  that, report the issue rather than repeatedly retrying.

### Triggers

- Get: `clay workflows triggers get <triggerId>` — trigger ids come from `clay workflows graph get`,
  which returns them alongside the nodes; a workflow id is not accepted here.
- Create: `clay workflows triggers create <workflowId> --input <json|file|->` — the one trigger
  command that takes a workflow id. Its output is a confirmation, not the trigger — see the wiring
  note below. The writable shape is dynamic per trigger type — read an existing trigger first, same
  pattern as nodes. When no trigger of the target type exists to read, the core writable fields per
  type: `audience_segment` = `triggerType, segmentId, entityType ("CONTACT"|"ACCOUNT")`;
  `audience_signal` = `triggerType, signalId (signal.id, "sig_…"), entityType`;
  `audience_scheduled` = those plus `scheduleConfig` (optional `batchProcessing`, below);
  `scheduled` = `triggerType, scheduleConfig`;
  `webhook` / `manual` = `triggerType, inputSchema`. `clay_table` triggers cannot be created
  from here — they are wired from inside a Clay table ("Invoke Workflow" action).
  For the `scheduleConfig` shape and the remaining trigger types, read
  `clay workflows triggers create --help` — it is the single source for the field detail.
- Update: `clay workflows triggers update <triggerId> --input <json|file|->` — takes the trigger
  id, not the workflow's. Only the fields in `--input` change.
- Delete: `clay workflows triggers delete <triggerId>` — trigger id again.
- CSV: `clay workflows triggers csv upload|run|remove <triggerId>` — link a CSV file to a
  `csv_upload` trigger and run one workflow run per row. See `csv-triggers.md`.

**Webhook payloads:** the trigger URL (`webhookUrl` on `triggers get`) accepts a JSON body. An
object body becomes the run inputs as-is, so `inputSchema` describes the object and downstream
nodes read `$.email`. A top-level array body is stored whole under `payload`, never spread into
index keys, so declare `"payload": { "type": "array", "items": { … } }` in `inputSchema` and read
`$.payload[0].email` (or iterate it in a list-mode node with `listEntriesRef` `$.payload`). Senders
like HubSpot post arrays of events, so check the sender's shape before writing the schema. When you
control the sender, post an object.

**Audience multi-segment sharing:** multiple `audience_segment` triggers (different `segmentId`s)
may share one trigger node when they have the **same trigger type** and the **same outgoing edge**.
Multiple `audience_scheduled` triggers may share a node when they also have the **same schedule**.
Pass an explicit `workflowNodeId` to bind/share; omit it (or pass `createTriggerNode: true`) to get
a new node. Do not mix `audience_segment` with `audience_scheduled` on one node. `audience_manual`
is a run companion created by the UI/run path — do not create it via the CLI.

**Audience batch processing:** on `audience_scheduled`, `batchProcessing: {"batchSize": <n>}`
makes each scheduled run process the next `<n>` segment members not yet processed in this pass,
instead of rerunning every member, and the trigger pauses itself once all members are done.
`null` (or no field) means every run reruns the whole segment. `triggers get` returns
`{batchSize, startedAt?, completedAt?}` or `null`. Before publishing a scheduled audience trigger
the user wants to process incrementally, set `batchProcessing`, then `triggers get` and quote the
returned `batchSize` back. Never describe per-run behavior the read-back does not show: with
`batchProcessing: null`, publishing reruns the whole segment on every run.
Turning batching back on after `null` reruns every member unless the pass was unfinished and the
disable unpublished; treat it as a full-segment run for the cost policy and confirm with the user first.

### Enabling batching on a tool node

Some actions support batching multiple workflow runs into a single provider call, cutting
cost/rate-limit pressure for high-volume workflows. Not every action supports it, and the
catalog doesn't flag which ones do — enable batching only when the user explicitly raises
batching, rate limits, or large volumes of rows/runs; never proactively.

Set it via `nodes update` after the tool node already has `tools` configured:

```bash
clay workflows nodes update <workflowId> <nodeId> --input '{
  "batchRunSettings": { "enabled": true, "maxBatchSize": 50 }
}'
```

`maxBatchSize` is optional and gets clamped to the action's real maximum. If the action
doesn't support batching, the update rejects — relay that to the user rather than retrying.
Create with `tools` first, then enable batching in a follow-up update (same conversation turn
is fine as two calls).

### List mode (Repeat)

An agent, code, tool, or workflow function call node (including a native waterfall) can run
once per item in an upstream list instead of once over the whole list. In the editor this is
the **Repeat** toggle. Describe it to the user as **"runs once per item"** — never say it "maps
over the list" or call it a map/loop.

Enable it on the node with `listMode: true` **and** `listEntriesRef` in the same
`clay workflows nodes update` (or on create), pointing at the upstream array:

```bash
clay workflows nodes update <workflowId> <nodeId> --input '{
  "listMode": true,
  "listEntriesRef": { "sourceNodeId": "wfn_upstream", "path": "$.results" }
}'
```

Always set `listEntriesRef` when turning list mode on: without it the node looks for an
`entries` input instead of the upstream array, and repeats over the wrong thing. Pass
`null` to clear it.

For tool nodes, map each input that should vary per item with `inputMappingConfig` `item`
(`{ "type": "item", "path": "$.field" }`) — not a `reference` to the upstream list (that
resolves to the whole aggregate). See `data-passing.md`. For list-mode code nodes, the item
is under `input`: use `context.item`, `context["input"]`, or `context.input`. Code tests pass
`--inputs` verbatim, so wrap each test item as `{"input":{"name":"Ada"}}`.
`listFailureMode` is `"fail_at_end"` (default: fails the node if any item fails) or
`"ignore_errors"` (keeps the successful items and continues). `ignore_errors` only covers a
partially failed list: if every item fails — including a one-item list whose item fails — the
node still fails and the run stops.

**When to use it:** the same per-record work over a list (enrich each row, draft one message
per lead), inline on one node. **When not:** a single aggregate step over the whole list — leave
`listMode` off.

**Function calls and waterfalls:** read `repeat-function-calls.md` before turning on Repeat for a
workflow function call or native waterfall, and whenever each item needs more than one step — it
covers mapping the current item, the two-update waterfall flow, and when to use one repeating
function call instead of a chain of Repeat nodes.

Unsupported on account agent nodes and on trigger/conditional/map/reduce/collect/fork/join.
If the workspace has list mode disabled, the update rejects — relay that rather than retrying.

### Wiring the first node after creating a trigger

`triggers create` returns `resourceId` (the **trigger** id) and `workflowNodeId`
(the canvas node id). Use `workflowNodeId` to wire the first node; do not use
`resourceId` as an `incomingEdges` source. If the response omits `workflowNodeId`,
read `clay workflows triggers get <resourceId>` to obtain it.

```bash
clay workflows triggers create wf_1 --input trigger.json > created-trigger.json
jq '{resourceId, workflowNodeId}' created-trigger.json
```

Wire it with `incomingEdges: [{ "sourceNode": "<workflowNodeId>" }]`. Do not send
`sourceNodeId` inside `incomingEdges` — graph summary uses that key on the read side.

**Trigger edge constraint:** a trigger may have zero or one direct outgoing edge, never more.
Before wiring a node with `incomingEdges` from a trigger's `workflowNodeId`, check the default
summary for an edge already leaving that trigger node —
`clay workflows graph get <workflowId> | jq '.summary.edges[] | select(.sourceNodeId == "<triggerNodeId>")'`.
If it already has a target, do not add another direct edge; add work downstream instead, or ask
the user whether to rewire. Before validating or running, each trigger must be connected to one
first executable node.

## Capabilities without a `clay workflows` command

Building a workflow often touches adjacent surfaces — tables, functions, audiences — that have
their own CLI commands elsewhere rather than a `clay workflows` subcommand:

- **Table schema** — `clay tables columns list <tableId>` (abbreviated) or
  `clay tables columns get <tableId>` (full settings).
- **Table rows** — `clay tables query-live <tableId> --query <clayql>`, against live Postgres.
  It takes ClayQL directly — write the query yourself off the columns above; there is no
  natural-language query option. Don't reach for `clay tables query` instead — that reads a
  different store (synced ClickHouse, gated on Enterprise sync).
- **Table configuration migration** — read `table-primitives.md` when rebuilding
  table columns as workflow nodes. Preserve referenced resources and verify the
  persisted bindings before testing.
- **Provider waterfall migration** — read `table-waterfalls.md` before translating
  a table's provider waterfall. Check for an equivalent installed function and preserve
  the input bindings, run condition, provider order, validation, and output selection.
- **Bulk enrichment migration** — for a known bulk enrichment table, use
  `clay tables columns get <tableId>` to determine the
  source origin and column DAG. When a source includes `audience`, use its configuration
  (global when `isGlobal`; otherwise `segments[].id`). Do not assume every bulk enrichment is
  Audiences-backed.
  For an Audience-backed bulk enrichment migration, or when the destination already
  has type `audience_enrichment`, read
  `/workflows-audience-enrichment` before translating the columns. Its migration guidance
  explains how to replace the table's source-record lookups and extracted columns with
  bindings to the existing audience trigger.
  `clay tables rows list <tableId> --limit <n>` is only an optional,
  unfiltered, unordered sample (`n` at most 20): it returns `truncated: true`, accepts and returns no
  cursor, and completed passthrough rows may already be deleted. Never treat it as a complete source dataset.
- **One audience segment** — `clay audiences get <audienceId>`, which includes the filter AST that
  selects its records.
- **Audience record fields** — `clay audiences fields list` with `--entity-type people` or
  `--entity-type companies` returns the ids for `upsert-audiences-record` (see `audiences.md`).
  Mind the two vocabularies: the flag is `people`/`companies`, while `upsert-audiences-record`
  still wants `entityType: "CONTACT"`/`"ACCOUNT"`.
- **Function schemas** — `clay functions get <functionId>` returns `inputSchema` and `outputSchema`.
  `clay workflows actions list` carries the `functionId` to pass it.
- **Listing what exists** — one command per resource kind: `clay workflows list`,
  `clay tables list`, `clay functions list`, and
  `clay audiences list --entity-type people|companies` for audience segments.

The raw CPJ Search DSL has no CLI command; `clay searches query-mode`
covers Clay search itself (see the `searches` skill). When a capability isn't listed here and has no
`clay` command, it's genuinely unavailable rather than hidden — tell the user that instead of
hunting for a command that will not appear.
