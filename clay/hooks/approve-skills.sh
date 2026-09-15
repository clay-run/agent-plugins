#!/bin/sh
# Approval hook for the Clay plugin, wired only for Claude Code. Companion to
# approve-clay.sh (which auto-approves the `clay` CLI). This one auto-approves
# invoking Clay's own plugin skills, so the agent stops asking on every call.
#
#   claude -> PreToolUse  (input .tool_name, .tool_input.skill)
#
# Wire it with the hook `matcher` set to "Skill"; the script then dispatches on
# tool_name.
#
# Scope is deliberately limited to the Skill tool. An approval that covers a
# tool the user drives elsewhere -- WebFetch and WebSearch especially -- would
# suppress Claude Code's own per-site prompt for the whole session, well beyond
# Clay's own work.
#
# Cursor and Codex are deliberately omitted -- neither exposes a permission
# event this hook can attach to, so there is no prompt to skip and nothing to
# auto-approve. (approve-cli.sh still wires both, because their `clay` CLI
# calls run through Cursor's beforeShellExecution and Codex's
# PermissionRequest/Bash surfaces.)

# Anything that isn't recognized falls through to the normal prompt (exit 0, no output).

# Harden: no globbing, and unset variables are errors so a typo can't silently
# widen approval.
set -fu

# Fail open to the normal prompt if we lack jq to parse the event.
command -v jq > /dev/null 2>&1 || exit 0

input="$(cat)"

# Claude's PreToolUse event exposes the tool name at .tool_name; anything else
# comes back empty and falls through below.
tool="$(printf '%s' "$input" | jq -r '.tool_name // empty' 2> /dev/null)"
[ -n "$tool" ] || exit 0

approve=0

# The Skill tool carries the skill being invoked at .tool_input.skill. Only
# Clay's own skills are approved; any other skill falls through to the prompt.
if [ "$tool" = "Skill" ]; then
  skill="$(printf '%s' "$input" | jq -r '.tool_input.skill // empty' 2> /dev/null)"
  # Strip an optional "clay:" plugin-namespace prefix (a plugin skill may arrive
  # as either `clay:cli` or `cli`), then require a bare skill identifier. The
  # charset guard rejects anything with `/`, `.`, or `~`, so a crafted name
  # can't traverse out of the skills directory in the lookup below.
  skill="${skill#clay:}"
  case "$skill" in
    '' | *[!A-Za-z0-9_-]*) skill="" ;;
  esac
  if [ -n "$skill" ]; then
    # Prefer the plugin root the harness exports; fall back to this script's
    # location (hooks/ lives directly under the plugin root).
    plugin_root="${CLAUDE_PLUGIN_ROOT:-}"
    [ -n "$plugin_root" ] || plugin_root="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
    # Authoritative allowlist: the plugin's own skills. Each skill's `name:`
    # frontmatter equals its directory name, so a directory match is exactly a
    # real Clay skill -- and it never drifts as skills are added or removed.
    [ -f "$plugin_root/skills/$skill/SKILL.md" ] && approve=1
  fi
fi

[ "$approve" -eq 1 ] || exit 0

reason="Clay skills are allowlisted by the Clay plugin"

# Invoking the onboard skill also displays the Clay banner, as a systemMessage
# attached to this verdict — the moment onboarding actually starts. Display
# can't be left to the model: harness-trained terseness makes agents reliably
# skip verbatim ASCII art no matter what the skill demands. Once per session,
# so a re-invocation can't repeat it.
if [ "${skill:-}" = "onboard" ]; then
  session_id="$(printf '%s' "$input" | jq -r '.session_id // empty' 2> /dev/null)"
  guard="${TMPDIR:-/tmp}/clay-onboard-banner-${session_id:-unknown}"
  # Pick the banner by width. Claude Code exports COLUMNS to hook processes
  # when a real terminal is attached; webview hosts (desktop app, IDE
  # extensions) leave it unset or 0, and /dev/tty is never available, so
  # COLUMNS is the only signal. The wide banner is 105 columns plus the UI's
  # gutter, hence the 115 threshold; anything narrower or unknowable gets the
  # 37-column logo-only variant.
  cols="${COLUMNS:-0}"
  case "$cols" in '' | *[!0-9]*) cols=0 ;; esac
  # A width confirmed to be below even the narrow art would wrap any banner
  # into noise: show none. The guard stays unset so a wider re-invocation can
  # still show one.
  fits=1
  [ "$cols" -gt 0 ] && [ "$cols" -lt 40 ] && fits=0
  banner_dir="$plugin_root/skills/onboard"
  banner_name="banner-narrow"
  [ "$cols" -ge 115 ] && banner_name="banner"
  # Prefer the ANSI-colored variant only when a terminal is confirmed (jq
  # escapes the color bytes into valid JSON): the no-width webview hosts are
  # the same ones that show raw escape codes instead of color. banner*.txt
  # stays plain for the hosts where the model prints it into a markdown code
  # block. NO_COLOR (https://no-color.org) also opts out.
  banner_file="$banner_dir/$banner_name-ansi.txt"
  if [ "$cols" -eq 0 ] || [ -n "${NO_COLOR:-}" ] || [ ! -f "$banner_file" ]; then
    banner_file="$banner_dir/$banner_name.txt"
  fi
  if [ "$fits" -eq 1 ] && [ ! -e "$guard" ] && [ -f "$banner_file" ]; then
    : > "$guard" 2> /dev/null
    jq -Rs --arg reason "$reason" \
      '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: $reason}, systemMessage: .}' \
      < "$banner_file"
    exit 0
  fi
fi

# Emit Claude's PreToolUse allow verdict. Only reached after the checks above
# pass, so we never allow anything we haven't vetted.
printf '%s\n' "{\"hookSpecificOutput\":{\"hookEventName\":\"PreToolUse\",\"permissionDecision\":\"allow\",\"permissionDecisionReason\":\"$reason\"}}"
