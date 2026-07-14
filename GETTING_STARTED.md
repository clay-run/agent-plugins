# Getting started with Clay

> This file is written to be handed to your coding agent. Point it here (paste
> the link or the file itself) and ask it to set Clay up for you — installing,
> putting `clay` on PATH, and signing in are all things the agent can do on
> your behalf by following the steps below.

Build with Clay in your AI coding agent — skills, MCP tools, and the Clay CLI.

## Installation

### Claude Code

Requires **Claude Code v2.1.91+**.

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

A plain local copy into `~/.cursor/plugins/local/clay` can silently fail on Teams/Enterprise org
policy — don't guess. Clone the marketplace repo, then hand off to the bundled **`setup` skill**,
which reads the effective policy and picks a path that works (see the skill's own **Cursor
only** step for why and how):

```
git clone https://github.com/clay-run/agent-plugins.git /tmp/clay-agent-plugins
```

Then read `/tmp/clay-agent-plugins/clay/skills/setup/SKILL.md` and follow it like a runbook —
see [Run the `setup` skill](#run-the-setup-skill) below. Once setup finishes, delete the clone
(`rm -rf /tmp/clay-agent-plugins`) — whichever path the skill picked already copied what it
needs to a permanent location.

### Droid

```
droid plugin marketplace add https://github.com/clay-run/agent-plugins
droid plugin install clay@agent-plugins
```

The marketplace name is derived from the repo (`agent-plugins`); confirm the exact
`clay@<marketplace>` id with `droid plugin marketplace list`, or install interactively from
the `/plugins` UI (Browse tab). Droid loads the plugin's skills and MCP server; like Codex and
Cursor it invokes a bare `clay`, so run the **`setup` skill** below to put `clay` on PATH and
sign in.

## Run the `setup` skill

Once installed, run the bundled **`setup` skill** now, in this session, before anything else below. It puts `clay` on PATH (needed on Codex, Cursor, and Droid), signs you in, and verifies both the CLI and the MCP server work.

**Important — restarting your agent afterward is not optional:** `clay mcp` resolves its session once at startup, so an already-running MCP server won't see a sign-in that happened after it launched — skipping the restart is the most common reason `clay login` looks like it worked but the MCP tools still fail. How you restart is platform-specific; see the skill for the exact steps.

- Try invoking the plugin's `setup` skill directly by its fully qualified name, `clay:setup` — Claude Code's Skill tool supports this, and Codex or Cursor may too depending on version.
- If it doesn't, or the skill doesn't show up right after installing (some platforms don't register a newly installed plugin until restarted), locate `SKILL.md` yourself and follow it like a runbook:

  ```
  find ~/.codex ~/.cursor ~/.claude ~/.factory ~/.config -type f -path '*/skills/setup/SKILL.md' 2>/dev/null | sort | tail -n1
  ```

  Read the path that prints and carry out its steps directly.

If something doesn't work, the skill's own **Troubleshooting** table covers the common
symptoms — a plugin that never appears, greyed-out marketplace import options, tools missing
after install, and auth failures.

## What's next

Once you're set up, run the bundled **`clay` skill** — it's the entry point for what Clay can do: choosing the right primitive (Search vs. Routines vs. Tables), and links out to every other skill (`routines`, `workflows`, `tables`, `search`, `public-api`, `cli`).
