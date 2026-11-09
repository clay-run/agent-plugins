#!/usr/bin/env bash

script_dir=$(cd -- "$(dirname -- "$0")" && pwd) || exit 0
source "$script_dir/cli-install-common.sh"
minimum=$(cat "$script_dir/../cli-min-version" 2>/dev/null)
message=
if ! clay_valid_version "$minimum"; then
  message='Clay plugin compatibility metadata is missing or invalid. Refresh the Clay plugin before using its CLI.'
else
  executable=$(command -v clay || true)
  if [ -z "$executable" ]; then
    message="Clay CLI setup required: no clay command is on PATH. Do not run clay directly. Invoke the Clay cli-setup skill first to install CLI $minimum or newer, then continue with the Clay task."
  else
    method=$(clay_install_method "$executable")
    case "$method" in
      legacy|legacy-npm)
        message="Clay CLI setup required: the clay command on PATH is a legacy plugin launcher or npm installation. Do not run clay directly, even if it works. Invoke the Clay cli-setup skill first to migrate to an independent CLI $minimum or newer (it preserves authentication and installation method), then continue with the Clay task."
        ;;
      *)
        version=$(clay_read_version "$executable" || true)
        if ! clay_version_at_least "$version" "$minimum"; then
          message="Clay CLI setup required: the clay command on PATH is outdated or cannot run. Do not run clay directly. Invoke the Clay cli-setup skill first to install CLI $minimum or newer (it preserves authentication and installation method), then continue with the Clay task."
        fi
        ;;
    esac
  fi
fi
[ -n "$message" ] || exit 0
message="For CLI access only: $message Honor the user's choice of CLI or MCP. For tasks already using connected Clay MCP tools, CLI installation and sign-in are unnecessary; skip cli-setup for those tasks."
case "${1:-plain}" in
  claude|codex) printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$message" ;;
  cursor) printf '{"additional_context":"%s"}\n' "$message" ;;
  *) printf '%s\n' "$message" ;;
esac
exit 0
