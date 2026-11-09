---
name: onboard
description: Clay first-run onboarding — banner, what Clay can do, and starter tasks served by the Clay API. Run this right after a sign-in that just happened — from `clay login` directly, or invoked by the CLI setup skill after its sign-in step. It checks server-side whether this user has been onboarded and stands down if so. Assumes the CLI is already signed in; for access or authentication problems, consult the clay entry skill first.
allowed-tools: Bash, Read
---

# Clay onboarding

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

Before continuing, read the `clay` entry skill and follow its access guidance.

Give a brand-new user a fast first win. Whether this user has already been
onboarded is tracked server-side, per user: `clay login` and `clay whoami`
report it as `onboarded`, and fetching the starter-task options marks them as
onboarded. There is nothing to record locally.

**This skill runs signed-in.** For access or authentication problems, consult the
`clay` entry skill before continuing. If CLI access uses an absolute executable
path, use that path in the examples below.

**The user's own request always wins.** If sign-in was just a prerequisite for
something concrete they asked for ("get this person's work email", a table
query, a fix for a broken tool), do not run the onboarding menu now — finish
their request; their own task is a better first win than a menu. After it's
done, a one-line offer of the starter tasks is fine if it fits the moment.
Since the options were never fetched, they stay un-onboarded server-side, so a
future login can still make the offer cleanly. Run onboarding immediately only
when there's no concrete task waiting: the user asked to get started, just
installed the plugin, or setup itself was the whole request.

Keep your own prose short — the banner and the starter tasks are the show. The
welcome (steps 2–3) goes on screen before you fetch anything; never repeat it
within a session.

## 1. Check that onboarding applies

If the sign-in that brought you here already reported `onboarded: false`, skip
this check and continue. Otherwise read the field yourself:

```bash
clay whoami
```

- **`onboarded: false`** — continue to step 2.
- **`onboarded: true`** — they've been onboarded before (possibly on another
  machine). Stand down: skip the rest of this skill without ceremony. If the
  banner already went up (the Claude Code hook shows it at invocation), a
  one-line welcome back is enough — no pitch, no menu.
- **The field is absent** — do not infer onboarding status. Consult the `clay` entry
  skill if access needs repair; otherwise stand down.

## 2. Show the banner

On Claude Code, when this skill was invoked through the Skill tool **and**
`command -v jq` succeeds, skip this step: a plugin hook displays the banner
automatically at that invocation (it needs `jq` to do so) — never print it
yourself; the step-3 pitch still opens your reply. In every other case — no
`jq`, any other host, or following this file directly as a runbook (no Skill
tool call, so no hook fired) — print a banner file from this skill's directory
**verbatim** inside a fenced code block, before any other tool call
(`AskUserQuestion` included). Pick the file by terminal width: run
`printf '%s\n' "${COLUMNS:-0}"` and use `banner.txt` only when it prints a
number of 115 or more; on anything smaller, non-numeric, or a failed probe,
use `banner-narrow.txt` — it fits every host. Exception: a number from 1 to
39 means the pane is too narrow even for the narrow art — show no banner at
all and go straight to step 3. Do not redraw, trim, or restyle
the art. Reading the file is not showing it: the banner must appear in your
reply to the user.

## 3. Say what Clay is

Position it as Clay's product and theirs to run ("Clay lets you…", "you can…"),
not as your own abilities. Two or three sentences: Clay is a GTM data and
automation platform — search hundreds of millions of people and companies,
enrich them with verified emails, phone numbers, firmographics, and tech stacks,
and automate the whole thing with functions and workflows.

Then show the breadth in a compact "you can ask me to…" list — four or five
one-line bullets, phrased as plain asks, e.g.: find people or companies matching
a profile, get verified emails for a list, see what technologies a company uses,
query and export your existing Clay tables, build a workflow around a webhook,
check your credit balance. No CLI command syntax and no skill names — the user
talks to you, not to the CLI. If they ask for the full command surface, show
them live `clay --help` output instead of reciting a remembered list.

## 4. Fetch and offer the starter tasks

```bash
clay onboard options
```

This returns the current option set (`{ data: [{ id, label, description }] }`)
and marks the user as onboarded server-side. **Present exactly what it
returns** — the options are server-controlled and may differ from anything you
remember. If the `AskUserQuestion` tool is available, use it (single-select)
with each option's `label` and `description`, and don't add a free-form option
of your own ("Type something", "Other") — the tool renders its own escape
hatch. Without the tool, present a numbered list ending with one extra line:
they can also just say what they'd like to do instead.

If the onboarding operation is unavailable, consult the `clay` entry skill for
access guidance. Do not install tools as part of onboarding.

For any other failure (network, server trouble), don't block and don't
diagnose — no error-hunting, no environment debugging, no mention of what went
wrong. Just ask the user what they'd like to do with Clay and help with that
directly; the rest of this skill doesn't apply.

## 5. Record the selection and run the task

For an option from the list:

```bash
clay onboard select <option-id>
```

This records the pick and returns `instructions` — follow them as if the user
had asked for that task directly. If the independent CLI's directory is not on PATH in this session,
use the verified absolute executable path from setup for the selected task too.

If `select` fails, proceed anyway: treat the option's label as the user's
request — but still get the user's explicit go-ahead before running anything
that spends credits; the guidance a successful `select` returns requires that,
and its absence doesn't waive it. Never block on the recording, diagnose it,
retry it more than once, or mention it to the user.

If the user picks something outside the list (e.g. "Other"), skip `select` and
just help with what they asked.
