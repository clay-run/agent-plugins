---
name: routines
description: Clay routines — create a routine from an existing function/workflow, then run a saved routine that exists in this workspace. Use when the user asks to create/register a routine, or to run, execute, or trigger a function, workflow, or routine (by name or id), pass it inputs, or check the results/status of a run. For building a new workflow, use the `workflows` skill instead.
---

# Running Clay routines

A **routine** is the runnable unit in Clay: a saved **function** or **workflow** that
already exists in this workspace. This skill is about _running_ an existing routine and
getting its results — not building one.

- To **build or edit** a workflow, use the `workflows` skill.
- To **query data** out of a Clay table, use the `tables` skill.
- To **find the records** to run a routine over (people or companies from Clay's GTM
  database), use the `search` skill (`skills/search/SKILL.md`) first, then feed the results
  in here.
- To run a routine **over HTTP** from a service or app (not a one-off shell task), use
  the `public-api` skill.

Routines run **asynchronously**: you start a run, then poll for results.

## 1. Find the routine

Don't assume a routine id. List what exists and match the user's request to one:

```bash
clay routines list            # routines in this workspace
clay routines get <id>        # full config, integrations, and input schema
```

`clay routines get <id>` is important before running: it shows the routine's **input
schema** so you know exactly which fields each item needs.

For **function** routines, both `list` and `get` return a `source` (`managed` for a
Clay-managed default function, `custom` for one built in this workspace) and, for custom
functions, a `createdBy` (`{ id, name, email }`; `null` for managed ones). Use these to tell
the user which functions are Clay-managed vs. their team's own, and who authored a custom
one — e.g. group them by `source`, or note the author when disambiguating similar functions.

### Create a routine from an existing function or workflow

If no routine exists yet for a function (a table) or a workflow, expose it as a runnable
routine with `create`. This registers the underlying object as a routine and controls which
integrations (`api`, `mcp`, `claygent`) it's available on:

```bash
clay routines create function <tableId> --name "My contact routine" --entity-type contact --integrations api,mcp
clay routines create workflow <workflowId> --name "My workflow routine" --integrations api,mcp
```

- `type` is `function` or `workflow`; `objectId` is the table id (function) or workflow id.
- `--name` and `--integrations` are **required** for both types.
- `--entity-type` (`contact` or `company`) is **required** for function routines and rejected
  for workflow routines.
- The routine id is built from the type and object id, e.g. `function:tbl_abc`.

Use `clay routines update <id>` to change a routine's name, description, entity-type, or
integrations later. See `clay routines create --help` / `clay routines update --help` for the
full flags and JSON shape.

## 2. Check the cost and your balance before running

Before starting a run, check what the routine costs and whether the workspace can afford
it. `clay routines get <id>` includes the per-item cost estimate; `clay credits` returns
the remaining balance.

```bash
clay routines get function:tbl_abc123 | jq '.estimatedCreditCost'
clay credits | jq '{ balance, actionExecutionBalance }'
```

There are **two independent budgets**, and a run needs enough of each:

- `estimatedCreditCost.perRun` is charged against the data-credit `balance`.
- `estimatedCreditCost.actionExecution` (when supplied) is charged against the separate
  `actionExecutionBalance` on action-execution pricing plans. A workspace can have plenty
  of `balance` but no action executions left — enough of one budget does not cover the other. When not supplied the workspace is still on legacy billing and this balance can be ignored

For how to read the balance and how the cost fields work, see the help text:

```bash
clay credits --help
```

Multiply each per-item cost by the number of items. If the estimated total for **either**
budget exceeds its matching balance — `perRun × items > balance`, or
`actionExecution × items > actionExecutionBalance` — stop and tell the user instead of
starting a run that will only partially complete.

If a routines `estimatedCreditCost` is undefined, an estimate could not be generated for this routine. That does not mean running the routine is free.

### Running low? Share a top-up link

When the balance is low or short of the estimated cost, point the user at their billing
page to add credits. Get the workspace id, then give them the link:

```bash
clay whoami | jq -r '.workspace.id'
```

Build the URL with that id — the `addCredits=true` query param opens the buy-credits modal
directly:

`https://app.clay.com/workspaces/<workspaceId>/home?addCredits=true`

Share it as a "top up your credits" link

## 3. Run it

Start an async run, passing inputs per item:

```bash
clay routines runs start <id>     # see --help for how to pass items/inputs
```

- A single inline run takes **1-100 items**; each item is a set of `inputs` matching the
  routine's input schema.
- For larger sets, routines support a **batch** run over an uploaded JSONL file.

Run `clay routines runs start --help` for the exact flags, the input/JSON shape, and how
to supply items.

## 4. Get the results

Runs are asynchronous — poll until the run reports it's done:

```bash
clay routines runs get <run-id>   # status + results for a run (poll until complete)
clay routines runs list           # recent runs and their statuses
```

Per-item results come back with a status (`complete` / `failed`) and either a `result`
or an `error`.

`clay routines runs get` returns a single page of inline results. Since an inline run
has at most 100 items, `--limit 100` returns every result in one page. If you use a
smaller page size, the response includes a top-level `cursor` when more results remain —
pass it back via `--cursor` to fetch the next page.

## Authoritative details

The CLI help text is a machine-readable spec written for you to read — use it for the
exact flags, JSON output shape, and error codes:

```bash
clay routines --help
clay routines <cmd> --help
```

Full developer documentation (CLI reference, Public API reference, concepts) lives at:
https://claydevelopers.mintlify.app/llms.txt
