# Writing an audience filter

Use this reference to create/update a saved audience or validate its filter.
For ad-hoc record searches and counts, prefer `--query` using `queries.md`,
including activity and signal criteria. Use an AST search only when DSL cannot
express the criteria or when checking the exact filter you will save.

A filter is a `ConditionalExpressionGroup` AST. Saved audiences and ad-hoc
`records search-ids` / `search-count` use this shape, but the Clay UI's filter
editor supports only a subset. `clay audiences create --help` carries the full node and
operator reference; read it once instead of guessing at the shape.

## Saved segment restrictions

**Search support does not imply saved-segment support.** A valid AST accepted by
`search-count` may not be supported by the segment editor. Save only filters the
frontend can faithfully represent and apply, including when updating or cloning
an existing segment. Unsupported clauses may be ignored by frontend record queries.

Read [Frontend AST filter support](frontend-ast-filters.md) when choosing a saved filter's
fields, operators, or collection shape. It lists the supported forms and their
limits, including the predefined “any of” exceptions.

If the proposed filter is unsupported, first try to rewrite it into a supported
shape that preserves the user's intended criteria. If no equivalent filter is
available, give a short, plain-language explanation: name the unsupported part,
propose a supported simplification, and say which additional records it could
include or which intended records it could exclude. Ask whether that change in
selection is acceptable before creating or changing the segment. If no useful
simplification exists, say so and ask what criteria the user wants to change.
Do not silently drop conditions or substitute a fixed cohort; use a fixed cohort
only when the user explicitly requests one.

Keep this to a few sentences, not a technical explanation or a list of unrelated
alternatives. Avoid AST jargon and repeated counts or status summaries. After
the user declines, briefly acknowledge and stop without repeating the limitation.

For example: “The segment editor can't require the title and date to match the
same task. I can use separate title and recency filters, but that could include
people whose matching task is older and whose recent task is unrelated. Is that
broader audience OK?”

The parts that cost the most time:

- **`key` + `dataPath` name a record field.** For record fields, `dataPath` is
  `[<root for the entity type>, "field", <fieldId>]` — see the entity-type table
  in `SKILL.md` for the root. `key` is the field id.
- **A filter is always rooted at people or companies, never deals** — and that is
  how you filter by deals. An `opportunity` `dataPath` is a cross-entity predicate
  _inside_ a people or companies filter, which is the supported way to ask any deal
  question; `--entity-type deals` itself accepts no `--filter`. See
  `custom_objects.md`.
- **`Empty`, `NotEmpty`, `True`, and `False` take no `value`.** Every other
  operator does. The relative-time operators (`WithinLast` / `WithinNext` and
  their `Not-` forms) take a numeric `value` plus `timeUnit` (`day` / `week` /
  `month`).
- **Match on nothing to match everything:**
  `{"type":"GroupOp","combinationMode":"And","items":[]}`.
- **Node `id`s are UI bookkeeping** — they are stripped, so never author them.

## Discover categorical values before filtering

Use `fields list-values` before filtering categorical fields instead of guessing
labels. Follow the value discovery and high-cardinality guidance in
`answering-data-questions.md`.

## Filter dates without guessing

Choose the field before the operator. For any request with a time constraint,
list the fields once with system fields included, then inspect only date
candidates:

```bash
clay audiences fields list --entity-type people --include-system > /tmp/people-fields.json
jq '.data[] | select(.dataType == "date") | {id, name, isSystemField}' /tmp/people-fields.json
```

Use the date field whose meaning matches the request. Workspace fields carry
business dates such as a form submission time or contract renewal date. The
Clay-managed `created_at` and `updated_at` fields mean record creation and
record update time; they are useful only when that is what the user asked for.
Do not substitute either system field merely because the intended field has
the wrong type.

**Date operators work only on a field whose `dataType` is `date`.** An ISO date
stored in a `text` field is still text. Do not try `WithinLast`, `After`,
`GreaterThan`, `StartsWith`, or other operator variants against it. That cannot
produce a reliable date query. Use another date-typed field with the right
meaning, or tell the user that this field must be converted/remapped to `date`
before it can be time-filtered accurately.

| User's time constraint                 | Operator             | Value                                                      |
| -------------------------------------- | -------------------- | ---------------------------------------------------------- |
| rolling past window ("last 7 days")    | `WithinLast`         | numeric `value` plus `timeUnit`: `day`, `week`, or `month` |
| rolling future window ("next 2 weeks") | `WithinNext`         | numeric `value` plus `timeUnit`: `day`, `week`, or `month` |
| before or after a specific instant     | `Before` / `After`   | ISO-8601 timestamp, e.g. `2026-09-01T00:00:00Z`            |
| field is populated or missing          | `NotEmpty` / `Empty` | no `value`                                                 |

`WithinLast` is a rolling duration from the current instant, not a calendar-day
interval. `Before` and `After` are strict. When the user names inclusive
calendar dates, set the `After` cutoff to the final representable instant before
the requested start, and set the `Before` cutoff to midnight after the requested
end. For example, August 24 through August 31 UTC uses `After`
`2026-08-23T23:59:59.999Z` and `Before` `2026-09-01T00:00:00Z`.

People created in the last 7 days:

```json
{
  "type": "GroupOp",
  "combinationMode": "And",
  "items": [
    {
      "type": "BinOp",
      "key": "created_at",
      "dataPath": ["contact_entity_field_values", "field", "created_at"],
      "operator": "WithinLast",
      "value": 7,
      "timeUnit": "day",
      "entityType": "CONTACT"
    }
  ]
}
```

Before trying another operator on a zero count, run a `NotEmpty` count on the
same field. A zero fill-rate means there is no data to filter; a nonzero
fill-rate plus a zero date count means the window may legitimately be empty.

## Node types

- `GroupOp` — combines child `items` with `combinationMode` (`And` / `Or`).
  Nestable, so mixed AND/OR logic is a group inside a group.
- `BinOp` — compares one field to a `value`: `{ key, dataPath, operator, value, entityType }`.
- `ColOp` — a collection/subquery: `{ key, dataPath, operator, condition, entityType }`,
  where `condition` is a `GroupOp` and `operator` is `AllItems` / `AnyItems` / `NoItems`.
  Signal and activity collections use `dataPath` rooted at `signal_events` or `activities`. Never wrap
  related-object predicates (e.g. `opportunity`) in a `ColOp` — those are plain `BinOp`s
  in the enclosing group (see `custom_objects.md`); the server rejects such a `ColOp`
  with a validation error. Another supported shape is UI-built source-sync-status:
  filters are `ColOp`s rooted at `*_entity_field_values` with an
  `external_source_sync_status_v3` path. Preserve the UI-generated source-specific shape; do not
  generalize it to arbitrary collections over record fields.
- `AggOp` — an aggregate over a group: `{ aggregation: { groupByPath, operator, value }, expression, entityType }`.

## Copy-paste starting point

People with no email:

```json
{
  "type": "GroupOp",
  "combinationMode": "And",
  "items": [
    {
      "type": "BinOp",
      "key": "email",
      "dataPath": ["contact_entity_field_values", "field", "email"],
      "operator": "Empty",
      "entityType": "CONTACT"
    }
  ]
}
```

Swap `email` for any field id from `clay audiences fields list`, and swap the
`CONTACT` / `contact_entity_field_values` pair for `ACCOUNT` /
`account_entity_field_values` to filter companies.

## Query email, meeting, or other activities (ad hoc only)

Read `clay audiences activities list` or `summary` to discover the returned
`activityTypeId`. It is distinct from the `activityType` enum (`email`, `meeting`,
etc.); never substitute that enum or infer record ids from the opaque `eventId`.
For distinct-account coverage, use `records search-ids` / `search-count --query`
with an activity relationship (see `queries.md`), then hydrate the matching records for the owner breakdown.
Summing event counts double-counts accounts with repeated touches.

Use `ColOp` on `["activities", "<activityTypeId>"]` with `AnyItems` (has a matching
activity) or `NoItems` (has none, including records with no activities at all).
`AllItems` is unsupported. The condition must be an `And` group of `BinOp`s for
exactly one activity type. Use `["activities", "activity_timestamp"]` for recency;
activity fields use `["activities", "fields", "<fieldId>", "<activityTypeId>"]`.

No email in the rolling last 30 days, replacing `<activityTypeId>` with the
discovered email type id:

```json
{
  "type": "GroupOp",
  "combinationMode": "And",
  "items": [
    {
      "type": "ColOp",
      "dataPath": ["activities", "<activityTypeId>"],
      "operator": "NoItems",
      "entityType": "ACCOUNT",
      "condition": {
        "type": "GroupOp",
        "combinationMode": "And",
        "items": [
          {
            "type": "BinOp",
            "dataPath": ["activities", "activity_timestamp"],
            "operator": "WithinLast",
            "value": 30,
            "timeUnit": "day",
            "entityType": "ACCOUNT"
          }
        ]
      }
    }
  ]
}
```

For **email OR meeting**, combine two `AnyItems` collections in an outer `Or`.
For **neither email NOR meeting**, combine two `NoItems` collections in an outer
`And`. Keep the target audience's existing filter in the outer `And` so the
result stays within the requested population. Validate with `search-count`,
but do not save these collection filters as segments.

## Filter by signal activity

Signal events captured on a record (see `SKILL.md`, "Signals write activities
onto records") are filterable through the `signal_events` dataPath root — this
is how "companies with a job posting in the last 30 days" is expressed, and it
is what the app's signal-based segments store.

For payload arrays such as funding-news topics, read **Primitive-array payloads**
below before querying; a News type/window clause alone includes every news topic.
The specific-signal results shape below is UI-supported. The compound payload
and rolling News topics examples are ad-hoc only; do not save those as segments.

Every example below is a whole filter, rooted at a `GroupOp` — `--filter` runs
`ConditionalExpressionGroup.safeParse`, so a bare `BinOp` or `ColOp` is rejected as
a `validation_error` before any request is made.

**Any event of a type within a window** — a `BinOp` whose `key` is the type's
aggregate-occurrences key and whose operator is a relative-time window:

```json
{
  "type": "GroupOp",
  "combinationMode": "And",
  "items": [
    {
      "type": "BinOp",
      "key": "signal_JobPost_aggregate_occurrences",
      "dataPath": ["signal_events"],
      "operator": "WithinLast",
      "value": 30,
      "timeUnit": "day",
      "entityType": "ACCOUNT"
    }
  ]
}
```

The key is `signal_<Type>_aggregate_occurrences` where `<Type>` is the
`signal.type` spelling from `clay signals list`: `JobChange`, `JobPost`,
`NewHire`, `News`, `Promotion`, `LinkedinPostMentions`, `PersonTopicIntent`,
`CompanyTopicIntent`, `WebsiteVisitorTracking`. `Custom` and `FakeSignal`
events are not filterable this way.

**Events from one specific signal (UI-supported shape)** — put the window clause and a `signal_id`
equality inside a `ColOp` over `signal_events`. The id is the `sig_…` value
(`signal.id` in `clay signals list` output — one of the few places that id,
rather than `td_…`, is what you need):

```json
{
  "type": "GroupOp",
  "combinationMode": "And",
  "items": [
    {
      "type": "ColOp",
      "dataPath": ["signal_events"],
      "operator": "AnyItems",
      "entityType": "ACCOUNT",
      "condition": {
        "type": "GroupOp",
        "combinationMode": "And",
        "items": [
          {
            "type": "BinOp",
            "key": "signal_JobPost_aggregate_occurrences",
            "dataPath": ["signal_events"],
            "operator": "WithinLast",
            "value": 30,
            "timeUnit": "day",
            "entityType": "ACCOUNT"
          },
          {
            "type": "BinOp",
            "dataPath": ["signal_events", "signal_id"],
            "operator": "Equal",
            "value": "sig_abc123",
            "entityType": "ACCOUNT"
          }
        ]
      }
    }
  ]
}
```

**Ad-hoc compound payload queries:** event payload predicates go inside the same `ColOp` condition as the window
clause — never beside it in the root group. Deeper `dataPath`s reach into the
event's data, e.g. `["signal_events", "data", "confidence"]` or
`["signal_events", "data", "jobPostData", "title"]`.

Clauses inside one `ColOp` condition lower to a **single** `signal_events` scan, so
they all have to hold for the **same event**. Two signal clauses sitting side by side
in the root group lower to **separate** scans, each free to match a different event —
so "a job post in the last 30 days" AND "title contains VP" would match a company
whose VP posting is two years old and whose recent posting is for an intern. Bind
them together instead:

```json
{
  "type": "GroupOp",
  "combinationMode": "And",
  "items": [
    {
      "type": "ColOp",
      "dataPath": ["signal_events"],
      "operator": "AnyItems",
      "entityType": "ACCOUNT",
      "condition": {
        "type": "GroupOp",
        "combinationMode": "And",
        "items": [
          {
            "type": "BinOp",
            "key": "signal_JobPost_aggregate_occurrences",
            "dataPath": ["signal_events"],
            "operator": "WithinLast",
            "value": 30,
            "timeUnit": "day",
            "entityType": "ACCOUNT"
          },
          {
            "type": "BinOp",
            "dataPath": ["signal_events", "data", "jobPostData", "title"],
            "operator": "Contain",
            "value": "VP",
            "entityType": "ACCOUNT"
          }
        ]
      }
    }
  ]
}
```

Payload shapes differ per signal type; read a real event's shape (or an existing
segment's filter) before authoring one, and always keep the aggregate-occurrences
clause in the condition so the scan stays scoped to that signal type and window.

### Primitive-array payloads with recency (ad hoc only)

For an array such as `newsData.newsTopics`, the `ColOp` path must name the full
array, and the element `BinOp` uses `["."]`. Put the type/window clause in the
**same array condition**; do not nest this inside a second `ColOp` or put the
window beside it at the root. Otherwise old fundraising news plus recent
unrelated news could qualify the record.

Fundraising news in the rolling last 30 days:

```json
{
  "type": "GroupOp",
  "combinationMode": "And",
  "items": [
    {
      "type": "ColOp",
      "dataPath": ["signal_events", "data", "newsData", "newsTopics"],
      "operator": "AnyItems",
      "entityType": "ACCOUNT",
      "condition": {
        "type": "GroupOp",
        "combinationMode": "And",
        "items": [
          {
            "type": "BinOp",
            "key": "signal_News_aggregate_occurrences",
            "dataPath": ["signal_events"],
            "operator": "WithinLast",
            "value": 30,
            "timeUnit": "day",
            "entityType": "ACCOUNT"
          },
          {
            "type": "BinOp",
            "dataPath": ["."],
            "operator": "Equal",
            "value": "Fundraising"
          }
        ]
      }
    }
  ]
}
```

A signal `ColOp` does compose with ordinary **field** predicates in the root group —
ICP fit AND recent signal activity can be queried together, and a
field predicate is evaluated against the record rather than an event, so there is no
event for it to disagree about. The rule above is only about two `signal_events`
clauses: those belong in one condition, not side by side. Validate with
`records search-count --filter` like any other filter.

## CLI counts do not validate frontend results

`records search-count --filter` evaluates the AST on the backend. With
`--audience-id`, it evaluates the saved segment's AST. Neither runs the frontend
cleanup that removes unsupported filters, so neither verifies the count shown
in the segment UI. Comparing DSL and AST counts cannot detect this mismatch.

Use CLI counts to inspect backend query results, not as a saved-segment
compatibility check. Establish frontend support from the filter shape instead.

## Copy a filter you know works

An existing audience can provide workspace-specific field references; `get`
returns the filter stripped of editor ids. It can still contain unsupported
clauses. Inspect the entire AST for frontend support before cloning it:

```bash
clay audiences get <audienceId> | jq .filter > /tmp/candidate-filter.json
```
