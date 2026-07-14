---
name: setup
description: Clay setup — authenticate both the `clay` CLI and the Clay MCP server (both are required to use the plugin). Use when `clay` is not found on PATH or the `clay` found in the PATH is the wrong version, `clay whoami` fails, the MCP tools (`read`, `edit_node`) error on auth or don't appear at all despite a Connected server, the CLI isn't signed in, the Cursor plugin never appears after a local install, or the user wants to configure Clay.
allowed-tools: Bash, Read, Edit, Write
---

# Clay setup

**Two things must be authenticated to use this plugin:**

1. **The `clay` CLI** — runs tests, searches actions, manages runs.
2. **The Clay MCP server** — provides the in-editor tools (`read`, `edit_node`, `validate_workflow`, `execute_clay_action`).

Both authenticate the same way: **`clay login`** opens a browser once, and the
resulting session is shared by the CLI and by `clay mcp` — the local proxy the plugin
registers as the MCP server, which forwards to Clay using that same session (no
separate key to hand the MCP server). The catch is _when_ each side picks up a
session: the CLI re-reads it on every command, but `clay mcp` is a long-running
process the agent's harness spawns once and only resolves the session at startup. So
signing in is not enough by itself — the agent (Claude Code / Codex / Cursor) must be
**restarted** for its already-running MCP server to see a session created after it
launched, and `clay whoami` succeeding does **not** by itself prove the MCP is
authenticated.

## 1. Check current state

Run this and read the printed **exit_code and JSON**, not any status string:

```bash
clay whoami; echo "exit_code=$?"
```

- **exit_code=0** with a `user`/`workspace` object → the CLI is authenticated.
  Also confirm the `mcp` subcommand is present — Cursor's config invokes a bare
  `clay` with no way to pin the bundled launcher, so a `clay` that already
  satisfied `whoami` could still be an old install shadowing it that predates
  `mcp`:

  ```bash
  clay mcp --help >/dev/null 2>&1; echo "exit_code=$?"
  ```

  - **exit_code=0** → both surfaces work. On Cursor, also check that a previous run's
    Option A registration isn't now duplicating an installed plugin — a marketplace
    import or sideload that was still pending back then may have completed since:

    ```bash
    grep -q '"clay"' "$HOME/.cursor/mcp.json" 2>/dev/null \
      && sh -c 'ls -d "$HOME"/.cursor/plugins/cache/*/clay/* "$HOME"/.cursor/plugins/local/clay 2>/dev/null' | grep -q . \
      && echo "dual registration"
    ```

    If that prints `dual registration`, run the "landed on path 3 or a marketplace path"
    cleanup under **Don't run two paths at once** in `cursor-install.md`, then fully
    restart Cursor. Otherwise tell the user (name the workspace) and stop —
    unless the reported symptom was specifically "the Cursor plugin never appears in
    Settings → Plugins," in which case this only proves a `clay` on PATH works, not that
    it's the Cursor plugin's own install; still do step 2 to confirm.
  - **non-zero** → the `clay` on PATH is authenticated but predates the `mcp`
    subcommand. Do step 3 to install the bundled launcher ahead of it on PATH,
    then re-run this check.

- **`clay: command not found`** (or exit 127) → the CLI isn't on your PATH. On Cursor, do
  step 2 first (it decides where the plugin's files permanently live); then do step 3, then
  step 4. On Claude Code, Codex, and Droid, skip step 2 and go straight to step 3, then step 4.
  Exception: exit 127 with a JSON envelope on stderr saying `no bundled launcher found` is
  the forwarder from a previous setup reporting that the plugin cache itself is gone —
  reinstalling the forwarder won't help; tell the user to reinstall the Clay plugin instead
  (on Cursor, reinstalling means redoing step 2 — the working install method is
  policy-dependent).
- **exit_code=3** (`auth_*`) → the CLI works but isn't authenticated. Skip to step 4.
- **exit_code=5** (`network_*`) → a connection problem. Check `CLAY_API_URL` and the
  network; do not restart the sign-in flow.

## 2. Cursor only: resolve which install path applies

Skip this entire section on Claude Code and Codex — they don't have this policy layer.

On Cursor, Teams/Enterprise org policy can silently block the naive "copy the plugin folder
into `~/.cursor/plugins/local/clay`" approach: the plugin never appears in Settings → Plugins
no matter how many times you restart, because the org disabled local sideloading. Read
`cursor-install.md` (in this same directory as this `SKILL.md`) in full and follow it — it
covers reading Cursor's resolved policy and choosing/applying the right install path (team
marketplace, personal marketplace import, local sideload, or a direct MCP-registration
fallback) — then continue to step 3 below.

## 3. Put `clay` on your PATH (if it was "command not found", lacked `mcp`, or is an outdated version)

Claude Code adds the plugin's `bin/` to PATH automatically, so this step is only
needed in Codex, Cursor, and Droid, or when another `clay` install is shadowing the
bundled one.

The plugin bundles the CLI launcher at `bin/clay` in the plugin root; it downloads
and checksum-verifies the real binary on first use. The launcher is version-stable
(it reads its neighbor `bin/cli-version` and fetches that CLI), so the forwarder
just needs to point at the newest launcher on disk.

Install a small forwarder onto your PATH (in `~/.local/bin`) that resolves the
newest bundled launcher **at runtime** rather than baking in one absolute path.
This is what lets it survive plugin updates (which install a new version directory)
and work no matter which agent (Claude Code / Codex / Cursor / Droid) installed the plugin.
It picks the most-recently-modified launcher — an install-time heuristic that works
across both version-named cache dirs (Claude/Codex) and commit-hash-named ones
(Cursor/Droid). If one agent's cache lags behind another's, the freshest install wins, so
the CLI can briefly trail the newest pin until the caches converge — every launcher
is self-contained, so it still runs a valid checksum-verified CLI.

First confirm a launcher actually exists where the forwarder will look — this is
the same resolution the forwarder performs, run once now so a missing plugin
cache fails loudly here instead of as a confusing 127 later (run it through `sh`
so unmatched globs stay harmless even if your shell is zsh):

```bash
sh -c 'ls -1dt \
  "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/*/clay/*/bin/clay \
  "${CODEX_HOME:-$HOME/.codex}"/plugins/cache/*/clay/*/bin/clay \
  "$HOME"/.cursor/plugins/cache/*/clay/*/bin/clay \
  "$HOME"/.cursor/plugins/local/clay/bin/clay \
  "${FACTORY_CONFIG_DIR:-$HOME/.factory}"/plugins/cache/*/clay/*/bin/clay \
  "$HOME"/.config/clay-plugin/clay/bin/clay \
  2>/dev/null | head -n1'
```

If this prints nothing, **stop** — no bundled launcher exists in any known plugin
cache, so the forwarder below would have nothing to exec. Tell the user to
reinstall the Clay plugin (on Cursor, that means redoing step 2 — the working
install method is policy-dependent), then re-run this skill. (If you read this SKILL.md
from a plugin root outside these caches, report that path to the user — the
plugin is installed somewhere this forwarder doesn't search.)

If it printed a path, install the forwarder (keep its search list in sync with
the pre-flight above):

```bash
mkdir -p "$HOME/.local/bin"
cat > "$HOME/.local/bin/clay" <<'EOF'
#!/bin/sh
# Resolve the newest bundled clay launcher at runtime so this forwarder survives
# plugin version bumps and works whichever agent (Claude/Codex/Cursor/Droid) installed it.
# CLAUDE_CONFIG_DIR, CODEX_HOME, and FACTORY_CONFIG_DIR relocate those agents' state
# roots (and with them the plugin cache), so honor them when set — they expand here
# at runtime, from the invoking process's environment.
launcher="$(ls -1dt \
  "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/plugins/cache/*/clay/*/bin/clay \
  "${CODEX_HOME:-$HOME/.codex}"/plugins/cache/*/clay/*/bin/clay \
  "$HOME"/.cursor/plugins/cache/*/clay/*/bin/clay \
  "$HOME"/.cursor/plugins/local/clay/bin/clay \
  "${FACTORY_CONFIG_DIR:-$HOME/.factory}"/plugins/cache/*/clay/*/bin/clay \
  "$HOME"/.config/clay-plugin/clay/bin/clay \
  2>/dev/null | head -n1)"
# Match the launcher's bootstrap-failure contract: JSON envelope on stderr and a
# categorical exit code (127 = command not found).
[ -x "$launcher" ] || { printf '{"error":{"code":"internal_error","message":"clay: no bundled launcher found in plugin cache; reinstall the Clay plugin"}}\n' >&2; exit 127; }
exec "$launcher" "$@"
EOF
chmod +x "$HOME/.local/bin/clay"
```

Ensure `~/.local/bin` is on PATH (for this session and future ones):

```bash
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) export PATH="$HOME/.local/bin:$PATH"
     for rc in "$HOME/.zshrc" "$HOME/.bashrc"; do
       [ -e "$rc" ] && ! grep -q '.local/bin' "$rc" && printf '\nexport PATH="$HOME/.local/bin:$PATH"\n' >> "$rc"
     done ;;
esac
```

`command -v clay` should now resolve — but confirm it's actually the bundled
launcher and not a shadowing install, since Cursor's MCP config invokes bare
`clay` with no way to pin the bundled path:

```bash
clay mcp --help >/dev/null 2>&1; echo "exit_code=$?"
```

- **exit_code=0** → whichever `clay` is first on PATH supports `mcp`; leave it as-is
  (a different `clay` taking precedence — e.g. an older standalone install — is
  fine as long as it passes this check).
- **exit_code=127** → the forwarder ran but found no launcher (its stderr — rerun
  without `2>&1` to see it — is a JSON envelope saying `no bundled launcher
  found`). The plugin cache disappeared since the pre-flight above, or the check
  hit a different stale forwarder; don't touch PATH — tell the user to reinstall
  the Clay plugin.
- **other non-zero** (unknown command) → an older `clay` is shadowing the
  forwarder you just installed, predating the `mcp` subcommand. Move the
  `export PATH=...` line above in your shell rc so `~/.local/bin` comes before
  the old install's directory, open a new shell, and re-run the check.

**Restart required:** a running Codex or Cursor process resolved its PATH (and,
for Cursor's MCP server, spawned `clay` via that PATH) before this step ran, so
it won't see the newly-created `~/.local/bin/clay` entry until it's restarted.
This restart is one-time — the forwarder never needs repointing after plugin
updates. See the Codex/Cursor restart steps under step 4 below, then re-run the
check in step 1.

## 4. Sign in

Run `clay login`. It opens a browser, the user signs in and picks a workspace, and
the CLI stores the session locally on disk — used by both the CLI and by `clay mcp`,
so there's nothing separate to configure for the MCP server. The flow waits up to 5
minutes for the browser round-trip. If your shell tool lets you set a per-command
timeout, request at least 5 minutes and just run it directly and block on it:

```bash
clay login   # request a timeout of at least 5 minutes if your tool supports one
```

If your tool's timeout can't be raised past 5 minutes and it doesn't support
backgrounding a long-running command, ask the user to run `clay login` in their own
terminal instead, then poll:

```bash
clay whoami; echo "exit_code=$?"   # poll this until exit_code=0
```

**Restart the agent afterward** so the running MCP server picks up this session.
A new chat/conversation is *not* the same as a restart everywhere — what
actually respawns the MCP server depends on where you're running:

- **Claude Code (desktop app):** MCP servers are shared at the app level, not
  per-conversation — a new chat does *not* restart one, and there's no
  in-session way to reconnect it either (no `/mcp` reconnect UI in the
  Desktop app's Claude Code pane). Fully quit the app (Cmd/Ctrl+Q) and reopen
  it — this restarts every session in the app, not just Clay's.
- **Claude Code (terminal):** a new chat in the *same* running process does not
  respawn the MCP server — exit the process itself: run `/exit`, then start
  `claude` again.
- **Codex (CLI):** same as the terminal case — Codex spawns MCP servers once at
  startup and has no way to restart a single one yet. Exit the session
  (`/exit` or Ctrl+C) and run `codex` again.
- **Cursor:** MCP servers run at the app level and are shared across all
  chats, so a new chat does *not* restart them. Open **Settings → MCP**, and
  toggle the `clay` server off then on — this is the fastest fix and usually
  enough. If the MCP tools still error, use Cmd/Ctrl+Shift+P →
  **Developer: Reload Window**; if that still doesn't pick it up, fully quit
  and reopen Cursor.
- **Droid (CLI):** Droid spawns each plugin's MCP server once at startup, so a
  new session in the *same* running process won't reconnect Clay. Exit the
  process (`/exit` or Ctrl+C) and run `droid` again; if a background
  `droid daemon` is running, restart it too. Confirm with
  `droid mcp list` — the `clay` server should read `connected`.

## 5. Verify both surfaces

**CLI:**

```bash
clay whoami; echo "exit_code=$?"
```

`exit_code=0` with a `user`/`workspace` object means the CLI is authenticated.

**MCP server:** after restarting the agent, confirm the `clay` MCP server is connected
and its tools respond — e.g. call `read` on a workflow. A "Connected" status alone
doesn't prove this: it only confirms the `initialize` handshake succeeded, not that
`tools/list` was ever called or parsed. If the tools don't work, tell the two failure
shapes apart:

- **MCP tools return an auth error while `clay whoami` succeeds** — two distinct
  causes with different fixes:
  - **Not yet restarted** (or the credential isn't visible where the harness launches
    the MCP server) — redo the restart from step 4 and recheck.
  - **Already restarted and still failing** — the credential is valid but the account
    isn't a workspace Editor/Admin (`auth_forbidden`). This is a workspace-role
    problem, not a session problem: re-running `clay login`/`clay logout` or
    restarting again won't fix it. Have a workspace Admin change the user's role to
    Editor or Admin, then recheck.
- **No Clay tools appear at all in Claude Code** — not an auth error, they're simply
  absent, even though the server shows Connected and `clay whoami` succeeds. This is
  an apparent Claude-Code-side tool-registration gap, not a session problem: restarting
  again, re-authenticating, or reinstalling the plugin won't fix it — but updating
  Claude Code might, since registration bugs in this class have been fixed in point
  releases. See the Troubleshooting table below instead of looping on restarts.

Setup is complete only when **both** the CLI and the MCP tools work.

## Troubleshooting

| Symptom | Cause | Fix |
| --- | --- | --- |
| Plugin never appears in Settings → Plugins; plugin log shows `userLocal=false` | `allowUserLocalPluginImports` disabled by org policy | Use path 1 (team marketplace, admin), path 2 (personal marketplace, if third-party imports are enabled), or path 4 (Option A) — see step 2 |
| "Add Marketplace" → Import options are greyed out or missing | Third-party imports policy-locked (`allowThirdPartyPluginImports` off) | This same flag gates path 1 too, so path 1 isn't a workaround here — an admin must enable `allowThirdPartyPluginImports` first for any marketplace path (1 or 2). Until then, use path 3 (local sideload, if `allowUserLocalPluginImports` is separately still on) or path 4 (Option A) — see step 2 |
| MCP tools not visible right after applying path 3 or 4 in Cursor | Didn't fully quit and reopen Cursor after installing — a new chat or Reload Window isn't enough for a newly-added local plugin or `mcp.json` entry | Fully quit (Cmd/Ctrl+Q) and reopen Cursor — see step 2 |
| MCP tools show an auth error after `clay login`, on any platform | Agent wasn't restarted the way its platform requires | Restart per your platform — see step 4 (Cursor: try the Settings → MCP toggle and Reload Window before a full quit) |
| `clay whoami` exits 3 | Not signed in | Run `clay login` (step 4), then restart the agent |
| Duplicate `clay` MCP registrations in Cursor (plugin **and** `~/.cursor/mcp.json`) | Option A was applied while a marketplace import or sideload was pending, and that path has since completed | Run the "landed on path 3 or a marketplace path" cleanup in `cursor-install.md`, then fully restart Cursor — see step 1 |
| MCP tools error with an auth error while `clay whoami` succeeds | Not-yet-restarted, or `auth_forbidden` (workspace role) — see step 5 above | Redo the restart, or have an Admin fix the workspace role |
| No Clay tools appear at all in Claude Code — not an auth error, just absent — even after a clean restart, with the server showing Connected and `clay whoami` succeeding | An apparent Claude-Code-side tool-registration gap (registration appears to be all-or-nothing per server; Clay's large, deeply nested `edit_node` schema is a plausible trigger) — see step 5 above | Update Claude Code (`claude update`, or your installer's equivalent) and retry — registration bugs in this class have been fixed in point releases. If the tools still don't appear on the latest version, report it to the Clay team using the `clay-feedback` skill (the `clay feedback` CLI still works while the MCP tools are absent), and include the Claude Code version (`claude --version`) |
