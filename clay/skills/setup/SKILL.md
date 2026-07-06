---
name: setup
description: Clay setup — authenticate both the `clay` CLI and the Clay MCP server (both are required to use the plugin). Use when `clay` is not found on PATH, `clay whoami` fails, the MCP tools (`read`, `edit_node`) error on auth, the CLI isn't signed in, or the user wants to configure Clay.
allowed-tools: Bash, Read, Edit, Write
---

# Clay setup

**Two things must be authenticated to use this plugin:**

1. **The `clay` CLI** — runs tests, searches actions, manages runs.
2. **The Clay MCP server** — provides the in-editor tools (`read`, `edit_node`, `validate_workflow`, `execute_clay_action`).

Both authenticate the same way: **`clay login`** opens a browser once, and the
resulting session is shared by the CLI and by `clay mcp` — the local proxy the plugin
registers as the MCP server, which forwards to Clay using that same session (no
separate key to hand the MCP server). The catch is *when* each side picks up a
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

  - **exit_code=0** → both surfaces work. Tell the user (name the workspace) and stop.
  - **non-zero** → the `clay` on PATH is authenticated but predates the `mcp`
    subcommand. Do step 2 to install the bundled launcher ahead of it on PATH,
    then re-run this check.

- **`clay: command not found`** (or exit 127) → the CLI isn't on your PATH. Do
  step 2, then step 3.
- **exit_code=3** (`auth_*`) → the CLI works but isn't authenticated. Skip to step 3.
- **exit_code=5** (`network_*`) → a connection problem. Check `CLAY_API_URL` and the
  network; do not restart the sign-in flow.

## 2. Put `clay` on your PATH (if it was "command not found", or lacked `mcp`)

Claude Code adds the plugin's `bin/` to PATH automatically, so this step is only
needed in Codex and Cursor.

The plugin bundles the CLI launcher at `bin/clay` in the plugin root; it downloads
and checksum-verifies the real binary on first use. You read this `SKILL.md` from
`<plugin-root>/skills/setup/SKILL.md`, so the launcher is two directories up at
`<plugin-root>/bin/clay`. Resolve it to an absolute path (with a search fallback):

```bash
# Replace <THIS_SKILL_DIR> with the directory you read this SKILL.md from:
shim="$(cd "<THIS_SKILL_DIR>/../.." 2>/dev/null && pwd)/bin/clay"
[ -x "$shim" ] || shim="$(find "$HOME/.codex" "$HOME/.cursor" "$HOME/.claude" "$HOME/.config" -type f -path '*/bin/clay' 2>/dev/null | sort | tail -n1)"
[ -x "$shim" ] || { echo "could not locate the bundled clay launcher; reinstall the plugin"; exit 1; }
```

Install a small forwarder onto your PATH (in `~/.local/bin`). Use a forwarder, not
a symlink — invoking the launcher by its real absolute path lets it find its own
plugin files:

```bash
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\nexec "%s" "$@"\n' "$shim" > "$HOME/.local/bin/clay"
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
  (a different `clay` taking precedence — e.g. an old `npm i -g @claypi/cli` — is
  fine as long as it passes this check).
- **non-zero** (unknown command) → an older `clay` is shadowing the forwarder you
  just installed, predating the `mcp` subcommand. Move the `export PATH=...` line
  above in your shell rc so `~/.local/bin` comes before the old install's
  directory, open a new shell, and re-run the check.

**Restart required:** a running Codex or Cursor process resolved its PATH (and,
for Cursor's MCP server, spawned `clay` via that PATH) before this step ran, so
it won't see the newly-created `~/.local/bin/clay` entry until it's restarted.
Tell the user to fully quit and reopen the agent — a simple retry or reload may
not re-spawn the MCP server's process environment — then re-run the check in
step 1.

## 3. Sign in

Run `clay login`. It opens a browser, the user signs in and picks a workspace, and
the CLI stores the session locally on disk — used by both the CLI and by `clay mcp`,
so there's nothing separate to configure for the MCP server. The flow waits up to 5
minutes for the browser round-trip. If your shell tool lets you set a per-command
timeout, request at least 5 minutes and just run it directly and block on it:

```bash
clay login   # request a timeout of at least 5 minutes if your tool supports one
```

If your tool's timeout can't be raised past 5 minutes, don't background the
process — ask the user to run `clay login` in their own terminal instead, then
poll:

```bash
clay whoami; echo "exit_code=$?"   # poll this until exit_code=0
```

**Restart the agent afterward** so the running MCP server picks up this session.

## 4. Verify both surfaces

**CLI:**

```bash
clay whoami; echo "exit_code=$?"
```

`exit_code=0` with a `user`/`workspace` object means the CLI is authenticated.

**MCP server:** after restarting the agent, confirm the `clay` MCP server is connected
and its tools respond — e.g. call `read` on a workflow. If the MCP tools return an auth
error while `clay whoami` succeeds, you signed in but the agent wasn't restarted (or
the credential isn't visible where the harness launches the MCP server) — redo the
restart from step 3 and recheck. Setup is complete only when **both** the CLI and the
MCP tools work.
