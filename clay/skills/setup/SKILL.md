---
name: setup
description: Clay setup — authenticate both the `clay` CLI and the Clay MCP server (both are required to use the plugin). Use when `clay` is not found on PATH, `clay whoami` fails, the MCP tools (`read`, `edit_node`) error on auth, CLAY_API_KEY is missing, or the user wants to configure Clay.
allowed-tools: Bash, Read, Edit, Write
---

# Clay setup

**Two things must be authenticated to use this plugin:**

1. **The `clay` CLI** — runs tests, searches actions, manages runs.
2. **The Clay MCP server** — provides the in-editor tools (`read`, `edit_node`, `validate_workflow`, `execute_clay_action`).

Both authenticate with the **same `CLAY_API_KEY`** (the workspace is resolved from the
key — there is no workspace id to set), but they read it at different times: the CLI
reads it per command, while the MCP server reads it **once, when the harness launches
it**. So setting the key is not enough for the MCP — the agent (Claude Code / Codex /
Cursor) must be **restarted** for the MCP server to pick up a newly-set key, and
`clay whoami` succeeding does **not** by itself prove the MCP is authenticated.

## 1. Check current state

Run this and read the printed **exit_code and JSON**, not any status string:

```bash
clay whoami; echo "exit_code=$?"
```

- **exit_code=0** with a `user`/`workspace` object → setup already works. Tell the
  user (name the workspace) and stop.
- **`clay: command not found`** (or exit 127) → the CLI isn't on your PATH. Do
  step 2, then step 3.
- **exit_code=3** (`auth_*`) → the CLI works but isn't authenticated. Skip to step 3.
- **exit_code=5** (`network_*`) → a connection problem. Check `CLAY_API_URL` and the
  network; do not re-collect the key.

## 2. Put `clay` on your PATH (only if it was "command not found")

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

`command -v clay` should now resolve. (If a different `clay` is already on PATH —
e.g. an old `npm i -g @claypi/cli` — it will take precedence; that's fine, it is
the same CLI.)

## 3. Credentials

Create a key in Clay under **Settings → Account**, then make it available as
`CLAY_API_KEY`:

- **Claude Code** — merge it into `.claude/settings.local.json` (gitignored) under
  `env`, preserving existing settings:

  ```json
  { "env": { "CLAY_API_KEY": "<the key>" } }
  ```

  Then tell the user to restart so it loads: `/exit`, then `claude --continue`.

- **Codex / Cursor** — export it in the shell profile so both the CLI and the MCP
  server pick it up, then restart the agent:

  ```bash
  echo 'export CLAY_API_KEY="<the key>"' >> "$HOME/.zshrc"   # or ~/.bashrc
  export CLAY_API_KEY="<the key>"
  ```

## 4. Verify both surfaces

**CLI:**

```bash
clay whoami; echo "exit_code=$?"
```

`exit_code=0` with a `user`/`workspace` object means the CLI is authenticated.

**MCP server:** after restarting the agent, confirm the `clay` MCP server is connected
and its tools respond — e.g. call `read` on a workflow. If the MCP tools return an auth
error while `clay whoami` succeeds, the key was set but the agent wasn't restarted (or
the key isn't visible where the harness launches the MCP server) — set it as in step 3
and restart again. Setup is complete only when **both** the CLI and the MCP tools work.
