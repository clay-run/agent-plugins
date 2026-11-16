# Inspect Audiences enrichments without running them

Use the existing `workflows` commands for workflow-backed Data hub enrichments.
Do not create, convert, publish, resume, or run a workflow just to inspect its configuration.
A parity check compares configuration and assignments; it does not require customer record reads.

## Discover enrichments and assignments

```bash
clay workflows list --limit 200
clay workflows triggers list --segment-id <audienceId> --scope draft
clay workflows triggers list --segment-id <audienceId> --scope live
clay workflows triggers list --workflow-id <workflowId> --scope draft
clay workflows triggers list --workflow-id <workflowId> --scope live
```

Follow `workflows list` pagination until `cursor` is absent. Native enrichments have
`type: "audience_enrichment"`; retain unassigned ones in an inventory. Ordinary workflows
can also have Audiences triggers (including exports), so do not classify every attached
workflow as an enrichment without inspecting its graph and writeback.

Trigger `settings.segmentId` and `settings.entityType` are the native audience assignments;
`reactionSettings.workflowId` identifies the shared workflow. Multiple segment triggers can
point to the same workflow. After finding one segment's matches, list each workflow's triggers
to see all audiences affected by a shared configuration change. Do not clone a workflow merely
to inspect or reuse its configuration.

`--segment-id` matches explicit assignments. Also inspect `--segment-id ALL` for global
assignments of the relevant entity type. Trigger entity types are `CONTACT` / `ACCOUNT`.
For an entity-wide inventory, list all triggers once and filter those settings locally.
`audience_manual` and `isSystemGenerated` companions are not extra automatic assignments.

## Map the customer's settings to the right reader

| Setting                                                  | Command and evidence                                                                                                                                                                                                                                                                                                                                                        |
| -------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Name, native enrichment type, budget, published graph ID | `clay workflows get <workflowId>`                                                                                                                                                                                                                                                                                                                                           |
| Provider waterfall order                                 | `clay workflows graph get <workflowId> --mode full`: preserve `waterfallConfig.providers` order. For hand-built fallbacks, follow edges, conditions, and code rather than guessing from node order.                                                                                                                                                                         |
| Provider input mappings                                  | Full graph's tool `inputMappingConfig` and native waterfall input configuration. Use `clay workflows nodes get <workflowId> <nodeId>` for a focused read; follow the `workflows` skill's `data-passing.md`.                                                                                                                                                                 |
| Audiences output field mappings                          | Full graph's `upsert-audiences-record` writeback: `recordFields\|selectedRecordFields` and `recordFields\|<fieldId>`. Resolve destination IDs with `clay audiences fields list --entity-type people` (or `companies`).                                                                                                                                                      |
| Fill-only / overwrite rules                              | Writeback `recordFields\|writeMode\|<fieldId>`: `write_if_empty`, `always_write`, or `always_write_including_blanks`. Also inspect upstream conditions, formulas, and provider skip rules. Preventing a provider call and preventing a write are different behaviors; do not flatten them into one boolean. Follow `workflows/audiences.md` for explicit-clear limitations. |
| Enabled status and auto-enrichment                       | `workflows triggers list --workflow-id <id> --scope live`: `status: live` vs `paused`; `audience_segment` is membership-driven automation. An unpublished draft is not enabled automation. Status does not prove a particular run succeeded or is currently running.                                                                                                        |
| Schedules                                                | Trigger list's `settings.scheduleConfig`, `skipWhileRunsActive`, and `batchProcessing` for `audience_scheduled`. Read both scopes; a draft schedule is not necessarily the schedule currently firing.                                                                                                                                                                       |
| Input record schema                                      | `clay workflows triggers get <triggerId>` returns the editable trigger configuration and `outputSchema`; trigger list omits schemas to keep assignment reads small.                                                                                                                                                                                                         |
| Shared credit budget                                     | `workflows get` returns `budget.id` and `budget.name`; match the ID in `clay budgets list` for accessible `creditLimit`, `currentBalance`, `resetPeriod`, and `nextResetAt`.                                                                                                                                                                                                |

If write rules are absent or encoded in arbitrary code, report the unresolved behavior rather
than assuming fill-only or overwrite semantics.

Missing budget details do not mean unlimited spending. `budgets list` includes only accessible
budgets; a workflow may spend from one absent from that list. Native `audience_enrichment`
workflows use the workspace's Audiences budget, which `workflows update --budget-id` cannot
change. Shared budgets and per-resource credit caps are different controls; do not claim
per-enrichment cap parity from shared budget metadata alone.

## Compare draft and published configuration

The full graph command reads the authoring graph. Read `publishedSnapshotId` from
`workflows get`, then use:

```bash
clay workflows snapshots get <workflowId> <snapshotId>
```

Null means no workflow-level publication is recorded; omitted means the server did not
supply it. Do not substitute the newest snapshot or highest version number: snapshots also
capture edits, and a restored older version can be current. A trigger with a concrete
`reactionSettings.snapshotId` can pin a different graph; inspect that snapshot too.
`liveVersionId` is a trigger-version ID, not a workflow-snapshot ID.

Trigger list defaults to `--scope draft`. `--scope live` overlays published settings, retains
published paused assignments, and excludes draft-only triggers. It also omits unpublished
legacy heads whose published settings cannot be reconstructed; flag that limitation rather
than claiming a complete published parity check. Multiple CLI calls are not an atomic snapshot.

## Edits and execution are separate

For authorized configuration edits, use the existing workflow skill and commands:
`nodes update` for provider order/mappings/conditions, and `triggers create/update/delete`
for assignments and schedules. A trigger's audience identity cannot be changed in place;
create the new segment assignment. Read back the draft and show changes affecting every
attached audience before publishing. `triggers get` returns a different, flat editing shape
from trigger list; never post a list item wholesale as an update payload.

Publishing and resuming can activate automation. `workflows triggers update` with status
`paused` or `live` is an explicit pause/resume operation; it cannot activate a draft trigger.
For explicitly authorized execution/backfill, follow `workflows/testing.md` and the cost policy:
`workflows runs test <workflowId> --audience-segment <segmentId> --limit <n>` performs real work,
not a read-only preview. Do not run it as part of a parity check.

## Legacy table-backed enrichments

A bulk-enrichment table is not a workflow. When a customer identifies one, existing
`tables get` and `tables columns get` can inspect its table/column configuration, but workflow
trigger assignments do not describe its native audience bindings or source schedules.
Do not claim full Data hub parity for legacy tables from those commands, or silently migrate
one. Report that remaining gap and separate an explicitly requested migration from inspection.
