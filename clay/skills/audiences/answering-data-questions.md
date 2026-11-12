# Answering a question about the user's data

Read this when the user asks for a number, a list, or a fact about their people
or companies — "how many…", "what's the fill rate on…", "who has…", "look up X
for these accounts", "which customers…".

## Audiences is the default home for "their" data

When a user mentions people, companies, contacts, leads, accounts, or customers
without naming a surface, they mean **their workspace's records — Audiences**.
Go straight to `clay audiences`.

| The user means                                    | Surface                                                                                                                                                                                        |
| ------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| "my/our/their" people, companies, leads, accounts | **Audiences** (`clay audiences`)                                                                                                                                                               |
| net-new prospects not in the workspace yet        | When `search` is an available CLI command, the `searches` skill (Clay's GTM database)                                                                                                          |
| net-new results they want kept in Audiences       | When `search` and `routines` are available CLI commands, the `searches` skill, then a routine wrapping an upsert workflow (the `workflows` skill's `audiences.md`, then the `routines` skill). |
| a named table they built                          | the tables entry-point skill — only when they name one                                                                                                                                         |

Do **not** open `clay tables --help` to answer a question about people or
companies. Tables are a separate surface holding whatever the user built there;
they are the right answer only when the user names a table.

## Read what exists before you enrich

**If the answer could already be a field in Audiences, read it. Only reach for an
enrichment when the data genuinely isn't there.** Enrichments cost credits and
tens of seconds per record; `search-count` computes the count server-side without
enrichment. Getting this order backwards spends the user's money to rediscover
data they already have.

The sequence:

1. **Resolve the fields.** Use the default IDs documented in `SKILL.md` for
   standard fields. For custom or ambiguous fields, list fields once and save
   the output — do not re-run it to slice the response a different way.

   ```bash
   clay audiences fields list --entity-type people --include-system > /tmp/people-fields.json
   jq -r '.data[] | "\(.id)  \(.dataType)  \(.name)"' /tmp/people-fields.json
   ```

2. **Check coverage when it affects the answer.** Before relying on an unfamiliar
   field, or diagnosing zero matches, check whether it is populated. Read
   `queries.md` before writing DSL. For example:

   ```bash
   clay audiences records search-count --query 'count from people where title is_not_null'
   ```

   Fetch a total count too if the user needs a fill-rate percentage. A simple
   request with known fields need not start with a separate coverage audit.

3. **Discover categorical values before filtering.** For fields expected to
   have low cardinality, such as job title, department, persona, industry,
   or seniority, use `fields list-values` to get the available values and
   counts instead of guessing enum labels or testing every synonym.

   ```bash
   clay audiences fields list-values title --entity-type people
   ```

   Call this command directly; no DSL query is needed. Results include up to
   50 values by default; request more only when needed with `--limit` (maximum
   24,999). These are observed values, not a predefined enum.
   Check `truncated` before treating the vocabulary as complete. Do not sample
   or enumerate records with `search-ids` and `records get` to discover field
   values. Counts from `list-values` cover the workspace's entity type; retain
   the user's original audience or filter scope when counting matches for the
   chosen values.

   If cardinality is high or the result is truncated, inspect the field's
   `dataType` and meaning. Check whether it is incorrectly typed, whether a
   different categorical field is more appropriate, or whether a numeric/date
   range or targeted predicate would answer the question. High cardinality alone
   does not prove a type error. Explain any remaining limitation or ambiguity;
   never fall back to reading all records, even to obtain an exhaustive taxonomy.

4. **Then** answer the question, or — if the field is sparse or missing —
   recommend an enrichment (below).

A fill rate is also the fastest way to tell an empty field from a wrong filter.
When a filter returns 0, check whether the field is populated at all before
assuming the AST is broken; that ambiguity is what makes people brute-force
operator variants.

## Field names are ambiguous — resolve it with fill rates, then ask

Workspaces accumulate several fields that look like the same thing ("Lead
Scoring", "Contact Score", "ICP Fit Score"). Do not pick one silently, and do not
guess from the name.

Pull the fill rate and data type for each candidate, then put the choice to the
user with those numbers attached — "Contact Score is numeric and populated on
8,412 people; Lead Scoring is text and populated on 300. Which do you mean?" The
counts usually make the answer obvious, and they take one call each.

Watch the entity type too: a field can exist on companies and not on people. That
is a **data gap to report**, not something to work around by guessing at a
cross-entity filter.

## When a lot of the data is missing

Say so plainly, with the number, and offer to fill it — do not quietly answer
from the populated subset as though it were the whole set.

> Phone is populated on 1,204 of 9,780 people (12%). I can answer for those
> 1,204, or we can enrich the rest first. Which do you want?

If they want it filled:

- **Stay within the authorized scope.** Never start an enrichment on your own initiative.
  Follow the shared cost policy in `workflows-discover-actions/cost-and-budget.md` for cost disclosure and significant-spend
  confirmation; ordinary authorized enrichments do not need a cost-only check-in.
- **In a workflow context, the answer is a workflow**: one that reads the records
  missing the field, runs the enrichment, and writes the result back with
  `upsert-audiences-record`. Start with that shape — trigger on an audience of
  the records missing the field, enrich, upsert — and build the reversible draft
  incrementally. A request to analyze missing data alone does not authorize the enrichment
  run. See the `workflows` skill's `audiences.md`
  for the trigger and node mechanics.
- The audience of records missing the field is itself the input: an `Empty`
  filter on that field, saved with `clay audiences create`, becomes the
  workflow's trigger.

## Don't do these

Each of these showed up in a real session and cost 10-45 seconds for nothing:

- **Brute-forcing filter variants in a shell loop** (`for op in NotEmpty GreaterThanOrEqual …`).
  Read `filters.md` first; the operator rules are there, including which operators
  take no `value`.
- **Re-running `fields list` two or three times** to grep, head, and parse it
  differently. Write it to a file once.
- **`python3 -c` against the skill markdown** to extract field ids. The docs are
  for you to read; the ids come from `fields list`.
- **Reading the skill file only after the failures.** `queries.md`, `filters.md`, and
  `custom_objects.md` are cheaper than one failed filter.
- **Retrying a `validation_error` unchanged.** Exit 2 means the request was
  malformed — re-read the shape, don't re-send it. `--entity-type deals` on a
  command that rejects deals is the expected answer, not a flake.
  `custom_objects.md` has the table of what deals do and don't reach.
- **Retrying an exit 4 immediately.** `rate_limited` is the command's per-minute
  budget, not a flake: sleep `details.retryAfter` seconds, then send the same call
  again. Tight retries just collect more 429s.
- **Paging `search-ids` to count records.** `search-count` answers "how many" in
  one call; a paging loop over `search-ids` spends many calls — plus the
  rate-limited retries it runs into — for the same number.

## Workspace field fill rates

For a people or company field coverage audit, use
`clay audiences fields list --entity-type people --include-fill-rates` (or `companies`).
This returns coverage for all listed fields together; do not issue a count query per field.
`fillRate` contains `percentage` (0–100), `recordsCovered`, and `totalRecords`.
A null `fillRate` means coverage is unavailable, not that the field is empty.
`fillRatesStale` indicates cached coverage awaiting refresh. Coverage alone does not
establish that a field is safe to delete; check dependencies before proposing deletion.
