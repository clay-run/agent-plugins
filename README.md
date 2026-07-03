# Agent Plugins for Clay

Build with Clay in your AI coding agent — skills, MCP tools, and the Clay CLI.

## Installation

### Claude Code

```
/plugin marketplace add clay-run/agent-plugins
/plugin install clay@clay-plugins
```

### Codex

```
codex plugin marketplace add clay-run/agent-plugins
```

Then open **Plugins** and install **clay**.

### Cursor

Teams/Enterprise: Settings → Plugins → Add Marketplace → Import from Repo → `clay-run/agent-plugins`.

Otherwise (local install): the repo root is a *marketplace*, so clone it and copy the plugin itself — the `clay/` folder, which holds the plugin manifest — into your Cursor plugins dir, then reload Cursor:

```
git clone https://github.com/clay-run/agent-plugins.git
cp -R agent-plugins/clay ~/.cursor/plugins/local/clay
```

## Configuration

The `clay` CLI and the Clay MCP server both authenticate with a Clay API key. Create one in Clay under **Settings → Account** (the workspace is resolved from the key — there is no workspace id to set), then expose it as `CLAY_API_KEY`:

- **Claude Code** — run the bundled `setup` skill, which saves the key and verifies it with `clay whoami`.
- **Codex / Cursor** — export it in your shell so both the CLI and the MCP server read it:

  ```
  export CLAY_API_KEY="<your key>"
  ```

Verify with `clay whoami` — exit 0 prints your user and workspace; exit 3 means the key is missing or invalid.

## Using the `clay` CLI

In **Claude Code** the bundled `clay` CLI is on the agent's PATH automatically. **Codex and Cursor do not add a plugin's `bin/` to PATH** — the simplest fix is to ask the agent to run the bundled **`setup` skill**, which installs `clay` for you (no npm). To do it by hand, drop a forwarder — *not* a symlink, since the launcher locates its own files by path — into a directory on your PATH:

```
mkdir -p ~/.local/bin
launcher="$(find ~/.codex ~/.cursor ~/.claude -type f -path '*/bin/clay' 2>/dev/null | sort | tail -1)"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$launcher" > ~/.local/bin/clay
chmod +x ~/.local/bin/clay
```

The CLI still needs `CLAY_API_KEY` in the environment (see above).

## Choosing the right Clay primitive

> **Read the docs first:** [claydevelopers.mintlify.app](https://claydevelopers.mintlify.app/) — start with [Choose the right primitive](https://claydevelopers.mintlify.app/). This is a quick decision guide; the docs are the source of truth.

Clay exposes three **core primitives** (callable from the plugin/CLI/MCP/API):

| Primitive | What it's for | Docs |
|-----------|---------------|------|
| **Searches** | Find companies, people, and jobs from natural-language queries | [homepage](https://claydevelopers.mintlify.app/) |
| **Routines** | Run **Clay-managed functions**, **custom functions**, and **Workflows** | [routines](https://claydevelopers.mintlify.app/routines/clay-managed-functions) |
| **Tables** (Enterprise) | **Query existing** Clay tables only — **you cannot create tables** programmatically | [homepage](https://claydevelopers.mintlify.app/) |

> Most teams start with **Searches → Routines**: find the right records, then enrich them with a Clay-managed function.

Within **Routines**, reach for the earliest option that fits. Don't build new when something ready-made exists.

### 1. Searches — *find the rows* (a primitive, not a routine)

Find a **list of companies or people** (the input list). The starting point, not enrichment — Search *first*, then enrich.

- "SaaS companies in NYC with 50–200 employees" → Search.
- Docs: [search-and-enrich recipe](https://claydevelopers.mintlify.app/recipes/search-and-enrich)

### 2. Clay-managed functions — *the default for enrichment* ⭐

Pre-built, Clay-maintained routines for **common GTM enrichment/research**. **Start here for any standard data task** — no building required.

- Work email, phone, job title, seniority
- Company domain, address, industry, employee count, revenue
- Tech stack, hiring signals / job openings, news, funding
- Pattern: `Search → managed function (e.g. find work email) → output`
- Docs: [clay-managed-functions](https://claydevelopers.mintlify.app/routines/clay-managed-functions)

> If the need is a common enrichment, a managed function almost certainly already exists. Check here **before** building anything.

### 3. Custom functions — *your team's reusable logic, built in Clay's UI*

Use when the org has a **validated, repeatable process that no managed function covers** — and you want it reusable across agents/tools.

- Account scoring / qualification, inbound routing, territory assignment, CRM cleanup, team-specific enrichment sequences.
- **Built only in the Clay UI — you cannot build or create a custom function from the CLI/MCP/API.** Those interfaces can only **invoke** an existing custom function (exposed via API/MCP in its Details, called as `function:t_...`). If a task needs a *new* custom function, surface that to the user — it has to be created in the Clay app.
- Prefer this over a Workflow when the logic can live in the UI and just needs invoking.
- Docs: [custom-functions](https://claydevelopers.mintlify.app/routines/custom-functions)

### 4. Workflows (Alpha) — *last resort, code-editor-built flows* 🧪

Multi-node flows (trigger → agent / enrich / code nodes) **built and edited from Claude Code, Codex, Cursor, or the CLI**. Same execution power as functions, different build surface. *(Unlike custom functions, Workflows **can** be built from the CLI/code editor — that's their whole point.)*

**This is an Alpha feature.** The interface is still evolving and behavior may change. Whenever you use, build, or edit a Workflow on the user's behalf, **tell the user up front that Workflows are an Alpha product** so they can calibrate expectations — e.g.:

> "Heads up: I'm using Clay's **Workflows (Alpha)** for this. It's an early-stage feature, so the interface may change and there can be rough edges. If you'd prefer something more stable, a managed or custom function may cover this."

**Only use a Workflow when a function genuinely can't do it:**

- You need **embedded custom code** (deterministic transforms) inside the flow
- You must **exceed the 50,000-row** function batch limit
- You need **step-by-step run inspection / debugging / snapshots** in a code environment
- Inputs come from **diverse sources** (CSVs, webhooks, Audiences, existing tables) stitched together

> ⚠️ The docs explicitly say: *for common enrichment and existing reusable logic, start with Clay-managed functions or custom functions.* Do **not** build a Workflow for something a managed/custom function already handles.
>
> Docs: [functions-vs-workflows](https://claydevelopers.mintlify.app/routines/functions-vs-workflows) · [workflows-alpha](https://claydevelopers.mintlify.app/routines/workflows-alpha) · [build-workflow-alpha](https://claydevelopers.mintlify.app/recipes/build-workflow-alpha)

### Tables — *query only, never create* 📊 (Enterprise)

Query data from Clay tables that **already exist**. **You cannot create new tables** through the plugin/CLI/MCP/API — that must be done in the Clay app. If a task needs a brand-new table, surface that to the user rather than trying to create one.

### Quick decision order

1. Need a list of people/companies? → **Search** (primitive)
2. Standard enrichment/research? → **Managed function** (check the catalog first)
3. Team-specific trusted logic, no managed fn exists? → **Custom function** (invoke an existing one; can't build it from the CLI)
4. Only if none of the above work (custom code, >50k rows, code-editor debugging)? → **Workflow (Alpha)** — *and tell the user it's an Alpha feature*
5. Need data from an existing table? → **Tables** (query only — can't create tables programmatically)
