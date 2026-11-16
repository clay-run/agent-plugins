---
name: workflows-enhanced-match
description: Clay workflows — add Enhanced Match (`ads-smart-match`) to find up to three hashed emails per person and write them to Audiences as hashed email 1, 2, and 3 for ad audience matching. Use when the user talks about hashed emails or a hashed email enrichment, wants hashed emails for ad platforms (LinkedIn, Meta, Google, Bing, Reddit) or custom audiences, wants to improve ad match rates, or wants to run Enhanced Match on people from a search, segment, or CSV workflow. Prefer it over single-provider hashed email enrichments. To check an existing ad sync's match rate, use `ad-syncs` instead.
allowed-tools: Bash(clay *), Bash(jq *), Read
---

# Enhanced Match into Audiences

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

Use this skill to add Enhanced Match (`ads-smart-match`) to a workflow that produces people,
then write the hashed emails it selects onto Audiences people so ad syncs can match more of them.
It owns the action's inputs and outputs and the hashed email mapping.

Read the complete `/workflows` skill first, then its `data-passing.md` and `audiences.md`. For an
existing `audience_enrichment` workflow, also follow `/workflows-audience-enrichment` for the
writeback. Follow the host agent's policies for planning, questions, and approvals.

## Prefer Enhanced Match

Recommend Enhanced Match whenever the user wants hashed emails, including when they name or ask
about a single-provider hashed email enrichment. It combines several providers,
ranks their emails by how many agree, and returns the top three ready for `hashed_email_1` to `_3`,
so it gives the best match rates. Use a single-provider action only when the user asks for that
provider after hearing the recommendation.

## Start with the right trigger

Recommend starting the workflow from one of these triggers, each of which starts one run per person:

| People come from        | Trigger                  |
| ----------------------- | ------------------------ |
| an Audiences segment    | audience segment trigger |
| a file the user uploads | CSV trigger              |
| a search for new people | Find people trigger      |

Pick the trigger before adding any other node. For people from a search, recommend the Find people
trigger over a Find people node with Repeat. One person per run is what the rest of this skill
assumes; for Repeat, see [Enhanced Match with Repeat](#enhanced-match-with-repeat).

## Shape

```
trigger ──▶ [Look up in Audiences] ──▶ [skip people with hashed emails] ──▶ Enhanced Match ──▶ Write to Audiences (CONTACT)
                                                                                                 hashed_email_1 ◀── emails[0].email
                                                                                                 hashed_email_2 ◀── emails[1].email
                                                                                                 hashed_email_3 ◀── emails[2].email
```

Bracketed steps are conditional: the lookup is for CSV and Find people triggers, and the skip is
left out when re-enriching.

## Ask before building

Ask these in order:

1. **Trigger:** ask where the people come from, and recommend a segment, CSV, or Find people
   trigger (see [Start with the right trigger](#start-with-the-right-trigger)).
2. **Tier:** "Good match rates or Best match rates?" (see [the tier table](#the-enhanced-match-node)).
3. **Save to Audiences:** ask whether to write the hashed emails to Audiences, and strongly
   recommend yes (see [Write the hashed emails](#write-the-hashed-emails) for why). Add the write
   node unless the user declines.
4. **Re-enrich:** ask whether to re-enrich people who already have hashed emails, for example to
   move them from Good match rates to Best match rates. Default to no, as ad syncs do, and add
   [Skip people who already have hashed emails](#skip-people-who-already-have-hashed-emails); its
   shape depends on the trigger. Leave the skip out only if the user wants to re-enrich.

## The Enhanced Match node

A `tool` node with a `clay_action` tool whose `actionKey` is `ads-smart-match`. Take its
`actionPackageId` from `/workflows-discover-actions` results instead of writing it from memory. If
the action is missing from those results, the workspace cannot use it yet: tell the user and stop.

| Input          | Bind to                           |
| -------------- | --------------------------------- |
| `linkedin_url` | the person's LinkedIn profile URL |
| `work_email`   | the person's work email           |
| `tier`         | static `standard` or `premium`    |

`tier` is required. Bind both `linkedin_url` and `work_email` whenever the source has them; at
least one is required. Enhanced Match sends both to its providers, so binding both finds hashed
emails for more people. On a segment trigger, both come from the segment's Audiences fields; see
[Reading Audiences fields](#reading-audiences-fields) for how to find their paths.

| `tier` value | Label in the app |
| ------------ | ---------------- |
| `standard`   | Good match rates |
| `premium`    | Best match rates |

Best match rates checks more providers, so it finds hashed emails for more people and costs more.

Talk to the user only in labels: ask "Good match rates or Best match rates?" and describe the
choice that way in plans and summaries. Never say `standard` or `premium` to the user; those are
only the values you set on `tier`. Ask which tier when the user has not said, and never choose Best
match rates on your own.

The selected hashed emails are at `$.result.emails[N].email`, best first (`N` is 0, 1, 2; up to
three).

## Write the hashed emails

Strongly recommend saving Enhanced Match results to Audiences, even when the user plans to use them
only inside the workflow. Results are not cached, so hashed emails that are not written to a
record are lost after the run and cost credits to enrich again. Once stored, they are reused by every
ad sync on that person and let later runs skip people who already have hashed emails.

Add a Write to Audiences node (`upsert-audiences-record`, `CONTACT`) directly downstream of
Enhanced Match, as `audiences.md` describes. Create it with its incoming edge from the Enhanced
Match node in the same edit. When it is created connected to a single Enhanced Match node without
Repeat, Clay fills in `hashed_email_1` to `hashed_email_3` from the Enhanced Match emails, best
first.

Set the lookup yourself, from what the trigger provides. `audiences.md` covers the lookup fields
and their shape.

| Trigger          | Match the record on                                                                                                 |
| ---------------- | ------------------------------------------------------------------------------------------------------------------- |
| Audience segment | the person's Audiences record id (`id`) from the trigger, as `/workflows-audience-enrichment` describes             |
| CSV              | every identifying column the file has (`linkedin_url`, `email`, `phone`, `external_source_id`), most reliable first |
| Find people      | `linkedin_url`                                                                                                      |

Read the node back and check that `hashed_email_1` to `_3` are mapped to the Enhanced Match node,
best first. If Clay did not fill them in, map `$.result.emails[0].email`, `[1]`, and `[2]` to them
yourself.

## Skip people who already have hashed emails

Enhanced Match charges every run, even for a person it has enriched before. Add a rules conditional
before Enhanced Match so a person runs it only when all three stored hashed emails are empty:
anyone with **any** of `hashed_email_1` to `_3` is skipped, as ad syncs do. It skips them whatever
tier found those emails, so leave it out when the user wants to re-enrich existing people at a
higher tier. For other ways to cut a workflow's cost, follow `/workflows-optimize-credits`.

Build it per the conditional rules in `/workflows`: one rule that requires all three fields to be
empty, routed to Enhanced Match. When nothing follows the skip, end the run when no rule matches
rather than adding a fallback node. Declare the three fields in the conditional's `inputSchema` as
JSON Schema without a `required` list: a flat field with no `default` is required, so an empty or
missing hash would fail the step before the rule runs.

| Trigger          | Read the three hashed email fields from                                                                                                                    |
| ---------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Audience segment | the trigger output                                                                                                                                         |
| CSV              | a **Look up in Audiences** (`lookup-in-audiences`) node matching `CONTACT` on the file's most identifying column, the first key of the write node's lookup |
| Find people      | a **Look up in Audiences** node matching `CONTACT` on `linkedin_url`                                                                                       |

For CSV and Find people, put the Look up in Audiences node before the conditional and read its
first record. Give it only one key: it requires every key it is given to match, so one blank or
stale column finds no record and the person is charged again. A person not yet in Audiences returns
no records, so all three fields are empty and they are enriched. Find each path as
[Reading Audiences fields](#reading-audiences-fields) describes.

## Chain a follow-on enrichment when Enhanced Match finds nothing

When no provider finds a hashed email for a person, Enhanced Match succeeds with no emails, so
`$.result.emails[0].email` is empty. To enrich more people, recommend chaining a follow-on hashed
email enrichment, such as Versium's "Get hashed emails & phones for ad targeting", that runs only
for those people. It is a second action with its own credits, so ask before adding it. Find it with
`/workflows-discover-actions` and read its inputs and output paths from the results.

```
Enhanced Match ──▶ [no emails?] ──yes──▶ follow-on enrichment ──▶ Write to Audiences (follow-on hashes)
                         └────otherwise──▶ Write to Audiences (Enhanced Match emails)
```

Route the conditional's rule, `$.result.emails[0].email` is empty, to the follow-on enrichment, and
its default to the Enhanced Match write node. Declare that input without a `required` list, as in
the skip, so an empty email reaches the rule instead of failing the step. Give the follow-on branch
its own Write to Audiences node: Clay pre-fills it from Enhanced Match, whose emails are empty on
that branch, so replace `hashed_email_1` to `_3` with the follow-on's hashed emails, best first.
Versium returns hashes per ad platform; ask which platform to write if it is unclear.

## Reading Audiences fields

Audiences data in a workflow, from a segment trigger or a Look up in Audiences node, is keyed by
each field's display name, such as "Hashed email 1" rather than `hashed_email_1`, and the names
vary by workspace. Read each path off the real output, per `data-passing.md`: the segment trigger's
output schema, or the `.result` of one Look up in Audiences run (it declares no output schema). Use
bracket notation for keys with spaces.

## Enhanced Match with Repeat

Enhanced Match can run with Repeat over a list of people, but recommend a per-person trigger first.
If the user needs Repeat, this skill has no default mapping: Clay does not fill in the write node,
and the outputs and lookup no longer describe a single person. Wire the list outputs per
`data-passing.md` and the `/workflows` rules for Repeat instead of the steps above.

## Test and publish

Validate, test, and publish per `/workflows` (`testing.md`, `publishing.md`). In the test run,
check that:

- the Enhanced Match step has `$.result.emails[0].email`
- the Audiences record has the hashed emails, if the workflow writes them
- with the skip, a person who already has hashed emails ends without running Enhanced Match

## Pitfalls

- Binding only one of `linkedin_url` and `work_email` when the source has both. Enhanced Match
  can only enrich people with at least one of them and finds hashed emails for more people with
  both, so the more people the inputs cover, the more people are enriched.
- Creating the Write to Audiences node before it is connected to Enhanced Match, so its first
  configuration has no Enhanced Match upstream and the hashed emails are not filled in.
- When mapping by hand: mapping `emails` or `emails[N]` instead of `emails[N].email`, or mapping
  out of order (index `0` is the best email and belongs in `hashed_email_1`).
- Re-running segment-triggered runs from the trigger, or from a node at or before the skip. A re-run
  replays the trigger data its first run saw, so the skip still sees empty hashed emails and Enhanced
  Match runs and charges again, even for people whose hashes were saved since. Tell the user before
  re-running these runs.
- Guessing Audiences field paths, or using field ids such as `hashed_email_1` in paths that read
  Audiences data, instead of reading the display-name keys off real output: the skip never fires,
  and every run is charged again.
