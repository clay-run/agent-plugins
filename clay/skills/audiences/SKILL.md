---
name: audiences
description: Clay Audiences — the workspace's own people, companies, and deals (contacts, leads, accounts, customers). Use for any request about their records when no surface is named, including counts, fill rates, lookups ("how many people have a phone?"), saved segments, and field definitions. Also deal and pipeline questions like largest opportunities, biggest pipeline items, recent wins, closed-won, deal stage, and ACV. Also the calls and meetings synced onto those records, such as Gong recordings.
---

# Clay Audiences

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

Audiences is Clay's CRM-shaped store of **people** and **companies** (plus deal
records). An **audience** — also called a saved segment — is a named filter over
one entity type. Nothing is copied into it: it selects records live, so its
membership changes as records change.

**Audiences is the default home for the workspace's own people and companies.**
When a user mentions people, companies, contacts, leads, accounts, customers,
deals, or opportunities without naming a surface, they mean these records —
start here, not in the tables entry-point skill (a separate surface, right only
when the user names a table) and not in `search` (net-new prospects that are not
in the workspace yet).

Read this before any audiences work. Supporting references:

- `answering-data-questions.md` — **read this first for any request to count,
  find, or filter existing records.** Before filtering a categorical field, call
  `fields list-values` as described there. Also covers field coverage and when
  to enrich.
- `queries.md` — **read before searching or counting records. Prefer `--query`,
  including activity and signal criteria, even when the task will later save an audience.** Audiences DSL grammar,
  relationship semantics, data or date filters, and server-side sorting for
  top-N questions.
- `filters.md` — writing the filter AST to create/update a saved audience, or
  validate that saved filter. Use it for record searches only when DSL cannot express the criteria.
- `frontend-ast-filters.md` — supported AST segment-editor fields, operators, and collection
  shapes. Consult when choosing a saved filter; backend search support is broader.
- `custom_objects.md` — **deals / opportunities.** Read it before anything that
  touches them, including vague rankings such as "largest opportunities",
  "biggest things in our pipeline", or "recent wins", and GTM phrasings:
  closed-won, closed-lost, open pipeline, deal stage, deal size / ACV / ARR,
  close date, forecast, win rate,
  renewal, expansion, churn, "our customers". Deals are read-only. Use the DSL
  `opportunities` root for deal counts and IDs; use people/company roots when
  the requested results are contacts/accounts associated with those deals.
- The `workflows` skill's `audiences.md` — writing values onto records (the
  `upsert-audiences-record` action) and triggering a workflow off an audience.

**Read with the CLI, write records with the action.** `clay audiences` covers
every Audiences primitive — segments, fields, and reading records — but it has no
command that writes a field value onto a record. That is the
`upsert-audiences-record` action's job.

**Net-new people or companies** — not in the workspace yet. When `search` and `routines`
are available CLI commands, start in the `searches` skill, then persist via a routine
wrapping an upsert workflow (the `workflows` skill's `audiences.md`, then the
`routines` skill).

**Act on this audience** — pull matching records (`records search-ids` / `get`). When
`routines` is an available CLI command, run a routine over them (see the `routines`
skill). Ongoing automation (fire when membership
changes) is the `workflows` skill's `audiences.md` (`audience_segment` trigger).

## One entity type, three spellings

The same entity types are named differently depending on where you are. Get this
mapping right up front — it is the most common source of wasted round trips.

| CLI `--entity-type` | Filter AST / action `entityType` | Filter `dataPath` root        |
| ------------------- | -------------------------------- | ----------------------------- |
| `people`            | `CONTACT`                        | `contact_entity_field_values` |
| `companies`         | `ACCOUNT`                        | `account_entity_field_values` |
| `deals`             | `CUSTOM` (Opportunity)           | `opportunity`                 |

Supported `--entity-type` values by command (all under `clay audiences`):

| Commands                                                                                         | Accepted values                | Deals support                                              |
| ------------------------------------------------------------------------------------------------ | ------------------------------ | ---------------------------------------------------------- |
| `records get`, `records search-ids`, `records search-count`, `fields list`, `fields list-values` | `people`, `companies`, `deals` | Supported; deal searches with this flag must be unfiltered |
| `list`, `create`                                                                                 | `people`, `companies`          | Not supported; saved audiences target people or companies  |
| `fields create`, `fields update`, `fields delete`, `fields segments`                             | `people`, `companies`          | Not supported                                              |
| `signals list --entity-id`                                                                       | `people`, `companies`          | Not supported                                              |

Use these exact plural values: `person`, `company`, and `deal` are invalid.
Commands not listed above do not take `--entity-type`; segment-scoped commands
use the saved audience's type. CLI output can also carry `entityType: "deals"`.
For filtered deal searches, omit `--entity-type` and use `--query` with the DSL
`opportunities` root; read `custom_objects.md` first.

Workflow **triggers** use the middle spelling: an `audience_segment` trigger's
`segmentId` is the audience id from `clay audiences list`, and its `entityType`
is `CONTACT` / `ACCOUNT`, not `people` / `companies`.

## Audiences (saved segments)

Prefer dynamic segments: saved audience filters whose membership updates as
records start or stop matching the criteria. Use the user’s request and
conversation context to determine the filter. Use a fixed cohort with hard coded
matching values only when explicitly requested. Read `filters.md` before building
the filter, including saved-segment compatibility restrictions.

```bash
clay audiences list --entity-type people          # id, name, description, entityType (no filter); 50/page, pass back .cursor
clay audiences get <audienceId>                   # same, plus the full filter AST
clay audiences create --entity-type people --name "Missing emails" --filter ./filter.json
clay audiences update <audienceId> --name "…" --description "…" --filter ./filter.json
clay audiences archive <audienceId>               # soft delete, idempotent; records untouched
```

- `create` and `update` take `--filter` as inline JSON, **a file path, or `-` for
  stdin**. Use a file or stdin for anything non-trivial — inline JSON in a shell
  triggers an approval prompt and invites quoting mistakes.
- `update` replaces the whole filter; there is no partial merge, and entity type
  is immutable after creation. Omitted flags are left alone.
- `get` returns an id-free filter. Inspect it for unsupported clauses
  before using it to clone an audience; see `filters.md`.
- `archive` and `fields delete` may answer `approval_required`. Present the
  request for the user's decision rather than retrying; approving runs it.

### Choosing a segment

When the work needs a saved segment and none is identified — no open `audience`
surface, an entity-wide view, or a name that matches zero or several segments —
look before you ask:

1. Use `clay audiences list --entity-type <type>` to get all segments.
2. If exactly one segment plausibly fits the request, use it and say which.
3. Otherwise ask once with your ask-user tool (`AskUserQuestion`; `askUser`
   inside the Clay app): the 2–3 segments that best fit the request as
   `choices` — `value` = segment id, `label` = segment name, `description` = its
   description (or what it contains when it has none) — best match first. When
   the user is on an entity-wide view, also offer "All <entity> in this view".
   Add `{ type: "text" }` so they can name another segment.

Never ask for a segment name with only a text box. If none of the segments fit
the request, say so and ask whether they want to create a new segment. If no
segments of that type exist, don't offer one; offer the entity-wide scope or
creating a segment instead.

## Fields

Field ids are what record payloads and filter ASTs key on, and they are scoped
to an entity type — every subcommand takes `--entity-type`.

```bash
clay audiences fields list --entity-type people                       # every field: id, name, dataType, fieldType, hidden
clay audiences fields list --entity-type people --filter id=email     # narrow by id (repeatable, comma-separated)
clay audiences fields list --entity-type people --include-system      # system fields, hidden by default
clay audiences fields create --entity-type people --name "Lead score" --data-type number
clay audiences fields update <fieldId> --entity-type people --hidden true
clay audiences fields delete <fieldId> --entity-type people
clay audiences fields segments <fieldId> --entity-type people         # audiences whose filter references the field
clay audiences fields list --entity-type deals                        # deal field definitions
clay audiences fields list-values title --entity-type people          # distinct values and counts
```

- **Run `fields list` once and save it** (`> /tmp/people-fields.json`), then slice
  it with `jq`. Re-running it to grep, head, and parse the same output three
  different ways is pure latency.
- `fields list` returns the workspace record-field catalog (system fields
  excluded) — use those ids for `upsert-audiences-record`.
- **Names are not ids.** Account "company name" is `org_name`. Never guess an id
  from a display name.
- **Discover categorical values before filtering.** Use `fields list-values`
  instead of guessing labels. See `answering-data-questions.md`
  for value discovery and high-cardinality guidance.
- `create` silently uniquifies a taken name (`"Tier (2)"`) — read the returned
  `name` and `id` rather than assuming the one you passed.
- Before `update --data-type` or `delete`, run `fields segments <fieldId>`: a
  delete rewrites saved filters with those clauses **removed**, changing what
  those audiences match. Empty `data` means nothing is affected.
- Default and system fields reject `--name` and `--data-type` changes and cannot
  be deleted; `--hidden`, `--order`, and `--description` still work.

### Default field ids

Present in every workspace, so you can write a filter against these without
listing fields first:

- **people** — `name`, `first_name`, `last_name`, `email`, `linkedin_url`,
  `phone`, `title`, `signal_summary`
- **companies** — `org_name`, `domain`, `headquarters_location`, `linkedin_url`,
  `sfdc_owner_id`, `signal_summary`, `technographics`
- **deals** — see `custom_objects.md`

`signal_summary` is derived from the signal events a signal has written onto the
record, not something you set — to see which signals feed it, use the `signals`
skill.

Anything else is workspace-defined — get its id from `fields list`.

## Records

```bash
clay audiences records search-count --entity-type people --audience-id <id>   # count a scope server-side
clay audiences records search-ids   --entity-type people --audience-id <id>   # matching ids, --limit per page + .cursor
clay audiences records get --entity-type people --ids 1,2,3                   # field values, max 100 ids
```

Scope for both search commands (`--query`, `--audience-id`, and `--filter` are
mutually exclusive):

- no scope flag → every record of the entity type
- `--query <dsl>` → preferred for ad-hoc searches; omit `--entity-type`
  (combining them is an error). Use `count from ...` for `search-count` and
  `select from ...` for `search-ids`. Read `queries.md` before constructing the query
- `--audience-id <id>` → a saved audience's records
- `--filter <json|file|->` → AST fallback for unsupported DSL constructs;
  backend query support does not guarantee the frontend can render the filter.

Add `--archived` to either to search archived records instead of live ones.

**Use `search-count` for "how many".** It counts server-side without fetching
every ID. A field's `is_not_null` query (or `NotEmpty` AST filter) checks coverage
when relying on unfamiliar data or proposing an enrichment. See
`answering-data-questions.md`.

**Use `search-ids --query 'select from ... order by <field> desc' --limit N`
for top-N people, companies, or deals.** This is the preferred way to answer
"Top N" questions: rank server-side and fetch only the N returned IDs for details,
without paginating through the full record set or sorting it locally.
Before ranking, check the field's `dataType` with `fields list`: numeric questions
require a number or currency field, not numeric-looking text. If the type is
wrong, recommend fixing the Audiences field type before ranking; do not change
it without approval. Sorting supports one same-entity text, number (including
currency), or date field. Missing values come last. Sorted results have no cursor,
even if more records match; they are not a full export. To count the same scope,
use `count from ... where ...` without `order by` or `limit`. Read `queries.md`
for grammar, field discovery, limits, and examples.

For filtered deal counts and IDs, use `--query` with the `opportunities` root.
`--entity-type deals` without a query still covers the whole population; combining
it with `--audience-id` or a non-empty `--filter` is a validation error.
The `activities` root supports counts; activity IDs are strings and cannot use
`search-ids`' numeric pagination. See `queries.md` and `custom_objects.md`.

`search-ids` returns ids only — feed them to `records get --ids` in batches of
100 for field values, keyed by field id (unset fields may be omitted). Combine
known IDs into batches and reuse hydrated records across overlapping scopes. Records
not found are omitted rather than erroring. To size a scope, use `search-count`,
not a paging loop over `search-ids`.

### Budget the walk before you start it

`search-count` first, then decide whether a full walk is needed. Searches and
record fetches share the workspace's Audiences budget:

- **ids** — unsorted `search-ids` pages at `--limit` ids per call (default 50, max 10,000).
  Size it from the count: aim for about 10 calls.
- **field values** — `records get` takes up to 100 ids per call. Batch known ids
  to reduce requests and fetch only the records needed to answer the question.

When that does not fit your data size, **narrow the scope instead of grinding through it**:
tighten the filter — a shorter date window is usually the biggest
win, then a single stage, owner, or segment — or read one page and label the answer
a sample of that scope. Never start an unbounded paging loop and hope it lands: it
spends the workspace's budget and the user gets a stalled turn instead of an answer.

## Segment activities

Use `clay audiences activities` when the user asks what happened inside a saved
segment, such as recent email or call activity, campaign touches, source mix, or
activity volume over a period.

```bash
clay audiences activities list --segment-id audseg_abc --since 2026-08-01 --until 2026-08-20 --activity-types call
clay audiences activities summary --segment-id audseg_abc --since 2026-08-01 --until 2026-08-20 --activity-types call --sources CLAY_SEQUENCER
```

- Use `activities list` for the raw activity feed. It returns cursor-paginated
  events for records in the segment.
- Event `data` contains source-specific fields when available. The 1 MiB page cap
  may return fewer events than requested. Follow each cursor until none remains
  to retrieve all events. An event with `truncated: true` contains partial data;
  lowering `--limit` does not recover its omitted content.
- For distinct-record coverage, read `queries.md` and use `--query` with
  `activities.exists(...)`. Before saving criteria as an audience, follow
  [Saved segment restrictions](filters.md#saved-segment-restrictions); activity
  search predicates are not automatically supported saved filters. `eventId` is
  opaque and must not be parsed for record ids.
- Use `activities summary` for grouped counts by activity type and source when
  the user asks for totals, trends, or a quick breakdown instead of individual
  events.
- Bound activity reads to the requested time window and activity types. These
  queries can take a few seconds on large segments, so prefer one targeted
  request over repeated exploratory calls.
- It is okay to page through `activities list` with each returned cursor when the
  user needs the full bounded result set. Continuation requests pass only
  `--cursor` and optional `--limit`; do not repeat time, activity-type, or source
  filters with a cursor. Do not loop for freshness or repeatedly rerun broad
  activity queries without narrowing the request.
- Common prompts: "show recent calls for this segment", "summarize email activity
  since last week", "which sources drove activity for this audience?", "sample the
  latest campaign activity before I run a workflow".

Calls and meetings from Gong, calendars, and CRMs sync in as `call` and `meeting` activities on
the companies and people involved. When the user asks about a call without naming a segment, such
as a good Gong call to watch, read call activities over a segment that covers those records (find
one with `clay audiences list --entity-type companies`), then pick by title and date. Activity
rows carry no recording link: give the title, date, and account so the user can open it in Gong,
and never construct a URL.

## Signals

Signals write activities onto records.

A **signal** on an audience — a watch for job changes, new hires, funding news,
job postings — stores each captured event as an **activity attached to the
person or company entity**, not as a row anywhere.

### Decide whether "signals" means triggers or captured events

Users often call both the watch and each occurrence it captures a "signal". Do
not decide from the noun or signal type alone. Use the session context to form a
likely interpretation, but **do not silently guess**. If the user's wording does
not explicitly distinguish the two, ascertain their intent with a short,
plain-language question before calling either surface: "Do you mean how many
JobPost watches are configured, or how many JobPost events were captured?" You
may say which reading seems more likely from the conversation, but contextual
likelihood is not confirmation. An explicit earlier statement about triggers or
events does count as confirmation.

- Use `clay signals` for **trigger definitions** when the conversation is at the
  inventory or configuration level: listing, creating, updating, pausing,
  resuming, scheduling, checking run status, or choosing a destination. In that
  context, "how many JobPost signals do I have?" means count JobPost trigger
  definitions.
- Use `clay audiences signals` for **captured events** when the conversation is
  about results or history: what happened, detections over a period, affected
  records, an audience/segment, or a trigger's output. In particular, once the
  session is focused on one specific trigger, the same question — "how many
  JobPost signals do I have?" — usually means how many events that trigger has
  captured, not how many trigger definitions exist. Resolve its underlying
  `signal.id` with `clay signals get` when needed, then narrow
  `clay audiences signals summary` with `--signal-ids`.
- After the user confirms captured events, reuse the record or audience/segment
  and time scope already established in the session. If any required scope is
  still missing, ask for it rather than inventing one.

Once the intended meaning is clear:

- **Signal questions should use signal-specific surfaces.** Do not use
  `clay audiences activities` commands to answer signal-event questions; those
  commands read activity rows and can miss signal-specific event detail.
- **Read captured events by record or segment.** `clay audiences signals list`
  returns the full event history for one person or company with `--entity-id`,
  or full payloads across a saved segment with `--segment-id`. The
  `signals summary` command groups a segment's counts by signal id and type.
- **Find matching records with DSL.** Use `records search-ids/search-count --query`
  with `signals.<type>.exists(...)` — see `queries.md`. To save those criteria as
  an audience, see `filters.md`, "Filter by signal activity".
- Check captured history through those event relationships. An empty trigger
  inventory (`clay signals list`) or `signal_summary` field does not prove that
  no events exist.
- For which signals exist, what one watches, and why one is not producing
  events, see the `signals` skill — that is where to start for "is this
  audience's signal firing?"

```bash
clay audiences signals list --entity-id 123 --entity-type people --since 2026-08-01
clay audiences signals list --segment-id audseg_abc --since 2026-08-01 --until 2026-08-20 --signal-types JobPost,News
clay audiences signals summary --segment-id audseg_abc --since 2026-08-01 --signal-types JobPost --signal-ids sig_abc
```

- Use `signals list --entity-id` when the user names one record. Pass the numeric
  id from `clay audiences records search-ids`, its `--entity-type`, and an
  explicit `--since` (and optional `--until`). It returns that record's events newest first;
  continuation calls repeat `--entity-id` and `--entity-type` with the returned
  `--cursor`, without time filters.
- Use `signals list --segment-id` when the event payloads across a saved segment
  matter. It returns one cursor page with `data`, timestamps, signal id and
  type, and matched-entity count.
- Use `signals summary` for totals and first/last activity times. A summary can
  cover multiple `--signal-types` and optionally narrow to underlying `sig_…`
  ids with `--signal-ids`.
- Segment-scoped first-page reads require `--since` and `--signal-types`; bound
  them with `--until` where possible. Their continuation calls repeat
  `--segment-id` but pass only `--cursor` and optional `--limit`, without
  repeating filters.
- `--since` (inclusive) and `--until` (exclusive) filter on `activityTime` —
  when the underlying event happened — not `emittedAt`, when the signal event
  was emitted.
- `--signal-ids` takes the underlying `signal.id` shown by `clay signals get`,
  not that command's `td_…` trigger definition id.

## Error codes

Every command prints JSON on stdout and a typed error envelope on stderr. Exit
codes: `0` ok, `2` validation, `3` auth, `4` rate-limit, `5` network, `6`
not-found. `3` on an audiences command usually means Audiences is not enabled for
the workspace — that is a workspace-config answer for the user, not something to
retry.

`4` (`rate_limited`) means the workspace reached an Audiences rate limit.
Most Audiences requests share a workspace budget. `records get` has a separate
100,000-record allowance per workspace that replenishes at 100,000 records/hour,
charged by the number of IDs requested. Activity from another caller can affect when a retry succeeds.

Wait `details.retryAfter` seconds before retrying. If the retry is also rate
limited, follow its retry delay instead of repeatedly sending the request.
