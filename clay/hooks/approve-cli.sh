#!/bin/sh
# Shared approval hook for the Clay plugin across Claude Code, Cursor, and Codex.
# Each agent prompts before running shell commands; this auto-approves a `clay`
# CLI call (optionally piped through a small set of read-only helpers, or
# `;`-chained with only `clay` / `echo` / `printf` clauses) so the plugin stops
# asking on every invocation. The verdict shape differs per agent, selected by
# the first argument: claude | cursor | codex.
#
#   claude -> PreToolUse           (input .tool_input.command)
#   codex  -> PermissionRequest    (input .tool_input.command)
#   cursor -> beforeShellExecution (input .command)
#
# "allow" only skips the prompt; deny/ask rules (including managed deny lists)
# still take precedence, so this can't punch through an admin block. Conservative
# by design: any command that redirects, substitutes, or expands the environment
# (`&`, `&&`, `||`, `>`, `<`, backticks, `$(…)`, any `$` parameter expansion
# like `$VAR`/`${VAR}`, or a backslash escape `\`) falls through to the normal
# prompt rather than being approved. Unquoted `|` and `;` are allowed as segment
# breaks under the rules below (see the awk pass); quoted `|`/`;` inside args
# are not separators. Semicolon clauses are stricter than pipes: file-reading
# helpers (`cat`, `jq`, …) are pipe-only, so `cat .env; clay whoami` cannot
# auto-approve and dump a cwd file into the agent context.

agent="${1:-claude}"

# Pipeline helpers allowed alongside `clay` when joined by `|`. Read-only by
# intent; this is the security-relevant surface, kept in one place for review.
# `echo`/`printf` never open a file or socket, so they are exempt from the
# path/file-flag guards below -- but unquoted glob/tilde chars are still
# refused for every helper (including echo/printf), on both `|` and `;`, so
# shell expansion can't turn `echo .*` into a cwd listing under auto-approve.
# Semicolon-chained clauses may only use `clay`, `echo`, or `printf` (not the
# rest of this list).
allowed_helpers="jq cat head tail wc grep sort uniq column tr echo printf"

# Credential/egress `clay` subcommands that never auto-approve
gated_subcommands="feedback login logout api-keys webhooks"

# Harden: no globbing, and unset variables are errors so a typo can't silently
# widen approval.
set -fu

# Fail open to the normal prompt if we lack the tools we rely on to parse the
# event (jq) or to vet the command (awk). Without awk the structure/operand
# checks can't run, so we must not approve.
command -v jq > /dev/null 2>&1 || exit 0
command -v awk > /dev/null 2>&1 || exit 0

input="$(cat)"

case "$agent" in
  cursor)
    # Cursor's beforeShellExecution event is shell-specific; command is top-level.
    cmd="$(printf '%s' "$input" | jq -r '.command // empty' 2> /dev/null)"
    ;;
  *)
    # Claude PreToolUse / Codex PermissionRequest both gate the Bash tool. One
    # jq pass yields the command only for Bash; anything else comes back empty
    # and falls through to the normal prompt below.
    cmd="$(printf '%s' "$input" | jq -r 'if .tool_name == "Bash" then .tool_input.command // empty else empty end' 2> /dev/null)"
    ;;
esac

[ -n "$cmd" ] || exit 0

# Strip harmless redirections before the safety checks so they don't block
# otherwise-valid clay pipelines. Only two shapes are removed: redirects whose
# target is /dev/null (anchored to a word boundary so we never eat a prefix of
# a real path like /dev/nullX), and fd-to-fd duplications (2>&1, 1>&2). Any
# redirection to a real file is intentionally left intact so it still falls
# through to the prompt.
cmd_stripped="$(printf '%s' "$cmd" | sed -E '
  s#([0-9]*|&)>>?[[:space:]]*/dev/null([[:space:]]|$)#\2#g
  s/[0-9]*>&[0-9]+//g
')"

# Reject redirection / substitution / env expansion / backgrounding outright.
# Runs on the raw (quoted) string so even a quoted `>`/`$`/etc. is conservatively
# refused. Unquoted `|` and `;` are handled as segment breaks in the awk pass
# below (not rejected here). The backslash is rejected too: the segment splitter
# below is not backslash-aware, so a `\"`/`\|`/`\;` would let awk and the shell
# disagree on where segments start and end (a total allowlist bypass). Refusing
# any `\` closes that desync.
case "$cmd_stripped" in
  *'&'* | *'<'* | *'>'* | *'`'* | *'$'* | *'\'*) exit 0 ;;
esac

# Reject multi-line commands (heredocs, embedded scripts).
[ "$(printf '%s' "$cmd_stripped" | wc -l | tr -d ' ')" = "0" ] || exit 0

# Bound the input so the char-by-char awk pass below can't be forced to scan an
# unbounded string.
[ "${#cmd_stripped}" -le 10000 ] || exit 0

# Validate the pipeline/chain in a single quote-aware pass. awk first splits on
# unquoted `;` into clauses, then each clause on unquoted `|` into segments (so
# a `|` or `;` inside jq/grep args or a quoted clay arg is not a separator; the
# `\`-reject guard above keeps this splitter in sync with the shell), trims
# surrounding whitespace per segment, then:
#   - any segment that leads with a `VAR=value` env-var assignment is rejected
#     outright -- we never vet the variable, so a prefix like `LD_PRELOAD=`,
#     `CLAY_API_URL=`, or `CLAY_CONFIG_HOME=` must not ride in as a plain call;
#   - at least one segment across all clauses must be `clay` (its own path/URL
#     args are left alone), so the pipeline/chain stays anchored to a clay call
#     wherever it sits;
#   - the `clay` segment's first non-flag word is refused if it is a
#     credential/egress subcommand (feedback, login, logout, api-keys,
#     webhooks) so those never auto-approve; ordinary read/write subcommands
#     (whoami, tables, routines, workflows, ...) still do;
#   - within a `|` pipeline that contains `clay`, every other segment's command
#     must be in the helper allowlist (membership is an exact key lookup, so a
#     token like `*` can't wildcard its way in);
#   - semicolon clauses with no `clay` may only be `echo` or `printf` -- not
#     file-reading helpers -- so `cat .env; clay whoami` cannot auto-approve
#     and print a cwd file straight into the agent context;
#   - every helper segment (including echo/printf, on both `|` and `;`) must
#     not contain an unquoted glob or tilde metacharacter (`*`, `?`, `[`, `~`),
#     so the shell can't expand `echo .*` / `cat *.env` into a cwd listing
#     under auto-approve; quoted forms like `echo "*"` are fine;
#   - every non-echo/printf helper segment must not reference a path (`/`, `~`)
#     or a read/write file flag (long `--output`/`--file` or short clusters
#     containing `o`/`f`, attached value or not) -- helpers must transform
#     stdin, not open files. These checks apply to helpers on both sides of
#     clay, so neither `cat /etc/passwd | clay` nor `clay | cat /etc/passwd`
#     slips by, and `clay | sort -oPWNED.txt` can't write a cwd file; quoted
#     text is scanned too, so cat "/etc/passwd" can't either. `echo` and
#     `printf` are exempt from the path/flag guards (a `/` in their args is
#     data -- JSON, a URL -- not a file read) but not from the unquoted
#     glob/tilde guard. The `$`-reject guard above is what keeps remaining
#     args literal -- otherwise `printf "$SECRET"` would expand an env var
#     into clay's stdin under the echo/printf exemption.
# Residual, knowingly accepted for `|` only: bare cwd-relative names (e.g.
# `cat .env | clay`) aren't caught; since no allowlisted helper can reach the
# network or redirect, such a read stays in the agent's context and still can't
# be exfiltrated without a separate, non-approved (prompted) command. Semicolon
# chaining no longer widens that residual to standalone helper stdout.
verdict="$(printf '%s' "$cmd_stripped" | awk -v helpers="$allowed_helpers" -v gated="$gated_subcommands" '
  BEGIN {
    n = split(helpers, a, " ")
    for (i = 1; i <= n; i++) H[a[i]] = 1
    nd = split(gated, d, " ")
    for (i = 1; i <= nd; i++) D[d[i]] = 1
    sq = sprintf("%c", 39)
  }
  # True if t has an unquoted *, ?, [, or ~ (shell glob / tilde expansion).
  function has_unquoted_glob_or_tilde(t,    i, c, inq) {
    inq = ""
    for (i = 1; i <= length(t); i++) {
      c = substr(t, i, 1)
      if (inq != "") { if (c == inq) inq = ""; continue }
      if (c == sq || c == "\"") { inq = c; continue }
      if (c == "*" || c == "?" || c == "[" || c == "~") return 1
    }
    return 0
  }
  function check_clay(t,    rest, m, w, j, sc) {
    rest = t
    sub(/^clay([ \t]+|$)/, "", rest)
    m = split(rest, w, /[ \t]+/)
    sc = ""
    for (j = 1; j <= m; j++) {
      if (w[j] == "") continue
      if (substr(w[j], 1, 1) == "-") continue
      sc = w[j]; break
    }
    gsub(/"/, "", sc); gsub(sq, "", sc)
    if (sc ~ /[][*?]/) return 0
    if (sc in D) return 0
    return 1
  }
  function check_helper(t, tok, pipe_ok,    allow) {
    if (pipe_ok) {
      if (!(tok in H)) return 0
      allow = 1
    } else {
      if (tok != "echo" && tok != "printf") return 0
      allow = 1
    }
    # Shared across | and ; : refuse unquoted glob/tilde so echo/printf
    # (and other helpers) cannot expand into a cwd listing under auto-approve.
    if (allow && has_unquoted_glob_or_tilde(t)) return 0
    if (allow && tok != "echo" && tok != "printf") {
      if (index(t, "/") > 0) return 0
      if (index(t, "~") > 0) return 0
      if (t ~ /(^|[ \t])--(output|file)([ \t]|=|$)/) return 0
      if (t ~ /(^|[ \t])-[A-Za-z]*[of]/) return 0
    }
    return 1
  }
  {
    inq = ""; nclause = 0; cur = ""
    for (i = 1; i <= length($0); i++) {
      c = substr($0, i, 1)
      if (inq != "") { cur = cur c; if (c == inq) inq = ""; continue }
      if (c == sq || c == "\"") { inq = c; cur = cur c; continue }
      if (c == ";") { clause[nclause++] = cur; cur = ""; continue }
      cur = cur c
    }
    clause[nclause++] = cur

    saw_clay = 0
    for (cl = 0; cl < nclause; cl++) {
      inq = ""; nseg = 0; cur = ""; cl_raw = clause[cl]
      for (i = 1; i <= length(cl_raw); i++) {
        c = substr(cl_raw, i, 1)
        if (inq != "") { cur = cur c; if (c == inq) inq = ""; continue }
        if (c == sq || c == "\"") { inq = c; cur = cur c; continue }
        if (c == "|") { seg[nseg++] = cur; cur = ""; continue }
        cur = cur c
      }
      seg[nseg++] = cur

      cl_clay = 0
      for (s = 0; s < nseg; s++) {
        t = seg[s]
        sub(/^[ \t]+/, "", t)
        sub(/[ \t]+$/, "", t)
        if (t == "") exit
        if (t ~ /^[A-Za-z_][A-Za-z0-9_]*=/) exit
        tok = t
        sub(/[ \t].*$/, "", tok)
        if (tok == "clay") cl_clay = 1
      }
      if (cl_clay) saw_clay = 1

      for (s = 0; s < nseg; s++) {
        t = seg[s]
        sub(/^[ \t]+/, "", t)
        sub(/[ \t]+$/, "", t)
        tok = t
        sub(/[ \t].*$/, "", tok)
        if (tok == "clay") {
          if (!check_clay(t)) exit
        } else if (!check_helper(t, tok, cl_clay)) {
          exit
        }
      }
    }
    if (saw_clay) print "allow"
  }
')"

[ "$verdict" = "allow" ] || exit 0

case "$agent" in
  cursor)
    printf '%s\n' '{"continue":true,"permission":"allow"}'
    ;;
  codex)
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PermissionRequest","decision":{"behavior":"allow"}}}'
    ;;
  claude | *)
    # claude (PreToolUse) is the default; an unknown agent also lands here, which
    # is safe because we only ever emit an allow after passing the checks above.
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"clay CLI is allowlisted by the Clay plugin"}}'
    ;;
esac
