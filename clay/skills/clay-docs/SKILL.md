---
name: clay-docs
allowed-tools: WebFetch(domain:www.clay.com), WebFetch(domain:university.clay.com), WebFetch(domain:trust.clay.com), WebFetch(domain:developers.clay.com)
description: Use when the user asks a Clay product question — how a feature works, whether Clay supports or integrates with something, what plans include, security/compliance, or what's new — and the answer isn't operational guidance another skill owns. Answer from Clay's live public documentation, fetched and cited, never from memory.
---

# Clay product documentation

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

Clay's public documentation is the source of truth for product questions. Your training
data about Clay is stale and incomplete: features ship weekly, integrations are added
and renamed, and plans change. Answering a Clay product question from memory risks
telling the user something that is no longer true, or denying something that now exists.

**The rule: fetch a live doc page, answer from what it says, and cite its URL.** If you
cannot find the answer in the docs, say so plainly — "I couldn't find this documented".
Never fill the gap by guessing.

## Not this skill

- **Doing things** (run a search, query a table, build a workflow) — use the area skill
  (`searches`, `tables-cli`, `workflows`, …). This skill answers questions, it does not
  operate Clay.
- **Live workspace state** — credit balances, quotas, plan limits in effect for this
  workspace: use `credits-quotas-plans`. This skill covers what plans and pricing _are_
  publicly, not what this workspace has.
- **API and CLI reference** — endpoints, schemas, flags: the `public-api` and `cli`
  skills point at <https://developers.clay.com/llms.txt>.
- **Something looks broken** — use `clay-feedback`.

## Docs map

Start from the most specific hub that matches the question:

| Question is about                                                            | Fetch                                                                         |
| ---------------------------------------------------------------------------- | ----------------------------------------------------------------------------- |
| How a feature works (find, enrich, transform, scraping, AI, export, signals) | <https://university.clay.com/docs> — the product docs hub, organized by topic |
| Whether Clay integrates with a specific tool                                 | <https://www.clay.com/integrations> — the catalog; tool pages hang off it     |
| Plans and pricing                                                            | <https://www.clay.com/pricing>                                                |
| Common product questions                                                     | <https://www.clay.com/faq>                                                    |
| GTM tactics and playbooks built on Clay                                      | <https://www.clay.com/claybooks>                                              |
| Prebuilt table templates                                                     | <https://www.clay.com/templates>                                              |
| What a GTM term means                                                        | <https://www.clay.com/glossary>                                               |
| What shipped recently                                                        | <https://www.clay.com/changelog>                                              |
| Security, compliance, subprocessors                                          | <https://trust.clay.com>                                                      |
| Structured learning (courses, lessons, certifications)                       | <https://university.clay.com/courses>                                         |
| End-to-end use-case walkthroughs                                             | <https://university.clay.com/use-case-templates>                              |

## Finding the right page

1. Pick the closest hub from the map and fetch it with your web fetch tool. Hubs link
   to their leaf pages; follow the link that matches the question and fetch that. One
   caveat: the University docs hub leans toward per-integration reference pages, while
   conceptual "how does X work" content (waterfalls, credits, signal types) lives in
   lessons at `university.clay.com/lessons/<slug>` — when the hub surfaces only
   integration pages, go to the sitemap (step 3) instead of digging deeper.
2. For an integration, fetch the catalog and follow its link for the tool. Tool pages
   live at `/integrations/<category>/<slug>` and the category is not guessable, so do
   not construct URLs by hand — and a 404 on a guessed URL does not mean unsupported.
3. Find lessons through <https://university.clay.com/sitemap.xml>. It is large enough
   that a summarizing fetch tool can silently miss entries, so when you have a shell,
   grep a raw fetch instead: `curl -sL <sitemap-url> | grep -i <keyword>`. Skip `/fr/`
   entries — they are French duplicates.
4. When hub navigation dead-ends or a page you expected is missing, use web search
   scoped to the docs (`site:university.clay.com` or `site:www.clay.com`) to locate a page,
   then fetch it. Never answer from a search snippet alone.

If your environment has no web fetch tool, fetch with `curl -sL <url>` instead. If you
cannot fetch at all, say you can't verify against the docs and link the user to the
relevant hub URL rather than answering from memory.

## Answering

- Cite the page URL with every answer so the user can read the source.
- Report what the page says, in its terms. Do not extrapolate a capability the page
  does not state, and do not present an inference as documented fact.
- Pricing: state numbers only from a page fetched this session, and say plans change —
  link <https://www.clay.com/pricing> as the current source. The page's interactive
  tier sliders flatten badly into fetched markdown, so present dollar figures as
  "starts at" rather than exact.
- University `/docs/...` pages are product reference; `/lessons/...` and claybooks are
  educational content that can lag or generalize. When they disagree, report both with
  their sources instead of picking one.
- A capability you cannot find documented is "not documented", not "not supported" —
  unless a page says it is unsupported. Say what you checked, and don't volunteer a
  support handoff for a capability gap — the `clay` skill's escalation rules say when
  support enters.

## Known unsupported

Clay does not offer X (formerly Twitter) data sourcing, scraping, or enrichment — no
follower lists, profile data, posts, or mentions. Say so directly — this answer needs
no fetch and no citation, and it overrides the fetch-first rule. Do not search the
docs for a workaround.
