---
name: routines
description: Clay routines — create a routine from an existing function/workflow, then run a saved routine that exists in this workspace. Use when the user asks to create/register a routine, or to run, execute, or trigger a function, workflow, or routine (by name or id), pass it inputs, or check the results/status of a run. For building a new workflow, use the workflows entry-point skill instead.
---

# Running Clay routines

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

A **routine** is the runnable unit in Clay: a saved **function** or **workflow** that
already exists in this workspace. This skill is about _running_ an existing routine and
getting its results — not building one.

- To **build or edit** a workflow, use the workflows entry-point skill.
- If no existing routine matches a request for custom Claygent or LLM work, use the
  `/workflows-claygent` skill to build and run it.
- To **query data** out of a Clay table, use the tables entry-point skill.
- To **find the records** to run a routine over, use the `searches` skill for net-new people
  or companies, or the `audiences` skill for members of a saved audience, then feed the
  results in here.
- To **write people or companies into Audiences**, run a routine whose underlying
  workflow contains `upsert-audiences-record` (for example, to persist Search results).
  Items pipe in the same as other runs, using `workflow:<id>` instead of `function:<id>`.
  If no such workflow exists, build it via the `workflows` skill's
  `audiences.md`, then `clay routines create workflow`.
- To run a routine **over HTTP** from a service or app (not a one-off shell task), use
  the `public-api` skill.

Routines run **asynchronously**: you start a run, then poll for results.

## 1. Find the routine

Don't assume a routine id. List what exists and match the user's request to one:

```bash
clay routines list            # routines in this workspace
clay routines get <id>        # full config and input schema
```

`clay routines list` is **paginated** — a workspace can have far more routines than one
page. Page through with `--cursor` until the response has no `cursor` before concluding a
routine doesn't exist. Each routine carries a `source` field in the response — `list` has no
filter flag, so filter client-side (e.g. `| jq '.data | map(select(.source == "managed"))'`).
`managed` routines are Clay's built-in enrichers
(emails, domains, firmographics) and should be your first choice for standard enrichment;
`custom` are workspace-built. Decide by **input schema**, not name — e.g. the managed
**Work Email** routine needs Full Name + Company Name + Company Domain, so resolve the
domain first with the managed **Company Domain** routine when you only have a company name.

`clay routines get <id>` is important before running: it shows the routine's **input
schema** so you know exactly which fields each item needs.

### Link the user to the underlying function or workflow

Whenever you show the user a routine — from `clay routines list` or `clay routines get` —
give them a link to open its underlying object in the Clay app so they can inspect or edit
it. This matters most in a headless environment (Claude Code, Cursor, a shell) where the
user has no Clay tab open.

A routine id encodes the object it wraps: `function:<tableId>` wraps a table,
`workflow:<workflowId>` wraps a workflow. Split off the id after the `:` and combine it
with the workspace id (`clay whoami | jq -r '.workspace.id'`) to build the link:

- **Function** (`function:<tableId>`) → `https://app.clay.com/workspaces/<workspaceId>/tables/<tableId>`
- **Workflow** (`workflow:<workflowId>`) → `https://app.clay.com/workspaces/<workspaceId>/terracotta/tc-workflows/<workflowId>`

For **function** routines, both `list` and `get` return a `source` (`managed` for a
Clay-managed default function, `custom` for one built in this workspace) and, for custom
functions, a `createdBy` (`{ id, name, email }`; `null` for managed ones). Use these to tell
the user which functions are Clay-managed vs. their team's own, and who authored a custom
one — e.g. group them by `source`, or note the author when disambiguating similar functions.

### Workflow functions

Workflow functions are functions backed by workflows. Their callable id is
`workflow:<workflowId>`, not `function:<workflowId>`. Discover them with
`clay workflows actions search` or `clay functions list` (includes published workflow functions when enabled).
Function listing returns workflow functions first, then table functions, newest first within each group.
Follow pagination cursors to reach table functions; the first page is not the newest functions overall.
Inspect a workflow function with `clay functions get workflow:<workflowId>` before registration.
This returns the published input/output schemas and the underlying `id`. The `schema` string
contains the published workflow implementation, like the implementation context returned for table functions.
`candidateId` is a search identifier; do not use it as a routine id.

Register a workflow function with `clay routines create workflow <workflowId> --name "My function"`
using the raw `id`, then run it with `clay routines runs start workflow:<workflowId>`.
Workflow functions need no `--entity-type`. Registration is required for routine execution,
but not for inspection or inserting a `subworkflow_call` into another workflow.
Direct routine runs use the workflow's normal manual trigger, including its configured snapshot pin.
To test unpublished changes, set that trigger's `snapshotId` to `latest` with `clay workflows triggers update`.
Read `clay routines get workflow:<workflowId>` for the inputs accepted by a direct run.
A `subworkflow_call` uses the latest published version by default; function inspection describes that published version.

### Create a routine from an existing function or workflow

If no routine exists yet for a function (a table) or a workflow, expose it as a runnable
routine with `create`. This registers the underlying object as a routine.

```bash
clay routines create function <tableId> --name "My contact routine" --entity-type contact
clay routines create workflow <workflowId> --name "My workflow routine"
```

- `type` is `function` or `workflow`; `objectId` is the table id (function) or workflow id.
- `--name` is **required** for both types.
- `--entity-type` (`contact` or `company`) is **required** for function routines and rejected
  for workflow routines.
- The routine id is built from the type and object id, e.g. `function:t_abc`.

Use `clay routines update <id>` to change a routine's name, description, or entity-type
later. See `clay routines create --help` / `clay routines update --help` for the full flags
and JSON shape.

## 2. Check the cost and your balance before running

Before starting a run, inspect its estimate and the workspace balance internally. Follow
the shared cost policy in `workflows-discover-actions/cost-and-budget.md` for disclosure and confirmation; ordinary authorized
runs do not need a cost-only check-in. `clay routines get <id>` includes a per-item estimate;
`clay credits balance` returns the remaining balance.

```bash
clay routines get function:t_abc123 | jq '.estimatedCreditCost'
clay credits balance | jq '{ balance, actionExecutionBalance, user }'
```

There are **two independent workspace budgets**, and a run needs enough of each:

- `estimatedCreditCost.perRun` is charged against the data-credit `balance`.
- `estimatedCreditCost.actionExecution` (when supplied) is charged against the separate
  `actionExecutionBalance` on action-execution pricing plans. A workspace can have plenty
  of `balance` but no action executions left — enough of one budget does not cover the other.
  A missing or null `actionExecution` does not identify the plan: it means the workspace is
  on legacy billing **or** the estimate carries no priced action executions. Whether
  `clay credits balance` returns `actionExecutionBalance` is what tells the plans apart —
  present means action-execution pricing, absent means legacy.

A run billed to the user also counts against their personal monthly credit limit,
reported as `user.limit` and `user.balance` (both null when they have none). Whether a run
is billed to the user depends on workspace settings, so treat `user.balance: 0` as a likely
blocker to mention, not a verified shortfall. A credit budget assigned to the user can also
stop a run, and `clay credits balance` does not report it.

For how to read the balance and how the cost fields work, see the help text:

```bash
clay credits balance --help
```

Only multiply per-item costs when they apply to the configured execution and all relevant
execution counts are known. Workflow estimates count nodes once and can omit branching
and fan-out; `containsVariablePricing: false` does not establish completeness. Do not turn
an incomplete base estimate into a total, even by labeling it approximate.

If a supported estimated total for **either**
budget exceeds its matching balance — `perRun × items > balance`, or
`actionExecution × items > actionExecutionBalance` — stop and tell the user instead of
starting a run that will only partially complete.

Undefined, null, incomplete, or inapplicable costs are unknown, not free. If asked, explain
that the total cannot be reliably estimated; otherwise continue within the authorized scope.

### Running low? Share a top-up link

When supported pricing shows insufficient balance, or a real billing failure occurs, read the
`credits-quotas-plans` skill and follow it for CLI top-up, auto top-up, and
billing UI options.

## 3. Run it

Start an async run, passing inputs per item:

```bash
clay routines runs start <id>     # see --help for how to pass items/inputs
```

- A single inline run takes **1-100 items**; each item is a set of `inputs` matching the
  routine's input schema.
- For larger sets, routines support a **batch** run over an uploaded JSONL file.
- A run can answer `approval_required`, because a routine's steps can act outside Clay. Present
  the request for approval as the `cli` skill describes. Approving starts the run, so don't run
  the command again.

Run `clay routines runs start --help` for the exact flags, the input/JSON shape, and how
to supply items.

## 4. Get the results

Runs are asynchronous. Prefer a single blocking call with `--wait` instead of hand-rolling a
poll loop:

```bash
clay routines runs get <run-id> --wait 60        # poll until complete / validation_failed / processing_failed, or 60s
clay routines runs get <run-id> --bulk --wait 60 # same for a bulk run (skip the inline probe)
clay routines runs get <run-id> --wait           # poll until complete / validation_failed / processing_failed (no budget)
clay routines runs get <run-id>                  # single request (may still be in_progress)
clay routines runs get <run-id> --bulk           # look up as a bulk run (bare flag, no value)
clay routines runs list                          # recent runs and their statuses
```

Check `.status` on the JSON before treating the run as done. With bare `--wait`, the command
blocks until `complete`, `validation_failed`, or `processing_failed`. With `--wait <seconds>`, if the budget expires
while still `in_progress`, the command exits 0 with that latest status — do not assume success.
Prefer a bounded `--wait <seconds>` for bulk runs: a bulk run that was stopped keeps reporting
`in_progress`, so bare `--wait` can wait forever.

Every response carries a `mode` of `inline` or `bulk`, and so does the output of
`runs start`. When it is `bulk`, pass `--bulk` on `runs get` so the run is looked up directly.
If you don't know the mode — a run id you were handed, or one from `runs list`, which does not
report it — omit `--bulk`; the response tells you the mode.

A completed bulk run reports a `resultUrl` rather than inline `data`. That URL is short-lived
(minutes) — download it promptly, and re-run `runs get --bulk` to mint a fresh one rather
than reusing a stale link. Results stay retrievable for about a day after the run finishes,
after which the id stops resolving.

Per-item results come back with a status (`complete` / `failed`) and either a `result`
or an `error`.

While an inline run is still `in_progress`, the response can include `data` with the items
that have finished so far (up to `--limit`, no `cursor`). Use those to act on early results
or show progress, but wait for `complete` before treating the result set as final.

`clay routines runs get` returns a single page of inline results. Since an inline run
has at most 100 items, `--limit 100` returns every result in one page. If you use a
smaller page size, the response includes a top-level `cursor` when more results remain —
pass it back via `--cursor` to fetch the next page.

## Authoritative details

```bash
clay routines --help
clay routines <cmd> --help
```
