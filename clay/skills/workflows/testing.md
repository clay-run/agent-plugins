# Testing Workflows

For list-mode code tests, wrap the item: `--inputs '{"input":{"name":"Ada"}}'`.
If `context.input` is missing, fix the test inputs.

`clay workflows nodes test` runs list fan-out. Use `--source-run` to reuse upstream list
data, `--inputs` for manual node-step inputs, or both to replace some of the source run's inputs.

If `clay` isn't on PATH or `clay whoami` fails on auth, run the `setup` skill.

Tests that create workflow runs use the workflow's run allowance. For a run-limit error,
follow [Workflow run allowance](SKILL.md#workflow-run-allowance); retrying does not reset it.

## Commands

```bash
# Start a test run (input JSON on stdin via --inputs -; defaults to {})
echo '{"key":"value"}' | clay workflows runs test <workflowId> --inputs -
clay workflows runs test <workflowId>                  # no inputs
clay workflows runs test <workflowId> --live           # run the published (live) version

# Audience-segment backfill (up to --limit members) — runs the current draft unless --live
clay workflows runs test <workflowId> --audience-segment <segmentId> --limit 5
clay workflows runs test <workflowId> --audience-segment <segmentId> --record-ids 8814,8815
clay workflows runs list <workflowId> --audience-segment <segmentId>

# Run a source trigger (Find leads search, CSV upload, audience segment) — one run per record
clay workflows runs test <workflowId> --trigger <triggerId>                # CSV / segment: current draft; Find leads: published version
clay workflows runs test <workflowId> --trigger <triggerId> --live         # CSV / segment: pinned to the published version
clay workflows runs test <workflowId> --trigger <triggerId> --replay     # Find leads: re-run already-found records too
clay workflows runs test <workflowId> --trigger <triggerId> --limit 5    # audience segment trigger: --limit or --record-ids required
clay workflows runs list <workflowId>

# Partial single-node test (--source-run, --inputs, or both); nothing downstream runs
clay workflows nodes test <workflowId> <nodeId> --source-run <runId>
clay workflows nodes test <workflowId> <nodeId> --inputs '{"param":"value"}'
clay workflows nodes test <workflowId> <nodeId> --source-run <runId> --inputs '{"param":"value"}'  # replace one recorded input

# Recover failed runs: restart each at its failed node and run the rest of the workflow
clay workflows runs rerun <workflowId> <runId...> --dry-run
clay workflows runs rerun <workflowId> <runId...>
```

### Draft vs live when testing

- **Plain / manual `clay workflows runs test`** (with or without `--inputs`) starts a run
  via the manual trigger and exercises the **current draft**. Use this to verify
  unpublished edits.
- **`--audience-segment`** starts runs for members of that segment through the segment
  trigger's manual companion. It needs no publish — the companion is created live even while
  the segment trigger is still a draft — and like the plain form the runs exercise the
  **current draft** unless you pass `--live`. Real segment automation (membership changes,
  schedules) runs the live version, so a passing `--audience-segment` run does not prove the
  published graph works — use `--live` for that.
- **`--live`** (works with or without `--audience-segment`) pins the runs to the
  workflow's published (live) version instead of the draft. It fails with
  `validation_error` if the workflow has never been published.

- **`--trigger <triggerId>`** runs whichever source sits behind that trigger and starts one
  run per record it returns. Which graph the runs use depends on the source:
  - **CSV upload** and **audience segment** triggers run the **current draft** unless you pass
    `--live`, so you can keep editing and re-run the same records against the draft.
  - A **Find leads** trigger always runs the **published version** — the source hands its
    records to the trigger's live version, and `--live` changes nothing. Draft edits are not
    exercised until you publish; to check one node against a real record first, use
    `clay workflows nodes test <workflowId> <nodeId> --source-run <runId>` with a run the
    source already produced.

  The trigger named by `--trigger` must be live. A Find leads or audience segment trigger goes
  live when the workflow is published, so `clay workflows publish` first for those — "is draft,
  not live" means publish, not retry. To run segment members against the draft without
  publishing, use `--audience-segment` instead, which does not check the trigger's status. A
  CSV trigger is live from creation and needs no publish (see `csv-triggers.md`); do not publish
  just to test one. "has no source yet" / "has no CSV file
  yet" mean the source is not provisioned or no file is linked. It returns `{ ok: true }` rather
  than a run id — watch the runs with `clay workflows runs list`. On an audience segment trigger
  it is bounded like `--audience-segment`: pass `--limit` (max 10) or `--record-ids`. Triggers
  this command cannot run (manual, webhook, scheduled, signal, Clay table) are rejected; use the
  plain form or the trigger's own entry point for those.

`--record-ids` runs exactly those Audiences records instead of the segment's first
`--limit` members; pass one or the other, not both.

`clay workflows nodes test <workflowId> <nodeId> --source-run <runId>` can start at a new
or unexecuted node. Its current input mappings resolve against completed upstream steps in
the source run; configure mappings first or run from the producer if its output is missing.
An unfinished source step cannot be reused; use `--inputs` without `--source-run` instead.
Adding `--inputs` to `--source-run` replaces the matching inputs the node recorded in that run
and keeps the rest; a node that did not run in the source run has none to replace, so it takes
one flag or the other.

`--inputs`, `--audience-segment`, and `--trigger` cannot be combined. See `publishing.md`.

```bash
# Status / progress for a run
clay workflows runs get <runId>           # header + progress + map/reduce nodes
clay workflows runs get <runId> --nodes   # include every node
clay workflows runs get <runId> --verbose # + full inputs/outputs, mappings, entry steps
clay workflows runs get <runId> --node-id <nodeId>  # isolate one node, full map/reduce results

# List/filter the individual execution steps
clay workflows runs steps <workflowId> <runId>
clay workflows runs steps <workflowId> <runId> --status failed
clay workflows runs steps <workflowId> <runId> --node-id <nodeId>

# Pause / resume a run
clay workflows runs pause <workflowId> <runId>
clay workflows runs resume <workflowId> <runId>

# Publish the tested draft as live
clay workflows publish <workflowId> --name "July enrichment rollout"
```

When you create or first load a workflow, share its `url` as a clickable Markdown
link (`[Open workflow](<url>)`) — see `presenting.md`.

## Finding runs after starting a trigger

Inspect `clay workflows runs list <workflowId>` before choosing filters. On a fresh
workflow triggered once, its runs are sufficient; check the expected row count and
follow pagination when needed. On an existing workflow, use trigger IDs and creation
times to narrow the results, but these may not distinguish overlapping executions of
the same trigger.

`batchId` (CLI `.batch.id`) identifies a legacy workflow batch record. `batchKey`
(CLI `.batch.key`) is a trigger execution/deduplication key, not that record's ID.
Never compare them. A run can legitimately have no `.batch`; this does not mean it
hasn't started. The run-list output does not expose the trigger's batch key.

If a filter finds no runs, inspect the unfiltered response before polling again.
Runs can appear asynchronously; an empty lookup does not mean you should retrigger
the workflow.

## Watching a run to completion

Prefer a single blocking call with `--wait` instead of hand-rolling a poll loop.
Once you have run IDs, wait on those runs rather than repeatedly rediscovering them.
There is no universal completion time: code, provider calls, agent steps, and explicit
delays take different amounts of time. Use status and progress to decide whether more
waiting is useful.
`status` is one of `pending` / `running` / `paused` / `waiting` / `completed` /
`failed` / `cancelled`; `progress.percentage` tracks progress.

```bash
clay workflows runs get <runId> --wait           # poll until terminal
clay workflows runs get <runId> --wait 60        # same, but stop after 60s
clay workflows runs get <runId>                  # single request (may still be running)
```

Terminal statuses are `completed`, `failed`, `cancelled`, and `paused`. `paused`
is returned rather than waited through — the run will not advance without
`clay workflows runs resume` or the paused trigger goes live. `--wait` also returns when a node has
`waitingReason` `agent_step_limit_reached`; other `waiting` reasons are not
terminal (async work is still in flight). If `--wait` returns `status: waiting`,
human intervention is required somewhere. With `--wait <seconds>`, any other
non-terminal status means the budget ran out — check `.status` before treating
the run as done.

## Recovering failed runs

When runs failed partway through, for example during an outage at an integration, never recover
them with `nodes test`. It runs only the one node and then ends the run, so every node after it is
skipped — anything those nodes write (CRM updates, campaign or sequence enrollment, attribution)
silently never happens, while the run reports `completed`.

Use `clay workflows runs rerun` instead. If `clay workflows runs rerun --help` fails, the CLI
predates the command: ask the user to update it, or to open the workflow's Runs view in Clay,
select the failed runs, and choose Re-run > Resume from failed node.

```bash
# Collect the failed runs, preview the re-run, then start it
clay workflows runs list <workflowId> --status failed --created-after <outageStart> | jq -r '.data[].runId' > failed.txt
clay workflows runs rerun <workflowId> $(cat failed.txt) --dry-run | jq '{rerunCount, estimatedCredits}'
SUBMISSION_ID=$(uuidgen)
clay workflows runs rerun <workflowId> $(cat failed.txt) --submission-id "$SUBMISSION_ID"

# Watch the re-runs it created (newest first)
clay workflows runs list <workflowId>
```

- The default, `--from failed`, restarts each run at the node it failed on and continues through
  every node after it. Runs that did not fail are skipped. `--from node --node <nodeId>` starts
  every listed run at one node, and `--from trigger` starts each run over from its trigger.
- `--from node` and `--from trigger` run every step from the start point again, including steps
  that already succeeded, so their effects (emails, CRM writes, sequence enrollments) happen a
  second time. For recovery, use the default `--from failed`, and only pick another start point
  when the user has confirmed those steps should repeat.
- Re-runs use the **published** version, so publish any fix before re-running. A workflow that
  was never published can't be re-run this way.
- Each record re-runs once, from its latest run, so `rerunCount` can be lower than the number of
  run ids passed.
- `estimatedCredits` is approximate. It counts every branch a run could take, but a step that
  repeats per list item (a node in Repeat mode) counts once, so for those workflows the actual cost
  can be much higher. Say so when you present the estimate for such a workflow.
- `runs list --status failed` returns one page; follow `cursor` to collect every failed run before
  re-running.
- The re-run can be held for approval (`approval_required`). Present it as the error says.
  Approving starts the re-runs, so don't run the command again afterwards.
- Never retry a failed re-run with a new submission id: the server may have queued the first one
  before the error. Rerun with the same id instead. An id that was already accepted starts nothing
  new, so the retry can't start a second set of runs. A failed submit names its id in the error's
  `details.submissionId`. Minting it yourself, as above, also covers a command that dies before
  printing anything.

## Inspecting what a run did (instead of "logs")

There is no `logs` command. The structured output of `runs get` and `runs steps`
is strictly better than grepping formatted text — filter it with `jq`:

```bash
# Full, untruncated inputs/outputs per node
clay workflows runs get <runId> --verbose | jq '.nodes'

# Just the failed nodes and their errors
clay workflows runs get <runId> --nodes | jq '.nodes[] | select(.status=="failed") | {nodeId, errors}'

# Errors across the failed steps (including each map entry)
clay workflows runs steps <workflowId> <runId> --status failed | jq '.data[].errors'

# One node's config + full map/reduce results
clay workflows runs get <runId> --node-id <nodeId> | jq '.nodes[0]'
```

## Tell the user what the run actually did

Don't dump raw run JSON at the user. After a run, **narrate the trace node-by-node**: for each node, what it received, what it produced, and (if it failed) why. `--verbose` gives you the untruncated inputs/outputs to do this from:

```bash
clay workflows runs get <runId> --verbose | jq '.nodes'
```

Structure the recap as a short per-node walkthrough (or a small table: node → inputs → output/result → status), then call out any failures and what you'll change. Reserve raw JSON for when the user explicitly asks for it.

**Locate results in the graph, don't just list them.** Pair the walkthrough with a `clay workflows diagram <workflowId>` render and overlay the run status onto it, so the user sees _where_ each result (or failure) came from — either annotate each node's label with a status marker or put a small "node → status" table beside the diagram. See `presenting.md` for the status markers and the annotation convention. Pull each node's status from `runs get --nodes` (or the per-step statuses from `runs steps`) to build the overlay.

## Example workflow

1. Start a test: `echo '{}' | clay workflows runs test wf_abc --inputs -`
2. Watch to completion: `clay workflows runs get wfr_xyz --wait | jq -r '.status'`
3. Inspect failures: `clay workflows runs steps wf_abc wfr_xyz --status failed | jq '.data[].errors'`
4. Walk the user through the trace node-by-node (see "Tell the user what the run actually did" above), not as raw JSON.

## Testing & exploration before wiring a node

Use `clay workflows actions test` and `clay workflows code test` as documented in
the parent skill. After wiring, confirm the persisted config with
`clay workflows nodes get` or `graph get --mode full`.

For code with declared outputs, test against the schema you will save before wiring:

If `clay workflows code test --help` does not list `--output-schema`, use `nodes test`
after saving the node instead; an execution-only code test does not validate its output schema.

```bash
clay workflows code test --file handler.py --inputs sample.json --output-schema outputs.json \
  | jq -e '.isError != true and .outputSchemaValidated == true'
```

`outputs.json` contains the schema itself, without an `outputSchema` wrapper: either flat
fields such as `{"owner":{"type":"string","description":"Assigned owner"}}`, or, when the installed
CLI's `--output-schema` help mentions JSON Schema, the JSON Schema `nodes get` returns for an
existing node, passed through unchanged (older CLIs take only the flat map). Flat fields
are all required and non-null, so a successful Python return containing `{"owner":null}` fails
the schema test. JSON Schema keeps its own `required` list. Run time enforces type, required, number `minimum`/`maximum`, and array `minItems`/`maxItems`; string `format`, `enum`, `pattern`, `minLength`, `maxLength` and `additionalProperties` are stored but not enforced. Test representative missing-data and
non-qualifying inputs as well as the happy path. Choose the missing-value behavior deliberately;
do not substitute zero or a placeholder owner just to pass validation. After saving or changing
the schema, use `nodes test` to verify the persisted node and its mappings before a full run.

## Pro tips

- Prefer `runs get --wait` over a hand-rolled poll loop when watching a run.
- Pipe to `jq` for filtering: `clay workflows runs steps <workflowId> <runId> | jq '.data[] | select(.status=="failed")'`
- To save output for later analysis, capture `clay workflows runs get <runId> --verbose` with your file-writing tool.
- `--verbose` returns untruncated inputs/outputs; prefer it over reconstructing logs.
