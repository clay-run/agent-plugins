# Investigating run data with `clay workflows analysis`

Read-only investigation of workflow execution data. Requires run analysis to be
enabled for the workspace — a disabled workspace answers every subcommand with
`auth_forbidden` (exit 3); report that it isn't available rather than retrying.

## The five subcommands

Start broad, then drill in. Each subcommand's `--help` documents its full
input schema. Commands that only make sense for one workflow (`traffic`,
`steps`) take the workflow id as a required positional argument; commands that
also work workspace-wide (`aggregate`, `runs`, `search`) take it as an optional
`--workflow` flag, and omitting it widens the query to every workflow.

1. `clay workflows analysis traffic <workflowId>` — node-to-node flow: per-edge
   transition counts, per-node reach/failure/duration stats, and where runs
   ended. **Run this first** to understand flow shape, dead branches, and
   drop-off points.
2. `clay workflows analysis aggregate [--workflow <workflowId>] --input '{"groupBy":[...],...}'` — the
   workhorse. Grouped counts, failure counts, duration stats (avg +
   p50/p75/p90/p95/p99), and credits. Group by `node` or `error_message`
   (step level, requires `--workflow`), or by `workflow`, `status`, `trigger`,
   `snapshot_version`, `hour`, `day`, `week` (run level). Answers "which node
   fails most", "error breakdown", "failure rate over time", "which workflows
   are most expensive".
3. `clay workflows analysis runs [--workflow <workflowId>] --input '{...}'` — list runs with filters
   (status, trigger, version, time range) and keyset pagination. Failed runs
   include their error text.
4. `clay workflows analysis steps <workflowId> --input '{...}'` — real step
   executions with truncated inputs/outputs. Ground every claim in actual
   data: compare a node's configuration against what it really received and
   produced, or inspect failing steps directly.
5. `clay workflows analysis search "<query>" [--workflow <workflowId>]` — token search
   across all recorded run content (step inputs/outputs, node names, prompts,
   agent reasoning, tool results). Finds where a value, error phrase, or
   entity appeared; follow up on the returned run ids with `runs` or `steps`.

## Reading values across many runs

Don't loop `clay workflows runs get` once per run over many runs: it is slow and repeats
the full run payload each time. For a count or a filter over run content, ask for it
directly with `aggregate`, `search`, or `clay workflows runs query run`. For per-run
values across 20 or more runs, export them in one CSV with
`clay workflows runs export start <workflowId> [--status ...|--query ...] --wait 240 --output runs.csv`
(one row per run; `--node <nodeId>:<path>` for a field's full value, since node and input
columns hold short previews). If it is still active when `--wait` ends, resume with
`clay workflows runs export get <exportId> --wait 240 --output runs.csv`. An export takes a
while to start, so for fewer runs read each with `runs get`.

## Version scoping

Every edit to a workflow creates a new immutable snapshot, and each run pins
the snapshot it started on — runs from before an edit reflect the OLD
configuration, not the current canvas. All subcommands default to the latest
version that has run (responses include `analyzedSnapshotId`). Keep that
default when diagnosing current behavior: findings from older snapshots may
describe bugs the user already fixed. Pass `"versionScope":"all"` or a pinned
`workflowSnapshotId` only for history, trends, or before/after comparisons —
and then say which version each finding belongs to.

To find a snapshot id: every response's `analyzedSnapshotId` names the version
it covered, `runs` rows carry each run's `workflowSnapshotId`, and `aggregate`
with `"groupBy":["snapshot_version"]` lists every version that has run with
counts. For the full version history, including versions that never ran, use
`clay workflows snapshots list <workflowId>`.

## Reporting findings

Numbers first: lead with the count, rate, or quoted error the data shows, then
the interpretation. Name the node and the affected run count for every
node-specific finding. When the host exposes canvas annotation tools
(`setAnalysisView`, `annotateWorkflow`, `clearAnnotations`), report node
findings through them and keep the chat message to a short summary.
