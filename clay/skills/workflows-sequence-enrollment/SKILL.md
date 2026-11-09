---
name: workflows-sequence-enrollment
description: Enrol Audiences people into a Clay sequence (formerly campaign) from a workflow step, using the "Enroll in sequence" action (`enroll-lead-in-sequence`). Use when a workflow should start emailing the people it just processed.
---

# Enrolling people in a sequence from a workflow

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

If the action is absent from `clay workflows actions list`, this workspace does not have it — say so
rather than trying to work around it.

How the **Enroll in sequence** action works as a workflow step. `clay workflows actions list`
still names it **Enroll in campaign**; the workflow canvas shows **Enroll in sequence**. For the
workflow mechanics this builds on (node creation, input mapping, `$.result.*` output paths), use
the `/workflows` skill and its `data-passing.md`.

Everything else about sequences — reading them, writing their copy, analytics, variants — lives
behind `clay sequences`, which is hidden in some products. Run `clay sequences --help` before
offering any of it, and point the user at the Sequencer UI when it is absent.

One run of this step enrols **one** Audiences person into **one** sequence. It confirms enrollment,
not delivery: the email provider owns pacing from there.

**A successful run sends a real email.** Get the user's explicit confirmation before publishing or
test-running a workflow that contains this step.

## Attaching the action

- `actionKey: "enroll-lead-in-sequence"`
- `actionPackageId: "b1ab3d5d-b0db-4b30-9251-3f32d8b103c1"`

Two inputs, and they come from completely different places:

| Parameter    | Mapping       | Where the value comes from                      |
| ------------ | ------------- | ----------------------------------------------- |
| `campaignId` | `static` only | `clay workflows actions dynamic-fields` (below) |
| `entityId`   | `reference`   | an upstream Audiences step's record id (below)  |

Outputs, all under `$.result`: `enrollmentStatus` (`"enrolled"` or `"already_enrolled"` — both are
successes), `campaignId`, `entityId`, `email`, and `entityResolution` (`"provided"`, `"matched"`,
or `"created"`). Only the first four are declared output parameters, so `entityResolution` is in
the run result but never in `clay workflows actions schema` or a token picker.

## `campaignId` must be a static value

The sequence is a fixed choice, not per-run data. A `reference`, `item`, `llm`, or `map` mapping
is **rejected** with `inputMappingConfig key "campaignId" must be a static value`. Resolve a real
id first:

```bash
clay workflows actions dynamic-fields b1ab3d5d-b0db-4b30-9251-3f32d8b103c1 \
  enroll-lead-in-sequence campaignId --type select
```

That returns only sequences that are **active** and take their leads from a workflow, so its
output is the only safe source for this value. Do **not** pick an id out of `clay sequences list`:
most sequences there draw leads from an audience instead, and pointing this step at one fails
every run with `campaign_not_workflow`.

Two outcomes are blocking, not retryable — report them to the user rather than trying again:

- `Couldn't load campaigns. Try again.` — the lookup itself failed.
- `No live campaigns take their leads from a workflow. Launch one to enroll.` — the workspace has
  no eligible sequence, and this step cannot be configured at all until it does. Launching is not
  something any skill can do; the user has to do it in the Sequencer UI.

## `entityId` is an Audiences record id

There are three supported ways to get one, and they answer different questions.

**Per-run (the normal case): take it from an upstream Audiences step.** Both
`upsert-audiences-record` and `update-audiences-record` return the record they touched as
`entityId`, so put one of them ahead of this step and wire its output through. `/workflows`'s
`audiences.md` covers configuring the upsert itself.

```json
{
  "inputSchema": {
    "type": "object",
    "properties": {
      "record_id": {
        "type": "string",
        "sourceNodeId": "wfn_upsert",
        "sourcePath": "$.result.entityId"
      }
    }
  },
  "tools": [
    {
      "toolType": "clay_action",
      "actionKey": "enroll-lead-in-sequence",
      "actionPackageId": "b1ab3d5d-b0db-4b30-9251-3f32d8b103c1",
      "inputMappingConfig": {
        "campaignId": { "type": "static", "value": "<id from dynamic-fields>" },
        "entityId": { "type": "reference", "expression": "{{record_id}}" }
      }
    }
  ]
}
```

`sourcePath` must be `$.result.entityId`. `$.result` on its own passes the whole output object and
fails with `invalid_input` — an enrich step's outputs sit under `result`, per `/workflows`'s
`data-passing.md`.

**Looking a record up instead of writing one.** **Look up in Audiences** (`lookup-in-audiences`)
also carries the id, at `$.result.records[0].fields.id`. Use it when the person is already in
Audiences and the workflow has no reason to write to them. Three differences from the upsert route,
all of which bite:

- It declares **no output schema**, so `clay workflows actions schema` returns an empty
  `outputParameters` and there is no field-level token to pick. Run the action once and read the
  path off `.result` before wiring it — see `/workflows`'s `data-passing.md`.
- It returns a **list** capped by `limit`, so you must index `records[0]`. A lookup that matches
  nothing returns an empty array, and the enrol step then fails `invalid_input`.
- It cannot create anyone. If the workflow might be seeing a new person, use the upsert route —
  that is the difference that decides between them.

**A fixed record (testing, or a workflow that always targets the same person):**
`clay audiences records search-ids --entity-type people …` returns matching ids; map one as a
`static` value. This is wrong for a workflow meant to enrol whoever it just processed.

## Before it will run

- The sequence must be **active**. A paused or draft sequence rejects every enrollment.
- The person needs an email address on their record, plus any field the sequence copy marks
  required.

A contact and an account created by the _same_ upstream upsert are not yet linked in a way this
step can read, so company tokens in the copy render blank on that first enrollment. Enrich or
associate the account in an earlier run if the copy depends on it.

## Failure codes

Every failure carries one of these codes, and the message alongside it is safe to relay verbatim.
This is the whole set — a code outside it means the step failed before enrollment was attempted.

| Code                                 | Means                                                           |
| ------------------------------------ | --------------------------------------------------------------- |
| `contact_not_found`                  | no such record, or it belongs to another workspace / is deleted |
| `ambiguous_identity`                 | the record could not be resolved to a single person             |
| `canonical_email_mismatch`           | the record has no usable email address                          |
| `missing_required_fields`            | the record is missing data the sequence copy requires           |
| `campaign_not_active`                | the sequence is not active                                      |
| `campaign_not_workflow`              | that sequence takes its leads from an audience, not a workflow  |
| `campaign_not_found`                 | the sequence no longer exists                                   |
| `lead_in_cooldown`                   | enrolled in a related sequence too recently                     |
| `cooldown_check_unavailable`         | the cooldown could not be checked                               |
| `insufficient_credits`               | the workspace is out of credits for this enrollment             |
| `snippet_generation_failed`          | the sequence's AI snippets could not be generated               |
| `provider_rejected`                  | the email provider refused this person (blocklist, unsubscribe) |
| `invalid_input`                      | usually a `sourcePath` that passed an object instead of the id  |
| `feature_disabled`                   | enrollment from workflows is off for this workspace             |
| `provider_result_indeterminate`      | the provider's answer could not be confirmed                    |
| `enrollment_persistence_unavailable` | the enrollment result could not be recorded                     |
| `unexpected_error`                   | an unhandled failure                                            |

`provider_result_indeterminate` and `enrollment_persistence_unavailable` mean the person **may
already be enrolled**. Re-running the step can send a second email, so report them and let the user
check the sequence rather than retrying.

## Testing a step without enrolling anyone

`clay sequences variants send-test` cannot preview a workflow-fed sequence — it looks for a
preview lead in an audience, and these sequences have none. Sending a test render of the copy is
only possible from the step's own panel in the app today. Say so rather than sending a real
enrollment to check the copy.
