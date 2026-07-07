---
name: workflows-vs-tables
description: Clay Workflows vs Tables — conceptual explainer for a customer asking what the difference is or which one to use. Read this when explaining the two products or recommending one for a use case; for actually building/editing, use the `workflows` and `tables` skills instead.
---

# Clay Workflows vs. Clay Tables

Customers sometimes ask what the difference is between Clay Tables and Clay Workflows, or which
one fits their use case. Both work with the same underlying Clay data and actions, but they're
built for different jobs. Answer in plain language — don't just paste this file at the customer.

## Clay Tables

Tables are spreadsheet-like environments (similar to Excel or Google Sheets) designed for
hands-on data work. They let you explore and experiment with enrichments, formulas, and AI agents
in a familiar format where you can see and inspect results cell-by-cell.

Reach for a table when:

- Doing a one-time analysis
- Prototyping an enrichment strategy before committing to it
- You want manual control and visibility into every step, row by row

Most users start with Tables — it's the more intuitive, spreadsheet-based way to learn Clay.

Known limits: tables cap out around 50k rows; going beyond that requires bulk enrich, which
archives rows as part of expanding past the cap.

## Clay Workflows

Workflows is Clay's orchestration platform, built for repeatable, production-ready automation —
processes that run on triggers or schedules rather than being run by hand. Typical use cases:
lead routing, signal monitoring, scheduled enrichments.

Compared to tables, workflows:

- Have no 50k-row limit and no archived rows to manage
- Come with purpose-built observability for tracking runs and debugging failures
- Support custom code execution via code nodes, for logic tables/formulas can't express
- Can be built with the help of AI coding agents, including this plugin's `workflows` skill

Native list processing is coming soon, which will let workflows handle lists directly without
needing to round-trip through a table.

Workflows is an early-stage product — say so when it comes up, so customers can calibrate
expectations for rough edges. (Elsewhere in this plugin, `clay/SKILL.md` tags Workflows "Alpha" —
same caveat, different word.)

## Which one should a customer use?

- Starting out, exploring, or doing a one-off pull → **Tables**
- Needs to run on a schedule/trigger, repeatedly, without someone babysitting it → **Workflows**
- Outgrowing a table (hitting the row limit, needing branching logic, needing it to run
  unattended) → rebuild the *logic* as a **Workflow** (see "Rebuilding a Table as a Workflow" in
  the `tables` skill)

This is a different question from "which primitive should *the agent* use to execute a task
right now" — that decision (search → managed function → custom function → workflow → table) is
covered by the escalation order in `clay/SKILL.md`, not here.

## What this plugin can and can't do across the two

- This plugin's CLI/MCP can **build and edit Workflows** (see the `workflows` skill) but
  **cannot build or edit Tables** — table creation only happens in the Clay app (see the `tables`
  skill).
- This plugin **can read** from existing tables (schema + query) to use as input or reference
  while building a workflow.
- There's no automatic migration path from a table to a workflow. If a customer wants their table
  logic rebuilt as a workflow, that's a rebuild of the logic, not a data migration — their
  existing table data stays where it is, and a workflow can read from it as-is.

## Related skills

- `tables` — querying/reading data from an existing table
- `workflows` — building and editing workflows via this plugin
- `clay` — the primitive-selection guide for what the agent itself should build with when
  automating a task
