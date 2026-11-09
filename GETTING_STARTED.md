# Getting started with Clay

> This file is written to be handed to your coding agent. Point it here (paste
> the link or the file itself) and ask it to set Clay up for you — installing,
> putting `clay` on PATH, and signing in are all things the agent can do on
> your behalf by following the steps below.

Build with Clay in your AI coding agent — skills and the Clay CLI.

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
policy — don't guess. Clone the marketplace repo, then hand off to the bundled **`cli-setup` skill**,
which reads the effective policy and picks a path that works (see the skill's own **Cursor
only** step for why and how):

```
git clone https://github.com/clay-run/agent-plugins.git /tmp/clay-agent-plugins
```

Then read `/tmp/clay-agent-plugins/clay/skills/cli-setup/SKILL.md` and follow it like a runbook —
see [Run the `cli-setup` skill](#run-the-cli-setup-skill) below. Once setup finishes, delete the clone
(`rm -rf /tmp/clay-agent-plugins`) — whichever path the skill picked already copied what it
needs to a permanent location.

## Run the `cli-setup` skill

The CLI installs independently of the plugin. Setup defaults to a native executable
at `~/.local/bin/clay`; organizations that require Node-based execution can choose
`@clay-run/cli` through npm. Existing plugin launchers are migrated during setup,
without replacing your saved sign-in. You do not need Node for the native install.

Once installed, run the bundled **`cli-setup` skill** now, in this session, before anything else below. It puts `clay` on PATH, signs you in, and verifies the CLI works.

- Try invoking the plugin's `cli-setup` skill directly by its fully qualified name, `clay:cli-setup` — Claude Code's Skill tool supports this, and Codex or Cursor may too depending on version.
- If it doesn't, or the skill doesn't show up right after installing (some platforms don't register a newly installed plugin until restarted), locate `SKILL.md` yourself and follow it like a runbook:

  ```
  find ~/.codex ~/.cursor ~/.claude ~/.config -type f \
    \( -path '*/clay/skills/cli-setup/SKILL.md' -o -path '*/clay/*/skills/cli-setup/SKILL.md' \) 2>/dev/null | sort | tail -n1
  ```

  Read the path that prints and carry out its steps directly.

If something doesn't work, follow the CLI setup skill's **Cursor only** section for plugin
registration problems, **Install or migrate the CLI** for executable and PATH problems,
and **Sign in when needed** and **Verify and onboard** for authentication failures.

## What's next

Once you're set up, run the bundled **`clay` skill** — it's the entry point for what Clay can do: choosing the right primitive (Search vs. Routines vs. Tables), and links out to every other skill (`routines`, `workflows`, `tables`, `searches`, `public-api`, `cli`).
