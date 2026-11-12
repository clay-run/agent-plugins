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
# pathname/extglob/brace/tilde/=path expansion can't turn `echo .*` into a cwd
# listing under auto-approve.
# Semicolon-chained clauses may only use `clay`, `echo`, or `printf` (not the
# rest of this list).
allowed_helpers="jq cat head tail wc grep sort uniq column tr echo printf"

# Credential/egress and self-update `clay` subcommands that never auto-approve
gated_subcommands="feedback login logout api-keys webhooks update"

# Multi-word `clay` prefixes that never auto-approve. Entries are comma-separated;
# words within an entry are space-separated (e.g. "credits top-up,routines start").
gated_prefixes="credits top-up"

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
#   - at least one segment across all clauses must be `clay`, so the
#     pipeline/chain stays anchored to a clay call wherever it sits. `--output`
#     writes a file and must name a plain `.csv` file in cwd. No other clay
#     argument (positional, or a `--flag=value` value) may name a path outside
#     cwd -- one that starts with `/` or `~`, or has a `..` component -- because
#     file flags such as `--file`, `--inputs`, and `--input` read that path and
#     upload it to Clay. Quotes are removed first, so `"/etc/passwd"` is caught;
#     inline JSON and `-` (stdin) still auto-approve. A cwd-relative word can
#     still be a symlink to a file outside cwd, so the awk pass also prints
#     every word of the clay and file-reading helper segments, and the shell
#     check after it refuses if any of them, or any directory on its path, is
#     a symlink in the event's cwd;
#   - the `clay` segment's first non-flag word is refused if it is a
#     credential/egress subcommand (feedback, login, logout, api-keys,
#     webhooks) or if its leading non-flag words match any gated prefix
#     (e.g. credits top-up) so billing checkout never auto-approves;
#     non-flag words are dequoted before option classification and gate compare,
#     and each gate-compared prefix word must match ^[A-Za-z0-9][A-Za-z0-9_-]*$
#     so shell-expansion tokens cannot slip past a literal prefix match;
#     `clay credits balance` still auto-approves;
#   - within a `|` pipeline that contains `clay`, every other segment's command
#     must be in the helper allowlist (membership is an exact key lookup, so a
#     token like `*` can't wildcard its way in);
#   - semicolon clauses with no `clay` may only be `echo` or `printf` -- not
#     file-reading helpers -- so `cat .env; clay whoami` cannot auto-approve
#     and print a cwd file straight into the agent context;
#   - every helper segment (including echo/printf, on both `|` and `;`) must
#     not contain an unquoted shell metacharacter (`*`, `?`, `[`, `]`, `~`,
#     `{`, `}`, `(`, `)`, or word-leading `=`) -- not an exhaustive shell
#     parser, but enough to block pathname/extglob/brace/tilde/=path expansion
#     so `echo .*` / `cat *.env` can't become a cwd listing under
#     auto-approve; mid-word `=` (e.g. `--filter key=value`), `@` in values
#     (e.g. `test@example.com`), and bare `+`/`!`/`^` (which only reach
#     extglob via the already-refused `(`) are allowed; quoted forms like
#     `echo "*"` are fine;
#   - every non-echo/printf helper segment must not reference a path (`/`, `~`)
#     or a read/write file flag (long `--output`/`--file` or short clusters
#     containing `o`/`f`, attached value or not) -- helpers must transform
#     stdin, not open files. These checks apply to helpers on both sides of
#     clay, so neither `cat /etc/passwd | clay` nor `clay | cat /etc/passwd`
#     slips by, and `clay | sort -oPWNED.txt` can't write a cwd file; quoted
#     text is scanned too, so cat "/etc/passwd" can't either. `echo` and
#     `printf` are exempt from the path/flag guards (a `/` in their args is
#     data -- JSON, a URL -- not a file read) but not from the unquoted
#     shell-metachar guard. The `$`-reject guard above is what keeps remaining
#     args literal -- otherwise `printf "$SECRET"` would expand an env var
#     into clay's stdin under the echo/printf exemption;
#   - a jq segment must not use the `env` builtin or load code the command
#     text does not show (`import`, `include`, `--from-file`): jq reads the
#     whole process environment through `env` with no `$`. Quotes are
#     removed before this check, so `e''nv` cannot hide the word.
# Residual, knowingly accepted for `|` only: bare cwd-relative names (e.g.
# `cat .env | clay`) aren't caught; since no allowlisted helper can reach the
# network or redirect, such a read stays in the agent's context and still can't
# be exfiltrated without a separate, non-approved (prompted) command. Semicolon
# chaining no longer widens that residual to standalone helper stdout.
verdict="$(printf '%s' "$cmd_stripped" | awk -v helpers="$allowed_helpers" -v gated="$gated_subcommands" -v gatedpfx="$gated_prefixes" '
  BEGIN {
    n = split(helpers, a, " ")
    for (i = 1; i <= n; i++) H[a[i]] = 1
    nd = split(gated, d, " ")
    for (i = 1; i <= nd; i++) D[d[i]] = 1
    # gatedpfx: comma-separated entries; each entry is space-separated words.
    # Pwords[e,k] = kth word of entry e; Plen[e] = word count; nPfx = entries.
    nPfx = 0
    max_pfx_len = 0
    ne = split(gatedpfx, entries, ",")
    for (e = 1; e <= ne; e++) {
      entry = entries[e]
      gsub(/^[ \t]+|[ \t]+$/, "", entry)
      if (entry == "") continue
      nPfx++
      nw = split(entry, words, /[ \t]+/)
      Plen[nPfx] = 0
      for (k = 1; k <= nw; k++) {
        if (words[k] == "") continue
        Plen[nPfx]++
        Pwords[nPfx, Plen[nPfx]] = words[k]
      }
      if (Plen[nPfx] > max_pfx_len) max_pfx_len = Plen[nPfx]
    }
    sq = sprintf("%c", 39)
    cand = ""
  }
  # Strip matching surrounding quotes, then remove any remaining quote chars.
  function dequote_word(w,    q, last) {
    if (length(w) >= 2) {
      q = substr(w, 1, 1)
      last = substr(w, length(w), 1)
      if ((q == "\"" || q == sq) && last == q) {
        w = substr(w, 2, length(w) - 2)
      }
    }
    gsub(/"/, "", w)
    gsub(sq, "", w)
    return w
  }
  # True if t has an unquoted shell metachar that can trigger pathname/extglob/
  # brace/tilde/=path expansion (* ? [ ] ~ { } ( ), or word-leading =).
  # Mid-word = and bare @ are allowed. Not an exhaustive shell parser.
  # Extglob needs its `(`, so rejecting ( ) already covers +( and !( -- a bare
  # + ! or ^ carries no expansion meaning and must not deny a value like
  # `--filter email=test+tag@example.com`.
  function has_unquoted_shell_metachar(t,    i, c, inq, prev) {
    inq = ""
    for (i = 1; i <= length(t); i++) {
      c = substr(t, i, 1)
      if (inq != "") { if (c == inq) inq = ""; continue }
      if (c == sq || c == "\"") { inq = c; continue }
      if (c == "=") {
        prev = (i == 1) ? "" : substr(t, i - 1, 1)
        if (prev == "" || prev ~ /[ \t]/) return 1
        continue
      }
      if (c == "*" || c == "?" || c == "[" || c == "]" || c == "~" || c == "{" || c == "}" || c == "(" || c == ")") return 1
    }
    return 0
  }
  # Accepts only a plain cwd file name, optionally wrapped in one pair of quotes,
  # so `--output` cannot replace a dot file or a file outside cwd.
  function is_cwd_csv(v,    q) {
    q = substr(v, 1, 1)
    if ((q == "\"" || q == sq) && length(v) >= 2 && substr(v, length(v), 1) == q) {
      v = substr(v, 2, length(v) - 2)
    }
    return v ~ /^[A-Za-z0-9_][A-Za-z0-9._-]*\.csv$/
  }
  function has_unsafe_output(w, m,    j, f) {
    for (j = 1; j <= m; j++) {
      f = dequote_word(w[j])
      if (f == "--output") {
        if (j == m || !is_cwd_csv(w[j + 1])) return 1
        j++
      } else if (substr(f, 1, 9) == "--output=") {
        if (!is_cwd_csv(substr(w[j], index(w[j], "=") + 1))) return 1
      }
    }
    return 0
  }
  function names_path_outside_cwd(w, m,    j, v) {
    for (j = 1; j <= m; j++) {
      v = dequote_word(w[j])
      if (substr(v, 1, 1) == "-" && index(v, "=") > 0) v = substr(v, index(v, "=") + 1)
      if (v ~ /^[\/~]/ || v ~ /(^|\/)\.\.(\/|$)/) return 1
    }
    return 0
  }
  # Collect each shell word of t (quote-aware, quotes removed) plus the value of
  # a `--flag=value` or `-fvalue` word, one per line, for the symlink check.
  function add_candidate(v) {
    cand = cand "\n" v
    if (substr(v, 1, 1) != "-") return
    if (index(v, "=") > 0) cand = cand "\n" substr(v, index(v, "=") + 1)
    else if (substr(v, 2, 1) != "-" && length(v) > 2) cand = cand "\n" substr(v, 3)
  }
  function collect_words(t,    i, c, inq, cur, have) {
    inq = ""; cur = ""; have = 0
    for (i = 1; i <= length(t); i++) {
      c = substr(t, i, 1)
      if (inq != "") { if (c == inq) inq = ""; else cur = cur c; continue }
      if (c == sq || c == "\"") { inq = c; have = 1; continue }
      if (c == " " || c == "\t") {
        if (have || cur != "") add_candidate(cur)
        cur = ""; have = 0
        continue
      }
      cur = cur c
    }
    if (have || cur != "") add_candidate(cur)
  }
  # Dequote each token before option classification and prefix/subcommand gates.
  function check_clay(t,    rest, m, w, j, sc, words, nw, e, pfx_match) {
    # Same policy as helpers: unquoted shell metachars (* ? [ ] ~ { } ( ), or
    # word-leading =) must not auto-approve; mid-word = and bare @ are
    # allowed. Gate-compared prefix words must match
    # ^[A-Za-z0-9][A-Za-z0-9_-]*$ (flag tokens skipped before this check).
    if (has_unquoted_shell_metachar(t)) return 0
    rest = t
    sub(/^clay([ \t]+|$)/, "", rest)
    m = split(rest, w, /[ \t]+/)
    if (has_unsafe_output(w, m)) return 0
    if (names_path_outside_cwd(w, m)) return 0
    sc = ""
    nw = 0
    for (j = 1; j <= m; j++) {
      if (w[j] == "") continue
      w[j] = dequote_word(w[j])
      if (substr(w[j], 1, 1) == "-") continue
      if (w[j] !~ /^[A-Za-z0-9][A-Za-z0-9_-]*$/) return 0
      if (nw == 0) sc = w[j]
      words[++nw] = w[j]
      if (max_pfx_len > 0 && nw >= max_pfx_len) break
    }
    for (e = 1; e <= nPfx; e++) {
      if (nw < Plen[e]) continue
      pfx_match = 1
      for (j = 1; j <= Plen[e]; j++) {
        if (words[j] != Pwords[e, j]) { pfx_match = 0; break }
      }
      if (pfx_match) return 0
    }
    if (sc ~ /[][*?]/) return 0
    if (sc in D) return 0
    return 1
  }
  function jq_reaches_env(t,    u) {
    u = t
    gsub(/"/, "", u)
    gsub(sq, "", u)
    if (u ~ /(^|[^A-Za-z0-9_.])(env|import|include)([^A-Za-z0-9_]|$)/) return 1
    if (u ~ /(^|[ \t])--from-file([ \t]|=|$)/) return 1
    return 0
  }
  function check_helper(t, tok, pipe_ok,    allow) {
    if (pipe_ok) {
      if (!(tok in H)) return 0
      allow = 1
    } else {
      if (tok != "echo" && tok != "printf") return 0
      allow = 1
    }
    # Shared across | and ; : refuse unquoted shell metachars (* ? [ ] ~ { } (
    # ), or word-leading =) so echo/printf (and other helpers) cannot expand
    # into a cwd listing under auto-approve; mid-word = and bare @ are
    # allowed.
    if (allow && has_unquoted_shell_metachar(t)) return 0
    if (allow && tok == "jq" && jq_reaches_env(t)) return 0
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
        if (tok != "echo" && tok != "printf") collect_words(t)
      }
    }
    if (saw_clay) printf "allow%s\n", cand
  }
')"

[ "$(printf '%s\n' "$verdict" | sed -n 1p)" = "allow" ] || exit 0

# True if $1, or any directory on its cwd-relative path, is a symlink.
names_symlink() {
  _prefix=""
  _ifs="$IFS"
  IFS=/
  for _part in $1; do
    _prefix="${_prefix:+$_prefix/}$_part"
    if [ -n "$_part" ] && [ -L "$_prefix" ]; then
      IFS="$_ifs"
      return 0
    fi
  done
  IFS="$_ifs"
  return 1
}

event_cwd="$(printf '%s' "$input" | jq -r '.cwd // empty' 2> /dev/null)"
if [ -n "$event_cwd" ]; then
  cd "$event_cwd" 2> /dev/null || exit 0
fi
printf '%s\n' "$verdict" | sed 1d | {
  while IFS= read -r word; do
    [ -n "$word" ] || continue
    if names_symlink "$word"; then exit 1; fi
  done
  exit 0
} || exit 0

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
