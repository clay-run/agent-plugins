---
name: signals
description: 'Clay Signals — watches that detect real-world changes (job changes, new hires, promotions, funding news, job postings, topic intent) and write them as events onto a table or an audience. Use for any request about a workspace''s signals: which ones exist, what one watches or writes to, whether one is running, turning one on or off, and why one is or is not producing events.'
---

# Clay Signals

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

A signal watches a set of records and emits an **event** when something changes
in the real world — someone changes job, a company posts a role or raises a
round. It has two halves, and telling them apart is the first thing to get right.

**Resolve the population before discovery.** For a historical question, use the
request and context to distinguish existing workspace records from net-new
prospects; ask if unclear before exploring either surface. For existing records,
read the `audiences` skill's `queries.md` and query captured events directly.
List triggers when managing watches, not as a prerequisite for historical
queries. An empty trigger inventory or summary field does not establish that
captured events are absent; check history before proposing a new watch.

| Record             | Id prefix | What it is                                           |
| ------------------ | --------- | ---------------------------------------------------- |
| Trigger definition | `td_…`    | The runnable unit: name, run status, filter, output. |
| Signal             | `sig_…`   | The underlying watch that trigger definitions share. |

**`id` in CLI output is the trigger definition (`td_…`), and it is the only id
these commands accept.** `signal.id` is the other record; passing it to
`clay signals get` is a `not_found`. Everything a user calls "a signal" — its
name, whether it is on, what it writes to — lives on the trigger definition.

**Web intent is out of scope.** Read **Current limitations** at the bottom before telling a
user something cannot be done: it lists every gap with what to do instead.

## The commands

```bash
clay signals list                          # every signal in the workspace
clay signals get <triggerDefinitionId>     # one signal, with its filter, schedule, and error
clay signals create --type T --input JSON  # new signal of a supported type
clay signals update <triggerDefinitionId>  # rename, re-schedule, re-filter, change per-type settings
clay signals pause <triggerDefinitionId>   # stop signal running, and stop it spending
clay signals resume <triggerDefinitionId>  # run signal again on its existing schedule
clay signals delete <triggerDefinitionId>  # remove signal but keeping the events it captured
clay signals search-topics --query Q --entity-type person|company  # topicIds for a topic intent signal
```

Excluding web intent makes `list` rows one per signal, so they are safe to count. Narrow
with `jq`:

```bash
clay signals list | jq -r '.data[] | "\(.id)  \(.signal.type)  \(.runStatus)"'
clay signals list | jq '[.data[] | select(.runStatus == "Errored") | .id]'
```

Read `clay signals list --help` and `clay signals get --help` for the exact output
shapes; they are the contract.

`pause` and `resume` return the signal with `runStatus` already updated, so no
confirming call is needed. They write nothing but the status: schedule, filter,
and destination are untouched, and setting a status a signal already has changes
nothing, so a retry after a network failure is safe.

**`create`, `update`, `pause`, and `resume` may answer `approval_required`.** Present the
request for the user's decision rather than retrying; approving applies it. A held
table-watching `create` has already made its destination table, so rerunning it makes another.

**Only an Active or Paused signal can be toggled.** Any other `runStatus` —
`Errored`, `Disabled`, `Testing`, `Preview` — is refused.

**Pausing is the credit lever.** A paused signal stops checking and stops
spending — reach for it when a signal costs more than it is worth, rather than
suggesting deletion.

**Reach for `pause` before `delete`.** Pausing already stops the signal running
and stops it spending, and it is reversible. Nothing undoes a delete: recreating
the signal means rebuilding it in the app and starting from a fresh baseline, so
the first weeks of coverage are lost again. Confirm with the user before deleting
something they may only want stopped, and show them `get` output first.

**Identify a write target by id, not by name.** `get` returns `input` — the same
targeting the list row carries — so read the signal back and check what it
actually watches before pausing or deleting it. Names are not unique and are not
reliable selectors; see the `ALL` warning under **Signals on audiences** for the
specific way name-matching goes wrong on audience signals.

**Deleting keeps the data.** The destination table and its rows survive, as do
the signal activities already on audience entities — a delete removes the watch,
not the history. It is also **not** idempotent: a second delete of the same id
returns `not_found`, which here means "already gone or never existed", so do not
read it as confirmation.

## Creating and updating a signal

**`clay signals create --help` is the list of creatable types and the authority on each
one's `--input` shape.** It is generated from the supported set, so it is never out of date;
anything absent from it is an app job, and passing such a type says so by name rather than
failing obscurely. The same goes for `clay signals update --help` and what that type lets you
change.

Types differ in what they take. The watch — a table view, or audience segments — is common to
all of them, but the settings beside it are not: one type takes search filters, another a set
of topic providers. Never carry an `--input` shape from one type to another; read the shape
for the type in hand, and prefer copying a working signal of that same type:

```bash
clay signals get td_abc123 | jq '.signal.inputs'   # copy this, edit it, feed it back
```

**Never guess a vocabulary value — fetch it.** Several `--input` fields take a fixed set of
exactly-spelled values that a misspelling silently turns into "matches nothing": news
`topics`, job-post `seniority` and `employment_type`, new-hire seniority levels and company
size/revenue buckets. Those closed sets are enumerated in full in `clay signals create --help`,
under each type's `--input` shape — read the values there rather than recalling them. The two
vocabularies that page cannot enumerate: topic intent `topicIds`, which
`clay signals search-topics` resolves (see **Topic intent types** below), and new-hire
`job_functions`, which is resolved per workspace — prefer `job_title_keywords` over it.

**Check for a duplicate first.** Nothing stops two signals of the same type watching the same
records, and each is charged in full. `clay signals list` and compare `signal.type` against
`input` before creating another.

**Resolve audience ids, never names.** `--input`'s `segmentIds` are ids from
`clay audiences list --entity-type companies|people`. See the `ALL` warning under **Signals on
audiences** — matching words in a segment name is how the wrong signal gets written.

**A table-watching signal needs three ids, and only two have a command.** `clay tables list`
gives `tableId`, `clay tables columns list <tableId>` gives the `fieldId` for the identifier
field. There is no command for `viewId` — read it off the table's URL in the app, or off
`input.table.viewId` of an existing signal on the same table:

```bash
clay signals list | jq -r '.data[] | select(.input.table.id == "t_abc123") | .input.table.viewId'
```

**A created signal is Paused.** It neither runs nor spends until `clay signals resume <id>`.
That order is deliberate: read it back, confirm `input` is what you meant, then resume. Pass
`--activate` only when the watched set and its identifier coverage have already been checked,
because a check that has run cannot be taken back.

**Price the signal before choosing a cadence.** Which of the two billing models a type uses
decides whether cadence matters at all — see **Two billing models** under **Common issues**.
For a per-record-checked type, cadence multiplies the bill and a large watched view on a fast
cadence is among the most expensive things a workspace can run; narrow the watched view before
slowing the cadence. Omitted, `--schedule` takes that type's own default, which is not the
same across types — and some types accept only a subset of the cadences (topic intent checks
weekly at the fastest, matching how often its providers refresh); the `--type` values in
`create --help` list each type's set.

**Some types are created with a default filter.** Omitting `--filter` takes it, matching the
app — job change and promotion start at `confidence >= 90`, which is why a new signal can look
healthy and still emit less than expected. Passing `--filter` replaces the default rather than
adding to it.

**`--filter` and a type's own `filters` are two different things, and confusing them is the
main way a signal ends up watching for the wrong thing.**

- **`--filter`** decides which _detected_ events fire. One flag, the same on every type, and
  what `get` returns as `filter`.
- **`filters`**, a key inside `--input` on the types that have one, is the search that decides
  what the signal looks for in the first place — which hires count for a new-hire signal,
  which postings for a job-post signal, which articles for a news signal. It lives in
  `signal.inputs.filters`.

A search `filters` document replaces rather than merges, and the search schemas are large and
heavily defaulted: a key you leave out is set back to its default, not left as it was. So edit
a real one rather than composing one from memory:

```bash
clay signals get td_abc123 | jq '.signal.inputs.filters'   # copy this, edit it, feed it back
```

**Topic intent types have their own gate and their own vocabulary trap.** `PersonTopicIntent`
and `CompanyTopicIntent` are gated separately from the rest of signals, so `create` can fail
with exit 3 on a workspace where every other type works. Their setting is `providerConfigs` —
which intent providers to ask, and which of each provider's topics to watch — and its
`topicIds` come from each provider's own catalog (opaque ids, except bombora's, which are the
topic names spelled exactly).

**Resolve `topicIds` with `clay signals search-topics` — never guess them, and never copy them
off another signal.** A guessed id validates and then matches nothing, and another signal's
ids encode _its_ topics, not the ones this user asked for. Describe what the user wants to
detect in plain language and take the ids from the result, per provider:

```bash
clay signals search-topics --query 'sales intelligence tools' --entity-type company
```

Each result maps one topic to its id in every provider's catalog (`matches.<provider>[].id`);
use each id only in a `providerConfigs` entry for that same provider. Pass the entity type
matching the signal type — a `person` search excludes person-restricted topics and returns no
bombora ids, because bombora is company-only.

A provider config without `topicIds` watches every topic that provider tracks, not none — and
every topic is charged per record on every run, so an omitted topic list is a cost decision,
not a blank.

Which providers a topic intent signal uses is also fixed at creation, unlike its topics:
`update` can change the `topicIds` and `tiers` inside each config, but adding or dropping a
provider is refused because each one keeps its own detection baseline. Choose the provider set
deliberately at create time — changing it later means a new signal.

**A failed table-watching create leaves something behind, and recovery depends on where it failed.**
The destination is set up before the signal is validated, and nothing cleans either up.
Read the error to tell the two apart before retrying:

- **The signal was rejected** — an unknown view, a watched view over the monitoring limit, a
  rejected filter, missing permissions. No signal exists, so `clay signals list` shows nothing:
  it lists signals, not tables. Retrying makes a _second destination_, not a second signal.
  Find the leftover table first. Without `--destination-table` that is a new table named
  `<Type> Events from <watched table> (<date>)`, which `clay tables list` will show; with
  `--destination-table` the table you named is now carrying a source that feeds nothing. Remove
  either in the app.
- **The signal was created but the command still failed**, on reading it back. The signal
  exists and runs while the command exits non-zero, so here `clay signals list` does show it —
  check there before retrying, or you end up with two signals.

An audiences signal is created in a single step and has no destination table, so neither case
applies to one.

**What a signal watches is fixed once created.** No type lets `update` repoint a watched
table, view, or identifier field — create a new signal and delete the old one. Name, schedule,
and filter are always editable; beyond those, what `update` accepts is per type and narrower
than what `create` took, so check `clay signals update --help` rather than assuming a field
that was settable at creation still is. Run status is on neither verb; `pause` and `resume`
own it.

**`update --input` changes only the keys it names, and replaces each of them whole.** Keys it
leaves out are untouched, so an update changing `segmentIds` does not disturb `filters` and
vice versa. `segmentIds` is the one key that requires an audiences signal — a table-based one
cannot be given audiences to watch.

Within one key there is no merging, though: a `filters` document replaces the saved search
outright, and any key absent from the one you send goes back to its default rather than
keeping its current value. Read the current search, edit it, send it back whole.

**Replacing a filter is how a signal quietly starts or stops emitting.** `update --filter`
replaces outright rather than merging, and `--clear-filter` removes it. Read the current one
first:

```bash
clay signals get td_abc123 | jq .filter
```

**A missing or stale identifier silently drops a record.** Nothing reports it, so check
coverage on the watched view or segments before trusting a new signal — see **The watch
column is a prerequisite** under **Signal types**.

## input is not destinationTable

The single most common misreading of this output. They are separate axes, and on
a table-based signal they are **two different tables**.

- **`input`** — what the signal watches. Either `input.table` (`{ id, viewId }`)
  or `input.audiences` (`{ segmentIds, entityType }`); at most one is set, and
  both are null for a custom signal, which is driven by an action instead.
- **`destinationTable`** — where its events are written.

`destinationTable` is null for an audiences-based signal, because its output goes
back onto the audience entities rather than into a table. It is also null when a
table-based signal has no destination resolved, so `destinationTable: null` alone
does not prove a signal is audience-based — check `input`.

## Signals on audiences

An audiences-based signal writes its output back to the audience entities as
**signal activities**. Nothing appears in a table, so don't go looking for one.

**Where the user sees it in the app.** An audiences-based signal is listed only
under **Companies** (`ACCOUNT`) or **People** (`CONTACT`) → **Data hub** →
**Signals**. It never appears on the **Signals** page in the main sidebar, which
lists table-watching signals only. When a user asks where to find, check, or edit
an audiences-based signal, send them to Data hub for its entity type. If they are
on the Signals page and can't find it there, that is expected and does not mean
the signal is missing. A table-watching signal is the reverse: it appears on the
Signals page and not in Data hub.

Its `input.audiences.segmentIds` are audience ids from `clay audiences list`, and
`entityType` uses the middle spelling — `ACCOUNT` / `CONTACT`, not
`companies` / `people`.

**`ALL` in `segmentIds` is a sentinel, and it collides with real segment names.**
It means the whole audience of that entity type — not a saved segment, and not a
segment called "BigQuery ALL" for example. A signal watching everything
and a signal watching a segment whose name contains "ALL" are indistinguishable
to a text match, so **never pick a signal by matching words in a name**: resolve
segment ids with `clay audiences list` and compare `segmentIds` against those
ids. This matters most before a write — `delete` on the wrong match is not
recoverable.

The `signal_summary` default field on people and companies is derived from those
signal events, so it is the record-level view of what a signal has been doing.
See the `audiences` skill for reading it, and its `filters.md` for selecting
records **by** their signal events — "companies with a job posting in the last
30 days" is an audience filter, not a signals command.

To read the captured events for one person or company, use the Audiences
`signals list` command with `--entity-id`. For a saved segment, use `signals list`
with `--segment-id`; to aggregate that segment by signal id and type, use
`signals summary`. These are separate from `clay signals`, which manages the
signal definitions and run status. The segment commands accept `--signal-ids`
as underlying `sig_…` ids, not trigger definition `td_…` ids.

## A signal that runs but produces nothing

Work down this list — the first two explain most cases, and both are visible
without spending anything.

1. **`runStatus`.** Only `Active` and `Preview` run. `Testing`, `Paused`, and
   `Disabled` do not; `Errored` stopped after a failure.
2. **`filter`, from `get`.** Job change and promotion signals are created with a
   default of `confidence >= 90`, so a signal can run correctly and still emit
   far fewer events than the user expects. A `null` filter is unfiltered; a
   missing filter is not the same as no filter having been configured.
3. **`error`, from `get`.** Populated when `runStatus` is `Errored`.
   `userFriendlyMessage` is what the app shows; `message` is the underlying
   failure.
4. **`schedule`, from `get`.** Cadences are often weekly or monthly, so a signal
   may simply not have run yet. `schedule.lastRunAt` and the top-level
   `lastRunAt` are the truth — `list` deliberately omits them.
5. **Where the output goes.** An audiences-based signal writes activities onto
   entities, not rows into a table (see above).

## Signal types

| `signal.type`            | Fires when                                                  | Watches by                        |
| ------------------------ | ----------------------------------------------------------- | --------------------------------- |
| `JobChange`              | A tracked person's current company changes                  | Person LinkedIn URL               |
| `NewHire`                | A tracked company hires someone matching your criteria      | Company identifier                |
| `Promotion`              | A tracked person's title advances at their current company  | Person LinkedIn URL               |
| `JobPost`                | A tracked company opens a job posting matching your filters | Company identifier                |
| `News`                   | A tracked company appears in news, including funding rounds | Company identifier                |
| `LinkedinPostMentions`   | Discontinued — a post mentioned your organization           | Organization id + connection      |
| `PersonTopicIntent`      | A tracked person researches one of your topics              | Person LinkedIn URL               |
| `CompanyTopicIntent`     | A tracked company researches one of your topics             | Company identifier                |
| `Custom`                 | An enrichment you configure returns a change                | Any action output                 |
| `WebsiteVisitorTracking` | A de-anonymized visit hits your website (web intent)        | Tracking script, not a record set |
| `FakeSignal`             | Internal test type — not created through product flows      | —                                 |

`LinkedinPostMentions` is no longer available: never suggest it, and do not try to create or
update one — both are refused. A workspace may still hold signals of the type from before,
and those are fine: they appear in `list` and can be read, paused, resumed, and deleted like
any other. For an existing one, know that it watches an organization rather than a record
set — an `organizationId` and a LinkedIn connection, with an optional table or audience
filtering only _who_ mentioned you — so check those three when its coverage looks wrong.

**The watch column is a prerequisite, not a detail.** A person-based signal tracks the
LinkedIn URL on each record; a record with a missing, stale, or invalid URL is silently
not monitored, and no error tells you so. Check coverage before trusting a signal — but
check it in the store the signal actually watches, which `input` on `get` tells you:

- **`input.audiences` set** — the records live in Audiences, so
  `clay audiences records search-count` with a `NotEmpty` filter on the identifier
  field gives the fill rate, per the `audiences` skill.
- **`input.table` set** — the records live in that table, and `input.table.viewId`
  narrows the watch to one view when it is set, so coverage has to be measured over that
  view and not the whole table. Read `/tables`.

`signal.inputs` on `get` is the stored per-type configuration, returned as-is — read a
working signal of a type before assuming its shape.

A user rarely names a signal type; they describe an outcome. The sections below are the
prompt shapes that map to each type — recognize one, then follow **Matching a request to a signal**
below rather than jumping straight to `create`.

### `JobChange`

Use when the request is about tracked _people_ changing employers: "tell me when any of my
champions change jobs", "which of my past customers landed somewhere new", "alert me when a
contact leaves their company", "track job changes across my CRM contacts". The employer is
what changes — a new title at the same company is `Promotion`, and "who did this _account_
hire" is `NewHire`.

### `NewHire`

Use when the request is about tracked _companies_ bringing people on: "tell me when a target
account hires a VP of Sales", "which accounts just brought on a new CMO", "alert me when a
company on this list hires into the persona I sell to", "find new decision-makers at my
accounts". Fires when someone has actually joined; a role that is merely open is `JobPost`.

### `Promotion`

Use for title advancement at the same company: "tell me when my champion gets promoted",
"track title changes in my buying committee", "who in my contacts moved up to director or
above", "congratulate contacts on new roles". If the company changed too, that is
`JobChange`.

### `JobPost`

Use for hiring as a buying trigger, while the role is open: "which of my accounts are hiring
SDRs", "alert me when a target account posts a job mentioning Kubernetes", "companies hiring
for the role my product serves", "use open roles to prioritize outreach".

### `News`

Use for company news and fundraising: "tell me when my accounts raise a round", "track
acquisitions in my territory", "alert me when a customer launches a product or hits the
news", "use funding events to trigger outreach". Fundraising is a `News` topic, not a
separate type.

### `LinkedinPostMentions`

Recognize "tell me when someone mentions our company on LinkedIn", "track posts talking
about our product", "who is talking about us" as brand-mention asks — and then do **not**
reach for this type: it is no longer available (see the note above). Never suggest it, and
never try to create or update one. If the workspace already has one, reading and managing it
is fine; for a _new_ brand-mention request, say plainly that no signal covers it anymore.

### `PersonTopicIntent`

Use when the request is about which tracked _people_ are researching something: "which of my
contacts are researching data warehouses", "people in-market for our category", "prospects
showing intent on the problem we solve", "who is actively looking into this space right now".

### `CompanyTopicIntent`

Use when the request is about which tracked _accounts_ are researching or in-market:
"I want to know which of my accounts are researching or in-market for <something>",
"surface accounts showing buying intent for our category", "which target accounts are
in-market right now", "pull third-party intent on my account list", "prioritize accounts
spiking on <topic>". Account-level intent; the same ask about named individuals is
`PersonTopicIntent`.

### `Custom`

Recognize "fire when <some enrichment or action output> changes" with no built-in type
covering it as a `Custom` signal — a change watch over an arbitrary action's output. It
cannot be created or updated from these commands: building or changing one is an app job,
so route the user there. Existing ones read and manage normally.

### `WebsiteVisitorTracking`

Recognize "who visited my website", "de-anonymize our site traffic", "alert me when a target
account hits our pricing page" as web intent — a real signal type, but out of scope for
these commands entirely: it cannot be created, updated, or even read here (see **Current
limitations**). Route the user to the Clay app.

## Matching a request to a signal

When a prompt matches one of the shapes above, work in this order — the answer is usually an
existing signal's output, not a new signal:

1. **Look at what already exists.** `clay signals list`, and compare `signal.type` and
   `input` against what the user is asking about — resolve tables and segments by id, never
   by name (see **Signals on audiences**). A signal of the right type watching the right
   records already answers the question, and a second one would double the spend.
2. **If a fitting signal exists, read its output rather than creating another.**
   For a table-based signal, read `destinationTable.id` with the `/tables` skill. For an
   audiences-based signal, use `clay audiences signals list --entity-id` when
   one person or company is in scope, `clay audiences signals list --segment-id`
   for full event payloads across a saved segment, or `signals summary` for
   counts within a saved segment. The segment commands can filter
   with the underlying `signal.id` (`sig_…`) when the user means one particular
   signal.
3. **If none fits, ask before creating.** Do not create a signal the user did not ask for —
   propose it and get a yes. Before the create, show them exactly what will exist so they
   can confirm: the type, what it will watch (table + view + identifier field, or audience
   segments by id and name), the per-type settings (`filters`, `providerConfigs`, topics),
   the schedule, the event filter, and how it is charged (see **Two billing models**). Note
   that it is created Paused and only starts checking — and spending — on
   `clay signals resume`.

## How signals get used

**Resolve workflow trigger intent from context.**
The workflow CLI supports `audience_signal`, bound to the underlying `signal.id`,
when signal events are the intended trigger. Compare plausible sources using the
request and prior discussion, then ask if the choice remains ambiguous. See
`workflows/trigger-selection.md` for examples and binding details.

The standard GTM shape is **detect → qualify → act**, and a signal is only the
first step. When helping a user design one, ask what the other two are.

- **Champion tracking** — a `JobChange` signal on an audience of customer
  contacts (champions). An event means a warm relationship just landed at a new
  account: the play is enrich the new company, check ICP fit, alert the owner or
  open a CRM opportunity. The qualification step matters — a board seat or
  advisory role added alongside an existing job is not a "champion moved".
- **Signal-based plays on audiences** — the app pairs a signal with a segment
  whose filter selects records with recent events of that type (the
  `signal_events` filter — see the `audiences` skill's `filters.md`). The
  segment is live: records enter as events arrive and age out with the lookback
  window. Use that segment for membership-based workflows or exports; use an
  `audience_signal` workflow trigger when the user wants to react to signal events.
- **Hiring / funding as account intent** — `JobPost` and `News` on a company
  audience, feeding prioritization: a company hiring for the role your product
  serves, or one that just raised, moves up the outreach queue.
- **Topic intent** — `PersonTopicIntent` / `CompanyTopicIntent` mark who is
  researching your category now; usually combined with fit filters rather than
  acted on alone.

Events land in the destination — table rows, or activities on audience entities
plus the derived `signal_summary` field. Workflows can react through an
`audience_signal` trigger or use a segment when membership is the intended condition.

## Common issues and how to avoid them

Beyond the checklist above, these are the recurring ways signals surprise
users in practice:

- **Signals detect changes after monitoring starts.** A change-detection signal
  (job change, promotion) diffs fresh data against a baseline captured when
  monitoring began. Changes that happened before the signal existed produce no
  events, except for the one-time historical lookback at setup (job change
  defaults to 3 months, `lookBackTimeWindowInMonths` in `signal.inputs`). Set
  expectations accordingly: a signal created today mostly pays off in the
  following weeks, and "this person changed jobs last quarter, why no event?"
  is usually this, not a bug.
- **Two billing models, and only one scales with records watched.** Check which
  before estimating anything.
  - **Per record checked** — `JobChange`, `NewHire`, `Promotion`, `JobPost`,
    `PersonTopicIntent`, `CompanyTopicIntent`. These charge for every record examined on
    every run whether or not it produces an event, so a large watched set at a fast
    cadence is one of the most expensive things a workspace can run. Size it as
    (records in the watched view or segments) × runs per month, and prefer narrowing the
    watched set over slowing the cadence. The two intent types multiply that by each
    selected provider's selected topics (`providerConfigs` in `signal.inputs`), so a
    quiet audience still pays in full and adding a topic is a cost change.
  - **Per result** — `News`, `Custom`, `LinkedinPostMentions`. These charge for events
    emitted, not records scanned, so the record × frequency formula does not apply and
    can be wildly wrong in either direction: a large quiet audience costs little, while a
    small noisy one can cost a lot. Estimate from expected event volume, and treat a
    loosened event filter as a cost change rather than only a coverage change.
- **A signal that exhausts its credit limit stays stopped.** An audience signal can
  carry a `creditLimit`, and exhausting it does not throttle the signal — the run sets
  its status to `Paused`, and nothing puts it back. The one automatic credit-cycle
  reactivation in the product is specific to web intent, so an ordinary audience signal
  stays paused until someone starts it again. Do not tell a user it will pick up next
  cycle: check `runStatus` on the signals they expect to be running, and once the limit
  is raised or the cycle rolls over, `clay signals resume` each paused one. Insufficient
  credits surfaces the same way — at run time, not as a validation error at setup.
- **The default filter eats events silently** — `confidence >= 90` on job
  change and promotion (see the checklist). When a user reports "missing"
  events for changes that really happened, check the filter before the watch.
- **Restrictive filters look like a broken signal, and there are two layers of
  them.** The search in `signal.inputs.filters` — news topics, job title
  keywords, seniority, locations — decides what the signal looks for, and the
  `filter` from `get` decides which of what it found actually fires. A signal
  can be healthy and emit nothing because either layer excludes everything, so
  read both before concluding events are missing, and loosen one at a time so
  you can tell which was responsible.
- **Watching a live segment means the watch list moves.** An audience-based
  signal monitors current segment membership, so records entering the segment
  start being monitored (with a fresh baseline — see above) and records
  leaving stop. If a user needs a stable cohort watched, the segment filter
  needs to define one.
- **Duplicate signals double the spend.** Two trigger definitions can share a
  watch or overlap on the same records. Before creating a signal, run
  `clay signals list` and check for an existing one of the same type over the
  same input — and prefer pausing or deleting the redundant one over leaving
  both running.

## Error codes

JSON on stdout, a typed error envelope on stderr. Exit codes: `0` ok, `2`
validation, `3` auth, `4` rate-limit, `5` network, `6` not-found.

- `3` usually means signals are not enabled for the workspace, or the credential
  cannot read them — a workspace-config answer for the user, not a retry.
- `6` on `get` most often means a `sig_…` was passed where a `td_…` belongs.

## Current limitations

Everything below is **not yet**, not impossible. This section shrinks as
commands land — when one does, delete its entry rather than rewording it, and
check whether the caveats elsewhere in this file still hold.

- **Not every type can be created yet.** `clay signals create --help` lists the ones that
  can; `Custom` and web intent are app-only for now, and `create` refuses them by name. This
  set grows, so read the help rather than a remembered list. `LinkedinPostMentions` is no longer available — see **Signal types**.
- **`update` is narrower than `create`, per type.** Name, schedule, and filter are always
  editable; everything else depends on the type, and a watched table, view, or identifier
  field is fixed for all of them.
- **Web intent (`WebsiteVisitorTracking`) is out of scope entirely.** `list` excludes it
  and every other command refuses it, so these commands never report on or change one at
  all — a web intent question is an app question.
- **`list` cannot filter or paginate.** It returns every signal in one
  response; narrow with `jq`. There is no server-side filter by type, status,
  or input.
- **`list` omits the schedule, last run, filter, and error.** The route behind
  it does not carry them, so they come from `get` one signal at a time — an
  N+1 for questions like "which signals are stale?"
- **No cost, health, or test commands.** The API exposes estimated signal cost,
  job status, and validation info, but nothing surfaces them yet: size a signal
  by hand (see **Common issues**), and diagnose from `get`'s `runStatus`,
  `error`, and `schedule`.
