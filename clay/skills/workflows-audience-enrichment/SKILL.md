---
name: workflows-audience-enrichment
description: Clay workflows — build enrichment steps and map their results back to Audiences in an existing audience enrichment workflow. Use while editing an audience enrichment workflow or migrating an Audience-backed bulk enrichment table into a workflow.
allowed-tools: Bash(clay *), Bash(jq *), Read
---

# Build an audience enrichment workflow

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

Use this skill for an existing `audience_enrichment` workflow or an explicitly requested
Audience-backed bulk enrichment migration. It owns the
workflow-specific sequence: build enrichment steps, ensure the shared final Audiences writeback,
and map enrichment results onto audience fields.

Read the complete `workflows` and `audiences` skills first. Read `/workflows-discover-actions` when
choosing provider actions, and read the `workflows` skill's `audiences.md` before mapping the
writeback.

## Verify the workflow type

Start every task with:

```bash
clay workflows get <workflowId>
```

Continue when `.type` is exactly `audience_enrichment`. For a regular workflow (null or
absent type), convert only as part of an authorized Audience bulk enrichment migration,
using the procedure below. For other tasks or workflow types, return to `/workflows`.
Never convert or reclassify a workflow implicitly.

## Plan the enrichment

Read the full graph and identify the audience trigger, existing enrichment steps, and current
writeback node. Resolve the following from the workflow and user instructions, asking only
where a choice remains:

- which audience fields should be populated
- whether the workflow should enrich people or companies
- whether the requested fields are actually missing or sparse
- the action or function to use when the workspace catalog offers consequential alternatives
- the audience size before testing or publishing

Use the `audiences` skill to inspect field fill rates and count matching records. Prefer direct
enrichment actions for provider data, Clay functions for reusable workspace logic, agents for
unstructured research or classification, conditionals for eligibility and fallbacks, and code for
deterministic transformations.

Map unambiguous existing fields without asking whether to use them or create new ones. A request
to update a field does not need another confirmation because it may already have values; do not
add a fill-blanks-only restriction unless requested. For ambiguous mappings, offer plausible fields
and a new-field option. Create needed fields without asking permission, following the
`workflows` skill's `audiences.md`. Reuse field choices already made.

Present a short plan and get approval before editing the graph unless the user already authorized
the edits. Get separate approval before
publishing. Testing must be within the authorized scope; follow the shared policy in
`workflows-discover-actions/cost-and-budget.md` for cost disclosure and significant-spend confirmation.

## Build the enrichment path

### Migrating an Audience bulk enrichment table

If the destination is a regular workflow, convert it with
`clay workflows update <workflowId> --type audience_enrichment` once the user has
authorized the migration. Then create draft Audience triggers matching the table's source
segments and entity type. Conversion alone does not create triggers or run enrichment.

Read the table's full column settings and the destination trigger's output schema before
creating nodes. Preserve the table's enrichment behavior while using the existing audience
trigger as the source of the original record ID and fields:

- Replace a lookup that only reloads the triggering Audience record, and columns that only
  extract its fields, with direct trigger bindings. Keep formulas that transform those fields.
- Only carry over a related-company lookup when a downstream enrichment or writeback uses
  its output and that value is not already available from the trigger. Preserve user lookups
  that retrieve different records or implement additional filtering.
- Pin each required value on the consuming code or tool node using an `inputSchema` property
  with the trigger's `sourceNodeId` and the exact `sourcePath` from its output schema. For
  example, a trigger exposing `fields.Name` supplies `sourcePath: "$.fields.Name"`; this may
  differ from the Audience field ID `name`. A nested expression like `{{fields.id}}` does not
  replace an explicit upstream binding. Read `/workflows`'s `data-passing.md` for the writable shape.
- In code, read the pinned input by its property name with `context.get_input`. On the final
  writeback, pin the original record ID from the trigger and the transformed value from the
  enrichment node, then reference those input names in `inputMappingConfig`. Read each node
  back and confirm its source bindings survived before running.

Use the shared writeback procedure below for the table's final Audience update. Do not copy
the table's source-record lookup or legacy writeback action into a separate update path.

Build from the existing audience trigger. Preserve the trigger and any existing
`upsert-audiences-record` node.

Use `clay workflows actions list` and `clay workflows actions schema` to choose and configure each
enrichment. Never guess action input names, output paths, credentials, or provider availability.
Put cheap eligibility checks before paid actions. When an enrichment can miss, use the user's
chosen fallback or conditional path rather than silently writing a blank value.

Use the general `workflows` skill for node creation, insertion, data passing, and branch wiring.
Do not manually create or reconnect the final audience writeback while building intermediate
steps.

## Ensure and configure the final writeback

After the enrichment graph is structurally complete, run:

```bash
clay workflows ensure-audience-writeback <workflowId>
```

This command calls the same server-side helper as the audience enrichment editor. It creates or
reuses exactly one `upsert-audiences-record` node, validates its entity type, and reconnects every
eligible terminal route. Do not reproduce that topology change with manual node or edge edits.

Read the returned node before updating it. Preserve its tool identity and static `entityType`, then
configure its `inputMappingConfig` with `clay workflows nodes update` using the writable shape from
`clay workflows nodes get`.

Discover destination fields with:

```bash
clay audiences fields list --entity-type people
clay audiences fields list --entity-type companies
```

Follow the `workflows` skill's `audiences.md` for the complete mapping shape. In particular:

- set `lookupFields|selectedLookupFields` to the static array `["id"]`
- bind `lookupFields|id` to the audience trigger record id: use `$.fields.id` when the trigger
  output schema contains a `fields` object, otherwise use `$.id`; inspect the trigger output schema
  and never guess the path
- do not replace the record-id lookup with email, LinkedIn URL, phone, or domain; those aliases are
  for generic or net-new audience upserts where an existing audience record id is unavailable
- include every destination id in `recordFields|selectedRecordFields` and provide its matching
  `recordFields|<id>` binding
- when the user wants a field cleared, set
  `recordFields|writeMode|<id>` to the static value `always_write_including_blanks` and map that
  field to an upstream value; `null`, `""`, or a missing value clears it only when explicit Audiences clears
  are enabled for the workspace (`enable-audiences-clear-field-command`)
- bind enrichment outputs from their declared `$.result.<outputPath>` paths; never invent paths

Read the writeback node again after updating it and confirm the mappings persisted. If explicit-clear
availability is unknown, do not promise a clear. After execution, read the record back before reporting
success; a successful step alone does not prove the field cleared.

## Validate, test, and publish

Finish an audience enrichment workflow in this order:

1. Run `clay workflows ensure-audience-writeback <workflowId>`, read the returned node, and confirm
   its mappings persisted.
2. Validate the graph with the available workflow tools and show the resulting diagram.
3. Resolve the segment id from the workflow's existing `audience_segment` trigger. Do not search
   for audience entities or records to decide what to publish or run. If the workflow has no
   `audience_segment` trigger, stop this completion sequence and use the general `workflows`
   testing guidance; do not alter its triggers.
4. Explain the likely credit exposure and get approval for a credit-consuming test.
5. Test 10 segment records from the current draft by default:

   ```bash
   clay workflows runs test <workflowId> --audience-segment <segmentId> --limit 10
   ```

   Use a different limit only when the user requests or approves it.

6. Wait for the run to finish. Inspect both the enrichment output and the final Audiences update.
   If mappings need correction, correct and validate them, then return to step 4 and get renewed
   approval before another credit-consuming test.
7. Get separate approval, then publish the tested draft with
   `clay workflows publish <workflowId>`.

When the user asks to **publish and run** an `audience_segment` workflow, publish first, then test 10
records from the version just published with `--audience-segment <segmentId> --limit 10 --live`.
Do not substitute an entity lookup, a record search, or a plain manual run for the requested segment
run. Later edits remain draft-only until the workflow is published again.
