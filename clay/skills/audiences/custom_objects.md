# Deals and other custom objects

Read this whenever the request touches **deals** or **opportunities** — including
any of the GTM phrasings in "Recognizing deal language" below.

**Query deals directly with the DSL `opportunities` root.** Use `count from
opportunities where ...` for a deal count and `select from opportunities where ...`
for deal IDs. See `queries.md` for DSL syntax. If the user wants the associated
people or companies instead, root the query there and filter by related deals.
The AST examples below describe that people/company filtering path.

## Ranking vague sales requests

"Largest opportunities" and "biggest deals" mean rank by `amount` descending.
Use a small top-N (for example, five) when no count is given and state the scope.
"Still in our pipeline" adds `is_closed = false`; "biggest wins" adds
`is_won = true`. Do not infer an owner filter from "my" alone: resolve a
workspace-specific owner field only when personal ownership is explicit.

Check `amount` once with `fields list --entity-type deals`: both `number` and
`currency` are numeric types. Then issue one sorted `search-ids` query and hydrate
only its IDs. A total count is optional for a highlights request.

For "lately", state a reasonable time window and filter on `close_date` before
ranking. For example, interpreting it as the last 30 days:

```bash
clay audiences records search-ids --query 'select from opportunities where is_won = true and close_date >= today() - interval 30 days and close_date < today() + interval 1 day order by amount desc' --limit 5
```

Missing close dates cannot establish a recent win. If this scope is empty, say
so; do not substitute all-time wins or record update dates for recent closes.
See `queries.md` for the DSL date grammar before constructing a query.

## What a deal is in Audiences

A deal is a **custom object** — a third record type alongside people and
companies. Opportunity is the only custom object type that exists today, so
"deal", "opportunity", and "custom object" all mean the same records.

| Where you are           | Spelling                                |
| ----------------------- | --------------------------------------- |
| CLI `--entity-type`     | `deals`                                 |
| CLI output `entityType` | `"deals"`                               |
| Filter AST `entityType` | `CUSTOM`                                |
| Filter `dataPath` root  | `opportunity`                           |
| CRM source              | Salesforce `Opportunity`, HubSpot deals |

Deals link to both companies and people: one deal belongs to an account and can
have several associated contacts (with CRM roles such as "Decision Maker").

To resolve deal-to-company mappings, first query `select from companies where opportunities.exists(id in (<deal_ids>))` for all selected deal IDs: if none match, report associations unavailable; otherwise resolve per-deal mappings with bounded parallel queries, retain each deal ID alongside its result, and bulk-fetch the company IDs without searching by deal/company name.

## Deals are read-only

Deals only enter a workspace through a CRM sync. There is no way to create,
update, or delete one from the CLI, and the `upsert-audiences-record` action
takes `ACCOUNT` or `CONTACT` only — it cannot write a deal. If a user asks to
create or edit a deal, say so and point them at their CRM; do not reach for a
workaround.

## What the CLI supports today

| Command                                 | `deals`?                                            |
| --------------------------------------- | --------------------------------------------------- |
| `audiences records get`                 | **Yes**                                             |
| `audiences records search-count`        | **Yes — filtered via DSL** (see below)              |
| `audiences records search-ids`          | **Yes — filtered via DSL** (see below)              |
| `audiences fields list`                 | **Yes**                                             |
| `audiences fields create/update/delete` | No — deals are read-only                            |
| `audiences fields segments`             | No — accepts only people/company field types        |
| `audiences list` / `create`             | No — audiences exist over people and companies only |
| `audiences signals list --entity-id`    | No — accepts only people/company records            |

Passing `--entity-type deals` to a "No" row exits 2 with `validation_error`.
`signals list --entity-id` forwards the type to the API and returns the API's
validation message. The other "No" rows reject it locally with
`must be one of: people, companies.` These errors are expected; do not retry or
work around them.
Use the exact plural `deals`; singular `deal` is invalid on every command.

```bash
clay audiences records search-count --entity-type deals              # how many deals in the workspace
clay audiences records search-ids   --entity-type deals              # their ids, --limit per page + .cursor
clay audiences records get --entity-type deals --ids 20384191        # field values, max 100 ids
```

`--archived` works on both search commands for deals, same as for people and
companies.

### `--entity-type deals` is the whole-population case, not the query case

The two search commands take `deals`, but with **no scope**: `--audience-id`, or a
`--filter` with any clauses in it, exits 2 with `validation_error` asking for an
unfiltered scope. This restriction applies to the AST path. To filter deals directly, omit
`--entity-type` and use `--query` with the `opportunities` root.

```bash
clay audiences records search-count --entity-type deals                          # ✅ every deal — the denominator
clay audiences records search-ids   --entity-type deals                          # ✅ every deal id — a full export
clay audiences records search-count --entity-type deals --filter ./won.json      # ❌ validation_error
clay audiences records search-count --entity-type deals --audience-id audseg_a   # ❌ validation_error
```

Use `--entity-type deals` for the two questions it answers well — the total deal
count (a denominator for any rate) and a full enumeration. For selective queries:

```bash
clay audiences records search-count --query 'count from opportunities where is_closed = false'
clay audiences records search-ids --query 'select from opportunities where is_closed = false' --limit 10
```

## Deal field ids

Every id here is usable both as a filter predicate (on the `opportunity` root) and
as a key in `records get` output. `fields list --entity-type deals` enumerates a
workspace's deal fields; these seven exist in **every** workspace, so you can write
filters against them without listing first:

| Field id           | Meaning                                          |
| ------------------ | ------------------------------------------------ |
| `opportunity_name` | Deal name                                        |
| `stage`            | Pipeline stage, as a CRM-specific string         |
| `amount`           | Deal value                                       |
| `close_date`       | Close date (actual once closed, expected before) |
| `opportunity_type` | Deal type, e.g. new business vs renewal          |
| `is_closed`        | Boolean — the deal has reached a terminal stage  |
| `is_won`           | Boolean — the terminal stage was a win           |

Three Clay-managed fields are filterable too — they are the UI's "Deal creation
date", "Deal last updated", and "Deal source":

| Field id           | Meaning                          |
| ------------------ | -------------------------------- |
| `created_at`       | When the deal record was created |
| `updated_at`       | When it last changed             |
| `origin_source_id` | Which sync brought it in         |

So "deals created since April" is a `created_at` predicate on the `opportunity`
root, same shape as any other deal filter.

### Date-window boundaries

Treat every date the user names as **inclusive by default**. "Since August 24"
includes August 24, and "from August 24 until August 31" includes both dates.
Only exclude a named date when the user explicitly asks to exclude it. Implement
an inclusive calendar range as a half-open machine interval by moving the upper
bound to the following date: August 24 through August 31 becomes
`August 24 <= date < September 1`. Use non-overlapping bounds for comparison
periods after translating the user's inclusive dates this way.

- An open-ended "since X" runs from the inclusive start through now. For a DATE
  field, cap it with `Before` midnight on the following calendar date so anomalous
  future-dated records cannot enter the result.
- `After` and `Before` are strict operators. For an inclusive start on a DATE
  field, set the `After` cutoff to the final instant before the start date; use
  `Before` at midnight on the exclusive end date.
- `WithinLast` is a rolling duration from the current instant, not a calendar-day
  interval. Use explicit bounds when the user names a calendar week or when
  DATE-valued records at midnight must include the whole first day.

`records get` returns the rest of the Clay-managed set as well
(`origin_source_type`, `sources`, `is_draft`, `external_source_sync_status*`).
Anything beyond those is a CRM property mapped into the workspace, and it varies
per workspace. Listing the deal fields is how you discover those ids and their
data types:

```bash
clay audiences fields list --entity-type deals > /tmp/deal-fields.json
jq -r '.data[] | "\(.id)  \(.dataType)  \(.name)"' /tmp/deal-fields.json
```

**Prefer the booleans over `stage`.** Stage strings come from the CRM and vary by
workspace (HubSpot emits `closedwon`, `presentationscheduled`; Salesforce uses
its own set). `is_won` / `is_closed` are normalized, so build on those and treat
`stage` as a label to display, not a value to guess.

## Recognizing deal language

These phrasings all mean deal records. When you see one you are in this file, and
choose the root based on the requested result: `opportunities` for deals,
or people/companies for their associated contacts/accounts.

| The user says                                                                                                             | Predicate                              |
| ------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| closed won, closed-won, won, we won, new logo, new customer, "our customers"                                              | `is_won` is `True`                     |
| closed lost, closed-lost, lost, we lost, lost to a competitor, no-decision                                                | `is_closed` `True` + `is_won` `False`  |
| open pipeline, open deals, active deals, in flight, live deals, still working                                             | `is_closed` is `False`                 |
| pipeline, pipegen, pipeline generation, pipeline coverage, "in the funnel"                                                | deals exist at all, usually open       |
| deal stage, sales stage, discovery, qualification, demo/presentation, proposal, quote, contract sent, negotiation, verbal | `stage`                                |
| deal size, deal value, ACV, ARR, MRR, TCV, bookings, contract value, average selling price                                | `amount`                               |
| close date, expected close, closing this quarter, slipped, pushed                                                         | `close_date`                           |
| forecast, forecast category, commit, best case, upside                                                                    | `stage` / `close_date` + `amount`      |
| win rate, conversion rate, sales cycle, days to close, velocity                                                           | `is_won` + `created_at` / `close_date` |
| new business, expansion, upsell, cross-sell, renewal, churn, downgrade                                                    | `opportunity_type`                     |
| deal owner, AE, account executive, rep, book of business                                                                  | a workspace-specific owner field       |

Quota, attainment, and net revenue retention are **derived** numbers — Clay
stores the deals, not the target. Compute them from `amount` and say what you
divided by.

## Filtering people or companies by their deals with AST

**Use this path for people/company results or saved audiences.** A people or companies
filter reaches into their deals with a cross-entity `BinOp` — `entityType:
"CUSTOM"` plus an `opportunity` `dataPath` root. Any deal field works as the
predicate, so "who has a closed-won deal", "accounts with a deal over $50k", and
"deals created since April" are all one search:

```json
{
  "type": "GroupOp",
  "combinationMode": "And",
  "items": [
    {
      "type": "BinOp",
      "key": "is_won",
      "dataPath": ["opportunity", "field", "is_won"],
      "operator": "True",
      "entityType": "CUSTOM"
    }
  ]
}
```

```bash
clay audiences records search-count --entity-type companies --filter ./won.json   # how many accounts
clay audiences records search-ids   --entity-type companies --filter ./won.json   # their ids
clay audiences records get --entity-type companies --ids <ids>                    # org_name, domain, …
```

Swap `--entity-type people` for the same filter to get the **contacts** on matching
deals instead of the accounts, and combine deal predicates with ordinary people or
company predicates in one `GroupOp` (won deals **and** `title` contains "VP").

**Pick the root by who the user is asking about.** Both roots see the same deals —
they differ in what comes back:

| Root        | Returns                            | Use when                                                                  |
| ----------- | ---------------------------------- | ------------------------------------------------------------------------- |
| `companies` | the accounts the deals belong to   | "which customers…", "accounts with open pipeline", anything account-level |
| `people`    | the contacts attached to the deals | "who should I email", "champions on won deals", anything person-level     |

For per-deal figures or matching deal IDs, use the DSL `opportunities` root.
Choose people/company results only when the user asks about associated contacts/accounts.

### `Role` is the one deal field with a different path

A contact's CRM role on a deal ("Decision Maker", "Champion") is not an
`opportunity` field. It lives on the relationship, so it uses a different root and
a `metadata` segment, and it only works with `--entity-type people`:

```json
{
  "type": "GroupOp",
  "combinationMode": "And",
  "items": [
    {
      "type": "BinOp",
      "key": "opportunity_role",
      "dataPath": ["opportunity_role", "metadata", "roles"],
      "operator": "Contain",
      "value": "Decision Maker",
      "entityType": "CUSTOM"
    }
  ]
}
```

It takes `Contain` / `NotContain` / `Empty` / `NotEmpty` only — no equality.

### Two deal predicates in one `And` group must be satisfied by the same deal

`is_won` `True` plus `amount` greater than 10000 matches an account only if a
single deal is both won _and_ over 10000 — an account holding a won small deal and
a separate large open one does **not** match. So "accounts with a won deal that
also have a big deal" is two searches whose ids you intersect yourself, not one
filter. State which reading you used when you report the answer; the difference is
easy to get wrong and changes the number.

### Never wrap deal predicates in a `ColOp`

The plain `And` group above is already "some deal matches all of these" — there is
no `AnyItems` / `AllItems` / `NoItems` layer to add. A `ColOp` with `dataPath:
["opportunity"]` is not a valid shape (`ColOp` is only for `signal_events` and
`activities`, see `filters.md`) and the server rejects it with a validation error.
Keep `opportunity` `BinOp`s directly in the `GroupOp`.

## What to say when the answer must be per-deal

Use `count from opportunities where ...` for the matching deal count, then
`select from opportunities where ...` for matching deal IDs. Read those IDs with
`records get --entity-type deals --ids ...`.

A people/company root counts contacts/accounts, not deals: an account with three
matching deals counts once. Never present that account count as a deal count.

- **Rank deals server-side with DSL.** For example,
  `clay audiences records search-ids --query 'select from opportunities where is_won = true order by amount desc' --limit 10`.
  Discover the amount or close-date field with `fields list --entity-type deals`
  first and check its `dataType`: amount must be a number or currency field for numeric ranking.
  If numeric values are stored as text, recommend fixing the Audiences field type
  before ranking; see `queries.md` for type checks and conversion caveats.
  Sorting supports one deal field, not sums of related deals per account.
  Results are bounded top-N IDs with no cursor, even if more deals match. Fetch
  only those IDs for details instead of walking all candidates and sorting locally.
  See `queries.md` for sorting limits and paired count queries.

And one hard limit:

- **No deal audiences.** `audiences create` rejects `deals`, so "save this as an
  audience" for a deal-shaped question means saving the **company** or **people**
  audience whose filter references deals. That audience stays live as deals change,
  same as any other.
