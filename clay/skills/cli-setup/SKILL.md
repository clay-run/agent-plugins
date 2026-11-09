---
name: cli-setup
description: Clay CLI setup — install and authenticate the `clay` CLI for command-line access to Clay. Use when the user asks to install or sign into the CLI, or a task that needs the CLI finds `clay` missing from PATH, at the wrong version, or failing `clay whoami` / not signed in. Also use when the Cursor plugin never appears after a local install, or the user wants to configure Clay. Signs the user in and runs first-run onboarding for new users.
allowed-tools: Bash, Read, Edit, Write
---

# Clay CLI setup

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

## 0. Check whether the task needs CLI setup

Continue with this skill when the user asks to install or sign into the CLI,
asks to fix plugin registration (for example, a Cursor plugin that never appears), or
the task uses the CLI. Honor the user's choice of CLI even when Clay MCP tools are
connected. For a task already using MCP, return to the skill you came from: a
missing, outdated, or signed-out `clay` executable does not affect the MCP session
and does not require CLI setup.

Install the CLI independently of the plugin, then check authentication. The same flow
applies to Claude Code, Codex, Cursor, and Cowork. Keep existing credentials and the
user's installation method when upgrading.

## 1. Check current state

Resolve `<PLUGIN_ROOT>` as two levels above this skill's directory. Use that exact
plugin copy, not whichever older cache directory was most recently modified.

```bash
bash "<PLUGIN_ROOT>/scripts/check-cli.sh" plain
cat "<PLUGIN_ROOT>/cli-min-version"
```

The check is local and does not sign in or download anything. A missing, old, or
plugin-managed CLI needs step 3, even if an old cached launcher still works. The
metadata is a minimum supported version, not an exact pin: leave a newer independent
CLI installed. If the check prints nothing, the installed CLI is compatible; proceed
to the authentication check below.

For a reported Cursor plugin registration problem, do step 2 even when the CLI works.

## 2. Cursor only: resolve which plugin install path applies

Skip this section unless installing the plugin into Cursor or investigating a plugin
that never appears in Settings → Plugins. Read `cursor-install.md` in this directory
and follow its policy checks before choosing marketplace import or local sideload.
A working CLI alone does not prove that Cursor loaded the plugin. If policy blocks
installation, follow that guide's admin handoff; do not bypass the policy.

## 3. Install or migrate the CLI

```bash
bash "<PLUGIN_ROOT>/scripts/install-cli.sh" --version "$(cat "<PLUGIN_ROOT>/cli-min-version")"
```

For a missing CLI or a recognized old plugin forwarder, this installs a native
macOS/Linux executable at `~/.local/bin/clay`, verifying its checksum and version.
For an existing native CLI below the minimum, it invokes that executable's `update`
command instead of reinstalling it. It checks `~/.local/bin/clay` even when that
directory is outside PATH and preserves compatible or newer versions. An existing
npm install keeps using npm. It never changes credentials.

If the user's organization requires Node-based execution, or the user explicitly
chooses npm, use this alternative (requires Node 22.21+ within Node 22 and npm):

```bash
bash "<PLUGIN_ROOT>/scripts/install-cli.sh" --method npm --version "$(cat "<PLUGIN_ROOT>/cli-min-version")"
```

Do not silently switch methods after a failed download or checksum check. If a native
binary is blocked by enterprise allowlisting, explain that the Node-based install is
available and use it when the user chooses that path. If npm reports a conflicting
`@claypi/cli` installation, inspect `npm list --global --depth=0` and its executable
path; migrate that old package explicitly rather than forcing an overwrite.

Read the installer's printed executable path. If its directory is missing from PATH,
add it once to the appropriate startup file for the user's shell (for example `.zshrc`
for zsh or `.bashrc` for interactive bash). Inspect the existing configuration first;
do not append to every shell's startup file or duplicate an existing entry. For the
default native location, the line is `export PATH="$HOME/.local/bin:$PATH"`.

Use the printed **absolute executable path** for all remaining commands in this
session, including subsequent skill calls, if the agent's inherited PATH is stale.
Variables do not persist between shell tool calls. Do not require a restart just to
finish setup. Resolve any older executable shadowing this path before declaring PATH
configured; do not delete unrelated executables.

Verify the executable with `--version` and compare its semver (before `+<commit>`)
to `cli-min-version`. Then run `clay whoami; echo "exit_code=$?"`, substituting the
verified absolute path when necessary:

- **0** with a user/workspace object: keep the session; skip sign-in and go to step 5.
- **3** (`auth_*`): go to step 4.
- **5** (`network_*`): investigate the network and `CLAY_API_URL`; do not restart sign-in.
- Any other failure: diagnose it before proceeding.

## 4. Sign in when needed

Use the verified executable from step 3, including its absolute path when PATH has not refreshed. Run `clay login`. It opens a browser, the user signs in and picks
the workspaces to connect, and the CLI stores a session per workspace locally on disk and
re-reads it on every command, so there's nothing else to configure and no restart to follow it.
Later commands run against the first workspace selected, and `clay workspaces switch <id>` moves
between them. The flow waits up to 5 minutes for the browser round-trip. If your shell tool lets
you set a per-command timeout, request at least 5 minutes and just run it directly and block on
it:

```bash
clay login   # request a timeout of at least 5 minutes if your tool supports one
```

If your tool's timeout can't be raised past 5 minutes and it doesn't support
backgrounding a long-running command, ask the user to run `clay login` in their own
terminal instead, then poll:

```bash
clay whoami; echo "exit_code=$?"   # poll this until exit_code=0
```

**Codex specifically:** the shell tool's timeout is usually shorter than the
5-minute browser round-trip, so a foreground `clay login` gets killed
mid-sign-in. The flow itself works on a local Codex session — approved commands
run on the user's machine, outside the sandbox — it just has to survive the
timeout. The recipe:

1. Run `clay login` in the background so the 5-minute wait survives the tool
   timeout:

   ```bash
   nohup clay login >/tmp/clay-login.out 2>/tmp/clay-login.err &
   ```

2. Read the sign-in URL from `/tmp/clay-login.err` and show it to the user to open
   in their own browser (`clay login` also tries to open the browser itself — the
   URL is the fallback). URLs from earlier attempts won't work.
3. Do NOT try to complete the sign-in with Codex's built-in browser tool: the user
   isn't driving it, so their credentials aren't available to enter — and if it
   runs in an isolated or remote context it can't reach the `127.0.0.1` callback
   anyway, so the sign-in is throwaway.
4. Poll `clay whoami; echo "exit_code=$?"` until `exit_code=0`.

If the backgrounded process dies (`clay whoami` never succeeds), fall back to the
run-it-in-their-own-terminal flow above.

In Cowork or another remote sandbox, use `clay login --device` and show the user the current
verification URL and code. Do not attempt a localhost browser callback from a remote machine.

## 5. Verify and onboard

Run `clay whoami; echo "exit_code=$?"` with the verified executable. Exit 0 with a
user/workspace object proves authentication. Keep identity details internal unless
needed to resolve an account issue.

If it exits 3 after a successful login, inspect the stderr error code and
`CLAY_CONFIG_HOME`: a different credential store or stale key can cause this. Retry
login as appropriate; this is not evidence of a workspace-role problem. Preserve
existing credentials during installation and migration.

If `whoami` or login reports `onboarded: false`, follow the `onboard` skill. Continue
using the verified absolute CLI path there if needed. If this session has not loaded
the skill yet, read `<PLUGIN_ROOT>/skills/onboard/SKILL.md` directly. Otherwise setup
is complete; do not make the user authenticate again merely because the plugin updated.
