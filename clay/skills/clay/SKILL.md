---
name: clay
description: Clay — start here. A table of contents for working with Clay and which skill to use for each thing — workflows (build automations), tables (query/export data), the CLI (ephemeral programmatic access), the Public API (build services on Clay), and feedback. Read this first to answer "what can I do with Clay?"
---

# Working with Clay

Clay is a GTM (go-to-market) data and automation product. This skill is a table of
contents: find what you want to do and go to that skill.

## How to work

Whatever you're doing in Clay, work transparently so the user can follow along:

- **Narrate as you go.** Say what you're about to do and why, then what happened —
  in plain language, referring to things by their human-readable names.
- **Summarize, don't dump.** Turn raw command output (JSON, `jq`, `diff`) into a
  short takeaway, table, or count. Reserve raw output for when the user asks.

## Choosing the right primitive

Clay exposes three core primitives (callable from the plugin/CLI/MCP/API):

| Primitive | What it's for |
|-----------|---------------|
| **Searches** | Find companies, people, and jobs from natural-language queries |
| **Routines** | Run Clay-managed functions, custom functions, and Workflows |
| **Tables** (Enterprise) | Query **existing** Clay tables only — you **cannot** create tables programmatically |

Follow this escalation order — reach for the earliest option that fits:

1. **Search** — need a list of people/companies? Start here (it's a primitive, not a routine).
2. **Clay-managed function** — the default for standard enrichment (work email, phone, job
   title, company domain, tech stack, funding, etc.). Check the catalog (`clay routines list`)
   **before** building anything — a managed function almost certainly exists for common GTM
   enrichment tasks.
3. **Custom function** — your team's reusable logic for things no managed function covers
   (account scoring, inbound routing, CRM cleanup, etc.). **Custom functions cannot be built
   from the CLI/MCP/API** — they can only be **invoked**. If a task needs a *new* custom
   function, surface that to the user; it must be created in the Clay app.
4. **Workflow (Alpha)** 🧪 — multi-node flows built from a code editor or the CLI. **Only use
   when a function genuinely can't do it**: embedded custom code, >50k-row batches, step-by-step
   run inspection, or inputs from diverse sources stitched together. **Workflows are an Alpha
   feature** — whenever you use, build, or edit a Workflow, tell the user up front so they can
   calibrate expectations.
5. **Tables** — query data from an existing table. You **cannot** create new tables through the
   plugin/CLI/MCP/API; if a task needs a new table, surface that to the user.

## Cost & budget

Before running a credit-consuming routine, check its per-item `estimatedCreditCost`
(`clay routines get <id>`) against the remaining workspace balance (`clay credits`). See the
`routines` skill for how to size a run against the balance.

## Skills

| Skill           | Use it for                                                                                                    |
| --------------- | ------------------------------------------------------------------------------------------------------------- |
| `cli`           | Ephemeral, programmatic access to Clay capabilities from a shell — run a routine, query a table, search, etc. |
| `routines`      | Creating a routine from an existing function/workflow, running a saved routine, and fetching its results.      |
| `public-api`    | Building services and applications on top of Clay over HTTP.                                                  |
| `workflows`     | Building and editing net-new Clay workflows (multi-step automations).                                         |
| `tables`        | Reading, querying, and exporting data from an existing Clay table (creating tables is not supported).         |
| `workflows-vs-tables` | Explaining the conceptual difference between Workflows and Tables to a customer, or which one fits their use case. |
| `search`        | Finding people or companies in Clay's GTM database from structured filters.                                   |
| `clay-feedback` | Sending a bug report or product feedback to the Clay team.                                                    |

## If another Clay MCP is connected

If `clay-for-reps` (the Clay MCP for sales reps) is also connected in your session,
ignore its tools entirely. That server is designed for interactive conversational prospecting
in chat apps (ChatGPT, Claude.ai) — it shares the same Clay workspace but is a completely
different product. Use the `clay` CLI and these skills for all automation, data enrichment,
and GTM operations.

## First-time setup

Run the `setup` skill.
