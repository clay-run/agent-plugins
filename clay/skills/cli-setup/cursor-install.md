# Cursor plugin install: resolving which path applies

On Cursor, Teams/Enterprise org policy can silently block the naive "copy the plugin folder
into `~/.cursor/plugins/local/clay`" approach: the plugin never appears in Settings → Plugins
no matter how many times you restart, because the org disabled local sideloading. Detect the
actual policy before choosing a path, so you don't burn restarts on a path that can never work.

## Read the signal

Cursor caches its resolved org policy locally, so you can read the actual gates instead of
guessing. The cache lives in the `adminSettings.cached` row of Cursor's SQLite state DB:

```bash
case "$(uname -s)" in
  Darwin) cursor_appsup="$HOME/Library/Application Support/Cursor" ;;
  *)      cursor_appsup="$HOME/.config/Cursor" ;;
esac
statedb="$cursor_appsup/User/globalStorage/state.vscdb"

python3 - "$statedb" <<'PY'
import json, sqlite3, sys

path = sys.argv[1]
row = None
try:
    conn = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    row = conn.execute(
        "SELECT value FROM ItemTable WHERE key LIKE '%adminSettings.cached%' "
        "ORDER BY length(value) DESC LIMIT 1"
    ).fetchone()
except sqlite3.Error:
    pass

if not row:
    print("no cached admin settings — not on a Cursor team, or Cursor hasn't run yet; "
          "fall back to the plugin-log heuristic below")
    sys.exit(0)

try:
    cached = json.loads(row[0])
except ValueError:
    print("cached admin settings weren't valid JSON; fall back to the plugin-log heuristic below")
    sys.exit(0)

if isinstance(cached, str):
    # VS Code-family state rows are sometimes double-encoded: a JSON string holding JSON.
    try:
        cached = json.loads(cached)
    except ValueError:
        pass
if not isinstance(cached, dict):
    print("cached admin settings weren't a JSON object; fall back to the plugin-log heuristic below")
    sys.exit(0)

def allowed(flag):
    # Team policy is opt-out (missing/true means allowed); non-team users are unrestricted.
    return cached.get(flag) is not False

local_ok = allowed("allowUserLocalPluginImports")
marketplace_ok = allowed("allowThirdPartyPluginImports")

if local_ok and marketplace_ok:
    print("path 3 (local sideload): allowed. path 1/2 (marketplace import): also allowed.")
elif local_ok:
    print("path 3 (local sideload): allowed; marketplace import (path 1/2) is policy-blocked")
elif marketplace_ok:
    print("local sideload is policy-blocked; path 1/2 (marketplace import) is allowed — "
          "do not apply path 3. If ~/.cursor/plugins/cache/*/clay/*/scripts/install-cli.sh exists, "
          "continue to SKILL.md step 3; otherwise print path 1/2 and STOP until the "
          "import lands and Cursor is fully restarted")
else:
    print("plugin imports are policy-blocked entirely — nothing here is self-serve; only an "
          "admin can unblock this (allowUserLocalPluginImports or allowThirdPartyPluginImports)")
PY
```

Windows/WSL isn't verified anywhere in this skill (the `*` branch above assumes a Unix-style
`$HOME`, and nothing else here has been tested off macOS) — if this doesn't resolve a real path,
skip straight to the plugin-log fallback below.

**Never write to `adminSettings.cached` or any other row in `state.vscdb` to force a flag on.**
It's re-fetched from the server on every sync and the import RPC re-enforces the same policy
server-side, so editing the local cache doesn't unlock anything — it just corrupts local state
until the next refetch. A blocked flag is the real answer; surface the admin instructions
instead of working around it. The same DB also holds `cursorAuth/accessToken` — don't read,
use, or mention it; it has no legitimate role in this skill.

If `state.vscdb` or `sqlite3`/`python3` isn't available, fall back to Cursor's plugin-load log
instead, which is a weaker but still useful signal:

```bash
latest_session="$(ls -td "$cursor_appsup/logs"/*/ 2>/dev/null | head -1)"
plugin_log="$(find "$latest_session" -name 'Cursor Plugins.log' 2>/dev/null | head -1)"
[ -n "$plugin_log" ] && grep -o 'loadAllPlugins completed[^)]*)' "$plugin_log" | tail -1
```

This prints something like:

```
loadAllPlugins completed in 42.3ms (claude=true, userLocal=false, userSettings=true, marketplace=0 sources, total=3 plugins, failures=0)
```

`userLocal=false` means local sideload is policy-blocked — skip straight to path 1/2.
`userLocal=true` means path 3 will work. If neither signal is available at all (nothing has
launched Cursor yet), assume `userLocal=true` and try path 3 first; the result after restart
will confirm or refute it.

## Apply a path, most legitimate first

Pick from the policy read above. Paths 1 and 2 need a human in the Cursor UI and can't be
automated from here. Path 3 is the only automatable install — only run it when local sideload
is allowed. If local sideload is blocked and marketplace import is allowed, print the path 1/2
steps, then distinguish **import still pending** from **import already landed**:

```bash
ls -1dt "$HOME"/.cursor/plugins/cache/*/clay/*/scripts/install-cli.sh 2>/dev/null | head -n1
```

A printed path means the marketplace plugin is on disk — **skip path 3** (sideload stays
blocked) and **continue to `SKILL.md` step 3** to install the independent CLI. An empty result means the import hasn't landed — **stop** and wait for the user
(or admin) to import + fully restart Cursor, then re-run `SKILL.md` step 1 (it should now
see the cache and continue). There is no self-serve fallback once path 4 is gone, and
applying path 3 with sideload blocked just leaves a dead never-loading entry.

**1/2. Marketplace import — team (admin) or personal (any user).** Both are UI-only, not
automatable from here, and use the same flow: Settings → Plugins → Add Marketplace → Import from
GitHub → enter `clay-run/agent-plugins`, choosing **team** scope (path 1, best for orgs — every
member gets the plugin) or leaving it at **personal** scope (path 2). Team scope needs an admin
with the `team.plugins.manage` permission (team role OWNER); personal scope needs no admin, but
only offer it if the policy read above says it's allowed — `allowThirdPartyPluginImports` gates
both scopes, since `clay-run/agent-plugins` is a third-party marketplace either way. The import
itself is a server-side RPC tied to the account — there's no CLI/script shortcut to complete it,
only to know in advance whether it'll work. State the steps. If local sideload is also allowed,
you can still apply path 3 below so they have a working install while the marketplace step is
pending. If local sideload is blocked, run the marketplace-cache check above: an installer means
the import has landed — skip path 3 and continue to `SKILL.md` step 3. No installer means the
import is still pending — **stop here**; after the user (or their admin) imports and fully
restarts Cursor, re-run `SKILL.md` step 1 (it should now find the cache and continue).

**3. Local sideload (automatable, gated by `allowUserLocalPluginImports`).** Skip this path
entirely unless the policy read above (or the plugin-log fallback) showed local sideload is
allowed — running the copy anyway when it's blocked just leaves a dead, never-loading entry under
`~/.cursor/plugins/local/clay` for the user to find and be confused by. If allowed, copy this same
plugin's files into Cursor's local-plugin directory. Resolve the plugin root as two levels up
from the CLI setup skill's own directory (`.../clay/skills/cli-setup` — the same directory that holds
this `cursor-install.md` and `SKILL.md`):

```bash
# Replace <THIS_SKILL_DIR> with the CLI setup skill's directory (the one containing this
# cursor-install.md and SKILL.md, e.g. .../clay/skills/cli-setup):
plugin_root="$(cd "<THIS_SKILL_DIR>/../.." && pwd -P)"
# A bad <THIS_SKILL_DIR> substitution must stop here, before the rm -rf below can
# destroy an existing install: empty means the cd failed, and the manifest check
# catches a substitution that resolved to a real but wrong directory.
[ -n "$plugin_root" ] && [ -f "$plugin_root/.cursor-plugin/plugin.json" ] \
  || { echo "could not resolve plugin root from <THIS_SKILL_DIR>" >&2; exit 1; }
target="$HOME/.cursor/plugins/local/clay"
# Resolve $target through pwd -P too — comparing raw strings would miss a symlinked or
# alternate-spelling path pointing at the same real directory as $plugin_root, and rm -rf
# would delete the source before the copy.
target_real="$(cd "$target" 2>/dev/null && pwd -P)"
if [ "$plugin_root" != "$target_real" ]; then
  mkdir -p "$(dirname "$target")"
  rm -rf "$target"
  cp -R "$plugin_root" "$target"
fi
```

When every plugin-import policy above is blocked there is no self-serve path left — stop and
tell the user an admin has to unblock `allowUserLocalPluginImports` or
`allowThirdPartyPluginImports`.

## Clean up after an earlier run

Preserve existing connector configuration when installing or repairing the CLI.
A connector with the same product name is not evidence of a stale installation.

Earlier setup runs may have left a permanent plugin copy at `~/.config/clay-plugin/clay`.
Leave it in place until `SKILL.md` step 3 has migrated and verified the independent CLI;
an old forwarder may still depend on it. It is no longer needed after that migration.

**Landed on path 1 or 2 (a marketplace path)?** Remove any dead local-sideload copy so Cursor
doesn't show a permanently-broken plugin entry. **Skip this after path 3** — it installs into
exactly this directory, so running it there deletes the install you just made:

```bash
rm -rf "$HOME/.cursor/plugins/local/clay"
```

After applying a path, **fully quit Cursor (Cmd/Ctrl+Q) and reopen it** — a new chat or
"Reload Window" is frequently not enough to pick up a newly-added local plugin. Once done,
return to `SKILL.md` and continue with step 3.
