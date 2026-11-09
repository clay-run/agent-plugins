# Publishing workflows (draft vs live)

Editing a workflow updates the **draft**. **Publishing** is a separate step that
makes that draft the **live** version automation runs. Until the user publishes,
live audience / schedule / webhook (etc.) automation does not pick up your edits.

When the user wants automation to go live (or to ship draft changes after a prior
publish), run `clay workflows publish <workflowId>`. Do not claim that node edits,
a test run, or `snapshots restore` published anything.

Speak to the user in **draft / live / publish** terms for the workflow as a
whole, and don't explain internal mechanics (how triggers bind to snapshots,
sentinel ids, etc.). A trigger you create or edit stays inert until the user
publishes — publishing is what takes triggers live. There is no per-trigger
"set live" action, so never say you "set a trigger live" or that a trigger you
just added is already live.

Users **can** pause and resume an individual trigger with
`clay workflows triggers update <triggerId> --input '{"status":"paused"}'` or
`{"status":"live"}`. A status change must be sent alone (not alongside other
fields). Resuming a paused trigger returns it to live; it is not a publish, and
going live for the first time is only ever through publishing.

A trigger's `dataSource` is also outside draft vs live. It configures the source that feeds the
trigger, which is not part of the workflow's versions, so changing it with `triggers update`
applies **immediately**, with no publish: a live trigger's next run (scheduled or requested)
uses the new source settings. Tell the user that, and confirm before changing the `dataSource`
of a live trigger.

## Concepts

| Concept                    | Meaning                                                                                                                                                             |
| -------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Draft**                  | The current editable graph (nodes, edges, prompts, tools). A never-published workflow is still a first draft.                                                       |
| **Draft-history snapshot** | An automatic freeze of the graph (after a graph-mutating edit, at run start). Undo/history only — not a release. See `/workflows-snapshots`.                        |
| **Publish**                | Ship the current draft as a numbered live version, activating its triggers. A trigger the user paused in the UI stays paused (publish does not silently resume it). |
| **Live**                   | The published version automation runs. After the first publish, further draft edits do **not** change live automation until the user publishes again.               |

Draft-history snapshots and published versions share the same snapshot store;
publish marks a snapshot as a numbered release. Re-publishing an unchanged draft
keeps the same version.

Publishing is the only way a trigger goes live for the first time: there is no
per-trigger "set live" step. Pausing and resuming an existing trigger is a
separate per-trigger action (`triggers update` with `status`) and does not
publish a new workflow version.

## Restore is not publish

`clay workflows snapshots restore` (see `/workflows-snapshots`) replaces the
**draft** only. It does **not** change what is live. Undoing an edit does not roll
back live automation — the user must publish again if they want live automation to
match the restored draft.

## What you should do

1. Build against the draft (`clay workflows nodes …`, `graph validate`/`format`). To verify **unpublished**
   edits, use a plain / manual `clay workflows runs test`, or `--trigger` on a CSV or audience
   segment trigger — those exercise the current draft. A Find leads trigger cannot: its source
   always runs the published version (see below).
2. After a successful draft e2e test, if the user wants automation to run this graph,
   run `clay workflows publish <workflowId>`. Use `--name` only to label the
   published version, not to rename the workflow.
3. If they edit a workflow that is already live, remind them that draft changes
   stay draft-only until they publish again — and that live automation, including
   Find leads runs, still runs the previous live version until then.
4. Never invent a publish API call or imply that restore/undo shipped a release.

## Which runs exercise draft vs live

| How you start the run                                                            | What graph it uses                                                                                                 |
| -------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------ |
| Plain / manual `clay workflows runs test` (optional `--inputs`)                  | **Current draft**                                                                                                  |
| `clay workflows runs test --audience-segment …`, or `--trigger` on a CSV trigger | **Current draft** — no publish needed (the segment companion is created live; a CSV trigger is live from creation) |
| `clay workflows runs test --trigger …` on an audience segment trigger            | **Current draft** — but the segment trigger itself must be live, so publish first (or use `--audience-segment`)    |
| Any of the above with `--live`                                                   | **Live** version — fails if never published                                                                        |
| `clay workflows runs test --trigger …` on a Find leads trigger                   | **Live** version, with or without `--live` — the source hands records to the published version only                |
| Live audience / schedule / webhook / Find leads automation                       | **Live** version — not unpublished draft edits                                                                     |

When checking whether draft changes work, use a manual test run or `--trigger` on a CSV or
segment trigger. Use `--live` or real automation to exercise the published path. A Find leads
trigger only ever runs the published version: to check a draft edit against one of its records,
run `clay workflows nodes test <workflowId> <nodeId> --source-run <runId>` with a run the live
source already produced, or publish.
