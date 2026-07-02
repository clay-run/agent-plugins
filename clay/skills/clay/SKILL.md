---
name: clay
description: Clay — start here. A table of contents for working with Clay and which skill to use for each thing — workflows (build automations), tables (query/export data), the CLI (ephemeral programmatic access), the Public API (build services on Clay), and feedback. Read this first to answer "what can I do with Clay?"
---

# Working with Clay

Clay is a GTM (go-to-market) data and automation product. This skill is a table of
contents: find what you want to do and go to that skill.

## Check what already exists before building

Don't jump straight to building a workflow. First see whether the job is already covered:

1. **An existing routine** — run `clay routines list` to see the workflows and functions
   already set up in this workspace. If one fits, run it (`clay routines …`) instead of
   rebuilding it.
2. **A direct CLI / API capability** — many tasks (querying a table, searching Clay's GTM
   database, etc.) are a single CLI command or API call, not a workflow. Skim `clay --help`
   and the table below.

Only build a **new** workflow when nothing existing does the job — i.e. you genuinely need
a new multi-step automation.

## Skills

| Skill | Use it for |
| --- | --- |
| `cli` | Ephemeral, programmatic access to Clay capabilities from a shell — run a routine, query a table, search, etc. |
| `routines` | Running a saved Clay function or workflow (a "routine") and fetching its results. |
| `public-api` | Building services and applications on top of Clay over HTTP. |
| `workflows` | Building and editing net-new Clay workflows (multi-step automations). |
| `tables` | Reading, querying, and exporting data from an existing Clay table. |
| `search` | Finding people, companies, or job postings in Clay's GTM database from a natural language query. |
| `clay-feedback` | Sending a bug report or product feedback to the Clay team. |

## First-time setup

Run the `setup` skill.
