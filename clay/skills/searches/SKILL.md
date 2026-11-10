---
name: searches
description: Use to find net-new people/companies by employer, name or title, refine criteria and page results. Other filters route to searches-advanced.
allowed-tools: Bash(clay *), Bash(jq *), Bash(grep *), Read, Grep
---

# Clay search

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

Search finds net-new people/companies; use `audiences` for workspace records.

## Simple queries

Outside Sculptor's Search panel, use these patterns without the full reference when they
capture **every** criterion. In that panel, read its required DSL reference before querying.
Preserve lists/exclusions; add no unrequested filters. Otherwise read **`searches-advanced`
before querying**: geography/metro/HQ versus offices, industry, growth, size, similarity,
employer history, hiring, audiences, education, counts, per-company limits or unknown
fields. It routes to the full runtime reference. Never drop criteria to avoid it.

Syntax: `select from people|companies where <predicate>`. Double-quote strings;
parenthesize lists. `and` binds tighter than `or`; group alternatives. Text matching is
case-insensitive; `contains` matches tokens, not substrings. Omit the DSL `limit` unless
the user explicitly caps the total across all pages, so "show me more" can continue the
same search. For ordinary requested counts, use the executing tool's page-size `limit`
within its allowed maximum; fetch additional pages only as needed.
Translate ordinary terms to English; preserve proper names/IDs.

**Current employer + role:**

```text
select from people where clay.filter_to_companies(("stripe.com")) and experiences.any(is_current = true and job_title is_similar_to ("software engineer"))
```

Use supplied identifiers or confidently known household-name domains. The company
function belongs at the root. Keep title/seniority in **one current experience**;
neither is a people-root field.
For an uncertain employer name, replace the identifier function with
`company_name contains "Name"` inside that same experience; never guess a domain.

Person names use root-level `full_name contains "Person Name"`; no first/last-name fields.

Titles default to `job_title is_similar_to ("role")`; use only user-supplied roles,
not invented synonyms. Exact titles use `=` or `in (...)`; literal keyword requests
use `contains`, keeping exclusions with `not`. Lists mean OR; required co-occurring
words need AND. Quote full phrases. Keep title predicates inside experience.

Only filter seniority when requested: senior individual contributors use
`seniority = "Senior"`, not leadership. Complete experience values: `Founder`, `Owner`,
`Board Member`, `Partner`, `C-suite`, `VP`, `Director`, `Head`, `Manager`, `Senior`,
`Mid-level`, `Entry`, `Intern / In Training`, `Unknown`. Use `=`, `!=`, `in`, `not_in`;
leadership tiers require leadership intent. Not job-posting values.

**Specific companies:** one inclusion call, all supplied identifiers (at most 1,000):

```text
select from companies where clay.include_company_identifiers(("stripe.com", "https://www.linkedin.com/company/notionhq/"))
```

Do not substitute `domain =`, guess domains or fabricate LinkedIn slugs. Ambiguous
company names and "companies like X" require advanced identification guidance.

## Execute and page

Use the access method selected by `clay`. Discover operation schemas;
CLI equivalents are `clay searches query-mode create --query '<query>'`, then
`clay searches query-mode run <searchId> [--limit <n>]`. Create returns `searchId`, not
records; run returns `data`, `hasMore` and optional `periodQuota`.

**Forward-only iterator:** reuse its ID for the next page; no replayable cursor.
Page size is separate from total limit.
Read only enough pages to satisfy the current request; for an unspecified count, show
one page. On "show more", advance only when `hasMore` is true. Check quota before each
page and stop near exhaustion unless the user confirms continuation. Changed criteria
require a **new query retaining unchanged criteria**, not filtering the old page.

## Limits and failures

Follow `workflows-discover-actions/cost-and-budget.md`; keep routine checks internal.
Before a generic large search, suggest 2–3 supported narrowing options or a small limit
and wait for confirmation/narrowing. Skip for bounded requests. If `periodQuota` is
present, ask before planned N results leave `remaining − N` below 15% of `limit`;
continue only if confirmed, otherwise offer a smaller pull/stop. Skip absent quotas.

### Quotas

On `quota_exceeded` (HTTP 402), stop and read `searches-advanced` → Quotas before any
retry/report. Only an explicit per-request cap permits one smaller-page retry; never
shrink pages or recreate searches to evade other caps. Preserve its billing/support links.
For validation, server or rate-limit errors, read advanced reference/retry guidance
before correcting or retrying: a failed run may already have charged/counted its page.
Do not evade authentication or approval requirements by changing transports/restarting.

For enrichment or persistence, use `routines`: inspect the paginated routine list,
prefer managed routines and match actual input schemas. Search missing email/phone
is not proof enrichment is unavailable. Preserve shared cost, approval and batch rules.
