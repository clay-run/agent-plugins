---
name: update
description: Keep Clay up to date. Use when the user asks to update or upgrade Clay, the plugin, or the `clay` CLI; when `clay update` reports the CLI is pinned / managed by the plugin; or to check whether a newer version is available. The plugin and CLI update independently; migrate older plugin-managed installs through setup.
allowed-tools: Bash, Read
---

# Keeping Clay up to date

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

The CLI is installed independently. The plugin declares its minimum compatible CLI
in `cli-min-version`; a newer CLI is fine. Updating one does not automatically update
the other.

## 1. Check and update the CLI

Run `bash "<PLUGIN_ROOT>/scripts/check-cli.sh" plain`, resolving `<PLUGIN_ROOT>` two
levels above this skill. If it reports a missing, old, or plugin-managed executable,
follow the `cli-setup` skill to locate the executable and choose the appropriate action:
existing native CLIs upgrade through their own `clay update`, npm CLIs through npm,
and missing or plugin-managed CLIs use installation or migration. An old plugin forwarder needs
migration even when a cached launcher still responds. Preserve the installation method
and existing sign-in.

Once the independent executable works, run `clay update --check` to check the latest
published release. Show the user what's new from the release URL when one is returned.
For a native installation, run `clay update`. For an npm installation, use
`npm install --global --ignore-scripts @clay-run/cli@latest`; `clay update` identifies
npm installs and provides that direction. Use the verified absolute executable path
if the current session's PATH has not refreshed.

## 2. Update the plugin

The marketplace is named `clay-plugins` and the plugin is `clay`. Pick your harness:

### Claude Code

Refresh the marketplace, then update the plugin:

```bash
claude plugin marketplace update clay-plugins
claude plugin update clay@clay-plugins
```

Then have the user run `/reload-plugins` (or restart Claude Code) so the new version
loads. If the plugin still shows the old version after that, the marketplace
clone was stale — the explicit `claude plugin marketplace update clay-plugins` above
force-refreshes it; as a last resort, uninstall and reinstall the `clay` plugin.

### Codex

Refresh the marketplace snapshot, then restart the Codex session:

```bash
codex plugin marketplace upgrade clay-plugins
```

`codex plugin marketplace upgrade` pulls the latest plugin version; restart Codex so
the running session picks it up.

### Cursor

Cursor is UI-driven — tell the user to do this (there's no reliable CLI path):

- Open **Customize** in the sidebar, find the **Clay** plugin, and click **Refresh**.
- With Auto Refresh enabled, Cursor picks up new commits atomically on its next refresh
  cycle; a manual **Refresh** forces it.
- If the content still looks stale, uninstall and reinstall the Clay plugin.

## 3. Verify both installations

After refreshing the plugin, read its new `cli-min-version` and run its
`scripts/check-cli.sh` again. If the minimum increased, run the current plugin's
`cli-setup` skill. Confirm `clay --version` is at least that minimum. Only investigate
sign-in if an authenticated command reports an auth error; an update does not require
another login.

The session-start hook makes the same local readiness check. It does not poll releases
or install software. Hosts without hooks use the `clay` skill's readiness check instead.
