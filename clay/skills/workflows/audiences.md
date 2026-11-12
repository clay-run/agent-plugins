# Audiences in workflows

How Audiences shows up while building a workflow: writing records with
`upsert-audiences-record`, and triggering a workflow off an audience.

For everything else about Audiences — creating and editing audiences (saved
segments), managing field definitions, reading and counting records, and writing
filter ASTs — use the **`audiences` skill**. Do not rediscover the `clay audiences`
CLI here.

**Inspect audiences with the audience operations; write records with the action.**
The audience operations inspect records and manage segments and field definitions;
they do not write field values onto records. Any workflow step that populates
people or companies uses the action below. For access instructions, read the
`clay` entry skill.

## Decide whether to write back

Inspect the whole workflow and prior user instructions before adding an
`upsert-audiences-record` node. Follow records from their source through enrichment to the
intended destination; the trigger type or the last node alone does not establish intent.

- **Audiences export workflows:** when building or editing a workflow whose source is an
  Audiences-related trigger (for example, `audience_segment` or `audience_scheduled`) and
  whose destination is an export enrichment node, do not add Write to Audiences
  (`upsert-audiences-record`). This includes the scheduled segment trigger created by the
  Audiences export UI. The records already come from Audiences; writing them back adds a
  redundant no-op loop. Apply this exception before the default writeback rules below.
  The intended path is audience trigger → export, with any requested processing in between.
- **Existing Audiences records:** write enrichment, qualification, and scoring results back
  to those records without asking whether to save. Reuse and extend an existing writeback
  node when possible. Resolve any field choices below before configuring those mappings.
- **New records from outside Audiences**, such as search results or a CSV upload: recommend
  saving the results to Audiences and ask before adding writeback. If the user already asked
  to save them there, proceed without asking again.
- **Explicit destination or no-save instructions:** follow them. Do not add Audiences as an
  extra destination or repeatedly recommend it after the user declines.

For `audience_enrichment` workflows, use `/workflows-audience-enrichment` to ensure the final
writeback. Draft construction does not authorize execution or publishing; preview-only work
must not execute writeback.

## The backfill shape: audience → enrich → upsert back

This is the standard answer when a field the user wants is missing or sparse on
their records, and the most common reason to build a workflow over Audiences:

1. **Save an audience of the records that need the field** — an `Empty` filter on
   it, via `clay audiences create`. That audience is the work queue, and it drains
   itself as records get filled.
2. **Trigger the workflow on that audience** (`audience_segment`, below).
3. **Enrich** in a tool node.
4. **Write the result back** with `upsert-audiences-record`, looking the record up
   by `email` / `linkedin_url` (people) or `domain` (companies).

Lead with the count from `clay audiences records search-count` so the user can
see the size. You may build the reversible draft incrementally while details are still
being refined. Run a backfill only within the authorized scope and get confirmation before
publishing the workflow. Follow the shared cost policy in `workflows-discover-actions/cost-and-budget.md` for cost disclosure
and significant-spend confirmation.

Before proposing it, confirm the data really is missing: read the existing field
first (see the `audiences` skill's `answering-data-questions.md`). A workflow that
re-enriches data the workspace already has spends credits for nothing.

## The ingest shape: search → upsert workflow → routine

This file owns **building** the upsert workflow. The **`routines` skill** owns
**running** it in bulk over Search results.

Use this when the user wants net-new people or companies from Clay's GTM database
**kept in Audiences** — not just enriched and discarded:

1. **Use the `searches` skill** to find the records and learn real field names
   (`email`, `linkedin_url`, `domain`, etc.) from Search results — do not invent
   JSON paths.
2. **Build a workflow that upserts one record per run.** Routine items are the
   batch. Trigger must be `manual` so the routine has an input schema and can
   run; do not use `webhook` or `audience_segment`.
3. **Add a tool node** with `upsert-audiences-record` (see below for
   `actionKey` / `actionPackageId`). Bind lookup keys from the search item;
   record fields from `clay audiences fields list`.
4. **Expose it as a routine:**
   `clay routines create workflow <workflowId> --name "…"`. Then hand off to the
   **`routines` skill** to run it in bulk over Search results.
5. **If they then want ongoing automation**, choose what should start each run:
   segment membership, a signal event, or a schedule. See `trigger-selection.md`;
   use the backfill shape above when processing audience members is the intent.

Do not use list mode or `clay workflows runs test` as the bulk upload path.

## Triggering a workflow off an audience

An `audience_segment` trigger's `segmentId` is the audience id from
`clay audiences list` or `clay audiences create`. Its `entityType` is `CONTACT` /
`ACCOUNT` — **not** the `people` / `companies` vocabulary the CLI flags use.

To backfill existing members through the workflow, see `testing.md`
(`clay workflows runs test <workflowId> --audience-segment <segmentId> --limit N`).

## upsert-audiences-record

This is the way to update Audiences records. Creates or updates a contact or account via `inputMappingConfig`. The config is a flat object with pipe-namespaced keys (`<group>|<fieldId>`) — never dot-notation, never nested.

When attaching this action to a tool node, use:

- `actionKey: "upsert-audiences-record"`
- `actionPackageId: "b1ab3d5d-b0db-4b30-9251-3f32d8b103c1"`

### Lookup vs record fields

- **Lookup fields** identify the audience record to update. Contacts support `id`, `email`, `linkedin_url`, `phone`, and `external_source_id`; accounts support `id`, `domain`, `linkedin_url`, `clay_company_id`, and `external_source_id`. Bind each selected key under `lookupFields|<id>`. The Audiences record `id` is checked first; other selected keys are tried in their selected order. Matching only on `id` updates existing records. To create a record when no match exists, include another lookup key with a valid value.
- **Record fields** are the data written onto the matched (or newly created) record. These are workspace-defined and vary per workspace; call `clay audiences fields list` with `--entity-type people` or `--entity-type companies` to discover the available ids.

For an `audience_enrichment` trigger, preserve its existing record identity by following the
`workflows-audience-enrichment` skill's `lookupFields|id` binding guidance.

### Required keys

- `entityType` (static) — `"ACCOUNT"` or `"CONTACT"`.
- `lookupFields|selectedLookupFields` (static array) — lookup-key field ids.
- `lookupFields|<id>` for every id above — value to match on.
- `recordFields|selectedRecordFields` (static array) — fields to write.
- `recordFields|<id>` for every id above — value to write.
- To explicitly clear a field, set `recordFields|writeMode|<id>` to the static value `always_write_including_blanks` and map `recordFields|<id>` to an upstream value; `null`, `""`, or a missing value clears it only when explicit Audiences clears are enabled for the workspace (`enable-audiences-clear-field-command`). `0` and `false` remain ordinary values. See `data-passing.md` for mapping and verification guidance.

Every id in a `selected*` array MUST have a matching `<group>|<id>` binding, or the action returns `ERROR_BAD_REQUEST`.

A missing value means a selected, mapped source field has no value on that record. Leaving a destination field unselected or unmapped does not request a clear.

### Verify a writeback

If explicit-clear availability is unknown, do not promise a clear. After execution, read the record
back before reporting success; a successful step alone does not prove the field cleared.

A workflow writeback can also change Clay-maintained system fields: `updated_at` moves,
`external_source_sync_status_v3` gains an entry for the workflow, and `workflows` gains the
workflow id the first time that workflow writes the record. These changes are expected and are
not overwrites. When you check that a writeback
preserved existing data, compare `clay audiences records get` output before and after on the
fields you did not select for writing, and leave the system fields out of that comparison.
`clay audiences fields list --entity-type <people|companies> --include-system` marks every system
field with `isSystemField`.

### Search writeback defaults

On the first configuration of a V2 Write to Audiences node downstream of search triggers,
the server adds matching default search fields before saving, alongside your explicit mappings.
Set `entityType` to `ACCOUNT` for companies or `CONTACT` for people; the server chooses the
corresponding defaults using the same matching rules as the field mapping editor. Defaults are
added only for existing Audience fields with one matching upstream search field. For example,
"Company name" can map to `org_name` for `ACCOUNT`, and "Full name" to `name` for `CONTACT`.

Connect its incoming edges before configuring mappings, or include `incomingEdges` in that same
node edit. Read the node after saving to discover the exact mappings that were added, and retain
them when adding more fields. Explicit sources and write rules take precedence over defaults.
Saved selections, including an explicitly empty selection, are not supplemented with defaults
on later edits. If the Audience field catalog is unavailable, the save keeps your explicit
mappings and skips defaults. These defaults do not apply to enrichment of existing Audiences records.

### Discover real field IDs

Run `clay audiences fields list` with `--entity-type people` or `--entity-type companies` first — schema ids and English names often differ (account "company name" is `org_name`). For planning-only requests that prohibit workspace queries, use the supplied catalog and defer ID discovery until editing is authorized. It returns the workspace's record field catalog, not the lookup keys listed above.

Match each upstream output by meaning and data type, using the workflow context:

- When one existing field clearly fits, map to its real ID without asking whether to use it
  or create a new field. For a requested update, existing values are not a reason to reopen
  that choice, create a duplicate field, or limit the workflow to filling blanks. Follow the
  user's update intent and preserve unrelated fields.
- When several fields plausibly fit, ask an explicit question naming those fields and the
  option to create a new field, including in a planning-only reply. Saying you would ask or
  listing the ambiguity is not a question. Wait for the user's choice before configuring
  that mapping.
- When no existing field clearly fits, create a suitable field without asking permission,
  as described below. An incompatible type or meaning is not a plausible match: a boolean
  verdict needs a boolean field, not an existing text field used for human explanations.

Reuse field choices already made. Do not
force a mapping into an unrelated field, change an existing field's type, or silently drop an
output to avoid asking. Continue independent draft work while a field decision is pending.

### Create missing fields

**You can create fields through the CLI.** Use `clay audiences fields create` when a workflow
output needs a new field. Choose a descriptive name and matching data type, then map the output
using the returned field ID. Creating needed fields requires no separate user approval; tell
the user what you created. Honor explicit instructions not to create fields or to plan only.
Audiences fields are distinct from table columns; limitations on adding table columns do not
apply to `clay audiences fields create`.
Do not claim field creation is unsupported or hand it back to the user without an actual tool
error establishing a blocker. Use the `audiences` skill for command details.

For a planning-only request, state the new field's name and type and the write-to-audiences
mapping you will create with the audience operations, without executing anything. Do not add hypothetical
access limitations or a manual handoff. Carry forward agreed field names and mappings; ask only
about unresolved choices needed for the requested work, not speculative gates, extra outputs,
or testing the user has excluded.

For example, a boolean qualification output with only a human-written text field available
calls for a new boolean field and a write-to-audiences node mapping to it. State that plan
directly. If the user already chose a name and mapping, retain them without reopening the
decision. Waiting to execute a planning-only request does not require asking again whether
the field should exist.

### Worked example — account upsert

```json
{
  "entityType": { "type": "static", "value": "ACCOUNT" },
  "lookupFields|selectedLookupFields": {
    "type": "static",
    "value": ["domain"]
  },
  "lookupFields|domain": { "type": "reference", "expression": "{{domain}}" },
  "recordFields|selectedRecordFields": {
    "type": "static",
    "value": ["org_name", "domain"]
  },
  "recordFields|org_name": {
    "type": "reference",
    "expression": "{{org_name}}"
  },
  "recordFields|domain": { "type": "reference", "expression": "{{domain}}" }
}
```
