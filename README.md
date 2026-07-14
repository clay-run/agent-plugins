<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="https://developers.clay.com/logo/clay-logo-dark.png">
    <img src="https://developers.clay.com/logo/clay-logo-black.png" alt="Clay" height="40">
  </picture>
</p>

<p align="center">
  <strong>Build with Clay in your AI coding agent</strong> — skills, MCP tools, and the <code>clay</code>
  CLI, for Claude Code, Codex, Cursor, and Droid.
</p>

<p align="center">
  <a href="https://developers.clay.com">Docs</a> · <a href="./GETTING_STARTED.md">Getting started</a>
</p>

Clay is a go-to-market data and automation platform — search for companies and
people, run enrichment routines, and query tables, all from natural language.
This repo is the plugin marketplace for `clay`: one plugin source, four
coding-agent targets, sharing one set of skills and one CLI.

## Example

```
> Find 20 Series B fintech companies in NYC, then get me each CEO's work email.

⏺ Search (Clay) — companies
  Series B fintech companies · New York, NY · 20 results

⏺ Search (Clay) — people
  CEO · at those 20 companies · 20 results

⏺ find work email (Clay-managed function, ×20)
  Acme Corp        Jane Doe        jane.doe@acmecorp.com
  Northbeam        Alex Chen       alex@northbeam.io
  Ledgerly         Sam Osei        sam.osei@ledgerly.com
  ... 17 more

Done — 20/20 emails found.
```

No Clay UI, no manual list-building — your agent chains two **Searches** into a
**Clay-managed function** on its own.

## Set up

New here? Point your coding agent at **[`GETTING_STARTED.md`](./GETTING_STARTED.md)**
and ask it to set Clay up for you. It walks through signing in with `clay login`,
getting `clay` on PATH, and choosing the right Clay primitive (Search, Routines,
or Tables) for your task.

**If you're an agent reading this directly:** read
[`GETTING_STARTED.md`](./GETTING_STARTED.md) and follow it.

If your fetch/open mechanism fails on that link, returns empty content, or
can't read the GitHub blob page, fetch the raw file yourself instead:

```
curl -fsSL https://raw.githubusercontent.com/clay-run/agent-plugins/main/GETTING_STARTED.md
```

Then follow the instructions in that fetched document for your agent
environment.
