---
name: schedules
description: 'Clay agent schedules — recurring prompts the Clay agent runs on a cadence, each occurrence starting a fresh agent task. Use for any request to do something on a schedule or recurring cadence: a daily digest, a weekly report, checking or changing when a scheduled run happens next, pausing or deleting one.'
---

# Clay agent schedules

A schedule runs the Clay agent on a cadence. Each occurrence starts a **fresh
agent task** with the schedule's `prompt` as its first message, run as the
schedule's creator. Nothing carries over between occurrences — no conversation,
no working files — so a schedule prompt must stand alone: name the audience,
table, or workflow it works on explicitly, and say what the output should be.

## The commands

```bash
clay schedules create --input '{...}'      # create; starts active with nextRunAt computed
clay schedules list                        # the schedules you created, status, cadence, next run
clay schedules update <scheduleId> --input '{...}'  # partial update; also pause/resume via status
clay schedules delete <scheduleId>         # remove it and every run it produced
```

Read `clay schedules <subcommand> --help` for the exact input and output
shapes; they are the contract.

## Writing the prompt

The `prompt` is the entire brief every occurrence gets. Write it as exactly three
short sections, in this order:

- **Objective** — one sentence: the ongoing job this schedule exists to do.
- **Goal** — the measurable end state, and any hard limits (spend, volume). When the
  goal can be measured from workspace data, state it in those terms and name the
  measure — the audience id, filter, or activity types a run should count (see
  "Measuring the goal") — so a run can tell from the reading alone whether it is done.
- **Instructions** — a short numbered list of what one occurrence does, naming every
  audience, field, and workflow by id (a fresh task cannot infer them).

Write the Instructions for the **minimum work that makes progress toward the goal**,
not for finishing it in one run. When the Goal names a measure, the first step is
taking it; the reading then decides the rest — a goal at its target means skip that
work entirely, and a backlog means work a bounded batch of it (name the batch size),
report the remainder, and stop. The schedule is the loop; no single occurrence needs
to be.

Keep it brief — a few hundred words, well under the 4000-character cap. A prompt near
the cap is a smell that it has absorbed things that do not belong in it:

- Tool usage and CLI flag reference — the run reads the same skills you did.
- Cadence. Frequency, days, run time, time zone, and start and end dates live in
  `scheduleConfig` and are enforced from there alone, so a prompt that restates them is
  wrong the moment the two differ: "every Monday" on a daily cadence runs seven days a
  week, and every run believes it is Monday's. Time windows that describe the work —
  "leads since the last run", "last week's pipeline" — are not cadence and stay.
- Restated notification or credit policy. Rely on the shared cost policy in
  `workflows-discover-actions/cost-and-budget.md` rather than adding balance disclosures
  or repeated spending approvals to the schedule prompt.
- Contingency trees. A run that hits a blocker reports it and stops; the next
  occurrence retries. One line covers it.
- Preconditions on budget access. A schedule that runs a workflow runs it; do not make
  the run depend on finding the workflow's budget in `clay budgets list`. Budget limits
  are enforced when the workflow spends (see `workflows-discover-actions/cost-and-budget.md`).
- Report formatting specs. Say what facts the final reply must contain (the goal's
  current reading, what changed, what failed) and leave the prose to the run.

## The cadence

`scheduleConfig` is one of two recurrence kinds:

```json
{
  "recurrenceType": "simple",
  "value": {
    "periodUnit": "daily",
    "startDate": "2026-09-01T09:00:00",
    "timezone": "America/New_York"
  }
}
```

`periodUnit` is one of `daily`, `weekly`, `biweekly`, `monthly`, `quarterly`.

```json
{
  "recurrenceType": "custom",
  "value": {
    "customPeriodType": "weeks",
    "customPeriodInterval": 1,
    "timesOfDay": ["09:00"],
    "daysOfWeek": [1, 2, 3, 4, 5],
    "startDate": "2026-09-01T09:00:00",
    "timezone": "UTC"
  }
}
```

`customPeriodType` is `days`, `weeks`, or `months`. Each day filter is read by
exactly one of them — `daysOfWeek` (0–6, Sunday is 0) by `weeks`, `daysOfMonth`
(1–31) by `months` — and **ignored without error** by the others. So "weekdays
at 09:00" is `weeks` with `daysOfWeek`, not `days`: `days` with `daysOfWeek` is
accepted and then runs every day, weekends included.

**At most once a day.** The sub-daily `periodUnit` values (`minute`,
`fifteen-minutes`, `hourly`) and more than one `timesOfDay` entry are rejected
as a `validation_error`. Do not promise a user anything more frequent.

**At most 20 schedules per workspace.** Creating past the cap is a
`validation_error` naming the limit. Deleting a schedule frees its slot;
pausing does not free one.

## Before you create one

Read `clay schedules list` first. If one of the user's schedules already does roughly what this
one would, say so and ask whether they still want a second — duplicate names and overlapping
purposes are both allowed, so this is the user's call, not yours to skip.

Set `timezone` to the zone the user means. For a simple recurrence, write `startDate`
as local wall time without an offset, for example `2026-09-01T09:00:00` with
`America/New_York`. For a custom recurrence, write `timesOfDay` as local wall time in
`timezone`, never converted to UTC. For example, 9 AM in `America/New_York` is
`"09:00"` in `timesOfDay`.

Read the prompt for cadence and compare it with `scheduleConfig` — on `create`, and on any
`update` that touches the prompt. When they agree, remove the cadence sentence from the prompt
and proceed. When they disagree on any element — frequency, day, time, zone, or a date — ask the
user which one to keep before creating or updating anything, offering both as choices with the
instructions' cadence first, each spelled out ("Every Monday at 9:00 AM", "Every weekday at
9:00 AM") and each saying where it came from. Then put the chosen cadence in `scheduleConfig`
and take the cadence sentence out of the prompt, so the schedule says one thing.

## Measuring the goal

Nothing about a goal is stored on the schedule or shown in the Clay UI. Progress lives in
one place: each occurrence takes the reading the Goal section describes and states it in
plain text in its final reply. That makes the Goal section a promise — write a measure into
it only when the number will actually reflect the goal.

### Choosing the measure

1. **Restate the goal as a measurable question.** Decide the entity (people or companies)
   and what "done" looks like as data, then match it to the `clay audiences` command that
   answers it — none of these is a fallback for the others:
   - The goal is about **record state** — a field filled, a segment grown or drained
     ("enrich every founder", "200 accounts with a verified email") → a record count from
     `clay audiences records search-count`, as a coverage ratio when that is what the goal
     means ("860 of 1,200 enriched").
   - The goal is an **outcome that happens** — meetings booked, emails sent, calls made,
     replies received ("book 25 meetings this quarter") → `clay audiences activities summary`
     over the relevant activity types and window. Check its `--help` for the accepted
     `--activity-types` values.
   - The goal is about **buying signals firing** — job changes, funding news, intent →
     `clay audiences signals summary`.
2. **Confirm the data can answer it.** For record-state goals:
   `clay audiences fields list --entity-type <t>` — is there a field that will actually
   reflect the outcome, and does it get updated by the work this schedule does? For
   outcome goals: run `clay audiences activities summary` once over the target segment —
   a workspace with no activity data of that type cannot measure it. **If nothing will be
   accurate, stop here**: tell the user what you looked for and why it cannot be measured,
   then offer the closest alternative — a proxy field, a different measure, or an
   unmeasured goal. Never write in a measure you expect to read wrong or stay stale.
3. **Build and validate the query.** Compose the filter and run
   `clay audiences records search-count --filter '...'` — this validates the AST and returns
   the count in one call. A zero or implausible count is a signal to revise the filter, not
   to use it.
4. **Reuse or create the audience.** Prefer a fitting saved audience (`clay audiences list`);
   otherwise `clay audiences create`. Re-check with `search-count --audience-id`.
5. **Write the measure into the Goal section** by id — the audience id, the filter, or the
   segment id plus activity or signal types and window — so a fresh occurrence can re-take
   exactly the same reading without re-deriving it.
6. **Tell the user how progress will be measured** and what the number means, including the
   current reading, so an already-met or impossible goal surfaces immediately.

### Taking the reading during a run

A scheduled occurrence takes the Goal's reading before doing work and lets it shape the
occurrence: skip work the numbers show is already done, focus where they lag, and state the
reading in the final reply next to what changed and what failed. Use the command the Goal
names:

- A saved audience's count:
  `clay audiences records search-count --entity-type <people|companies> --audience-id <id>`.
- A coverage ratio: `search-count` rejects `--audience-id` and `--filter` together, so fetch
  the audience's own filter with `clay audiences get <audienceId>`, AND it with the Goal's
  condition in one `GroupOp`, and run `search-count --filter` with that. The audience count
  alone is the denominator.
- Activity volume: sum `activityCount` across the groups returned by
  `clay audiences activities summary --segment-id <audienceId> --activity-types <types> --since <window start>`.
- Signal volume: the same through `clay audiences signals summary --segment-id ...`.

A reading you cannot take — the audience returns `not_found` because it was archived, a
lookup fails — is a fact to report, not a blocker: do the occurrence's work without it and
say so in the reply. Readings are current-state only. When the schedule needs run-over-run
deltas, record each reading in the occurrence's scheduled-task memory file (your
scheduled-run instructions describe it) so later occurrences can compare; without workspace
memory, report the current value without a comparison rather than guessing one.

## Status

`status` on every schedule is its lifecycle — whether it will run again — and
is one of three values:

- `active` — running on its cadence.
- `paused` — the user paused it, or its stored cadence stopped parsing.
- `completed` — the cadence has no further occurrence, its creator is no
  longer in the workspace, or the user retired it. Saving a cadence with a
  later `endDate` revives it.

All three can be requested on `update`. Requesting `completed` also sets the
cadence's `endDate` to the end of today in the schedule's timezone, which is what
the editor then shows as the end date. The system writes `completed` on its own
when it claims the final occurrence, leaving the cadence as it is.

`currentTask` is the schedule's unsettled task (`{ id, status }`, or null once
every task has settled). Its `status` is the run's progress, independent of the
schedule's: `pending`, `queued` or `running` while the occurrence executes, and
`waiting_for_user` when it is blocked on a question. A paused schedule can still
carry a running task, and a completed one its final run. `nextRunAt` is the next
unclaimed occurrence — it is not tied to either status. `lastRunAt` is the last occurrence the scheduler consumed, stamped even
when that occurrence was skipped without running, so a value there does not by
itself mean work happened.

## Semantics worth knowing

- **You only see your own.** `list` returns the schedules the current user
  created; another user's schedule ids return `not_found`, indistinguishable
  from ids that never existed.
- **Updates are partial.** Only the fields in `--input` change. Setting
  `"status": "paused"` clears `nextRunAt`; resuming or changing
  `scheduleConfig` recomputes it from now; changing only `name` or `prompt`
  does not shift the next run. Pausing an already-`completed` schedule is a
  `validation_error` — save a cadence with a later `endDate` to revive it
  instead.
- **Edits apply from the next occurrence.** `update` is accepted while a run is
  in flight, including a run of this very schedule. The occurrence already
  running carries its own copy of the prompt and its own slot, so an edit never
  changes what it is doing — it takes effect from the next occurrence on. This
  is what lets a scheduled run adjust the schedule that started it.
- **Delete removes the schedule's history with it.** Every run the schedule
  produced, and the Clay agent tasks those runs created, are deleted along with
  the schedule; nothing here undoes it. Confirm with the user before deleting a
  schedule that has run (`hasRun` true) — set `"status": "completed"` instead
  when the runs should stay readable. Delete is a `conflict` while a task is
  _executing_, since that agent is mid-turn; a task merely waiting on the user
  is deleted along with the schedule and its question is dropped. Not
  idempotent — a second delete of the same id is `not_found`.
- **Runs are gated at fire time.** An occurrence runs only if the Clay agent is
  still enabled for the workspace and the creator is still a workspace editor;
  otherwise it is skipped, not queued. A creator who has left the workspace, or
  whose account is gone, also retires the schedule: the occurrence is skipped
  and the schedule moves to `completed` rather than waiting for the next one.
- **Occurrences do not pile up.** If runs were missed (downtime, a long pause),
  the schedule resumes with a single next occurrence rather than replaying the
  backlog.

## Error codes

JSON on stdout, a typed error envelope on stderr. Exit codes: `0` ok, `1`
conflict, `2` validation, `3` auth, `4` rate-limit, `5` network, `6` not-found.

- `2` covers a malformed `--input`, a cadence that runs more than once a day or
  has no future occurrence, a non-UUID `scheduleId`, pausing a completed
  schedule, and the 20-schedule cap.
- `1` (`conflict`) covers deleting a schedule whose task is executing, and — on
  any command — the moment between the scheduler reserving an occurrence and
  starting it. The second is two statements wide; retry rather than reporting
  it as a limitation.
- `6` on `list` usually means the Clay agent is not enabled for the workspace;
  on `update`/`delete` it usually means the id belongs to another user's or a
  deleted schedule.

## Current limitations

Everything below is **not yet**, not impossible — check `clay schedules --help`
before telling a user something cannot be done.

- **No way to answer a `waiting_for_user` task.** There is no `clay` command that
  opens, replies to, or stops the task in `currentTask`; tell the user to answer
  it in the Clay UI. Editing and deleting the schedule still work, so this
  blocks only answering the question itself.
- **No run history command.** Nothing lists the tasks a schedule started or
  whether the last occurrence succeeded; `lastRunAt` on `list` is the only
  trace, and it does not distinguish a run from a skip.
- **`list` cannot filter server-side.** It is cursor-paginated (`--limit`,
  `--cursor`), but the 20-schedule cap means one page holds them all at the
  default limit, so `cursor` is normally absent. Narrow by `status` with `jq`.
- **No cross-user visibility.** There is no way to list or manage schedules
  other workspace members created.
