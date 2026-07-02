---
name: routines
description: Clay routines — run a saved Clay function or workflow that already exists in this workspace. Use when the user asks to run, execute, or trigger a function, workflow, or routine (by name or id), pass it inputs, or check the results/status of a run. For building a new workflow, use the `workflows` skill instead.
---

# Running Clay routines

A **routine** is the runnable unit in Clay: a saved **function** or **workflow** that
already exists in this workspace. This skill is about _running_ an existing routine and
getting its results — not building one.

- To **build or edit** a workflow, use the `workflows` skill.
- To **query data** out of a Clay table, use the `tables` skill.
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

## 2. Run it

Start an async run, passing inputs per item:

```bash
clay routines runs start <id>     # see --help for how to pass items/inputs
```

- A single inline run takes **1-100 items**; each item is a set of `inputs` matching the
  routine's input schema.
- For larger sets, routines support a **batch** run over an uploaded JSONL file.

Run `clay routines runs start --help` for the exact flags, the input/JSON shape, and how
to supply items.

## 3. Get the results

Runs are asynchronous — poll until the run reports it's done:

```bash
clay routines runs get <run-id>   # status + results for a run (poll until complete)
clay routines runs list           # recent runs and their statuses
```

Per-item results come back with a status (`complete` / `failed`) and either a `result`
or an `error`.

## Authoritative details

The CLI help text is a machine-readable spec written for you to read — use it for the
exact flags, JSON output shape, and error codes:

```bash
clay routines --help
clay routines <cmd> --help
```

Full developer documentation (CLI reference, Public API reference, concepts) lives at:
https://claydevelopers.mintlify.app/llms.txt
