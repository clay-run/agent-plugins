---
name: clay-feedback
description: Clay feedback — send a bug report or product feedback to the Clay team via the `clay feedback` CLI.
allowed-tools: Bash(clay *), Bash(rm *), Write, AskUserQuestion
---

# Clay Feedback

Send feedback or a bug report to the Clay team using `clay feedback`. It reads the message from **stdin** and automatically attaches environment details.

The CLI does no confirmation of its own, so confirm with the user before sending.

Feedback is one-way: it lands in the Clay team's triage queue and nobody replies. When the
user wants a human who responds — they explicitly ask for support, or the matter needs staff
action (a disputed or duplicate charge, a refund, account recovery) — use `clay support`
instead (see the `clay` skill's "Getting help and reporting problems"). Product feedback
_about_ billing or plans (confusing UX, a feature request) is still feedback and belongs here.

## Steps

1. **Determine type.** The test is: did Clay fail, or behave differently from how it is documented or built to work? First occurrences count, and you do not need to know whether it worked before.
   - Choose `bug` for: errors, crashes, timeouts or hangs; failures on valid input; wrong, empty, stale or duplicated output; output that contradicts the docs or `--help`; data lost or changed unexpectedly; documented features that do not work.
   - Choose `feedback` only when Clay worked as designed and the user wants something different: feature requests, capabilities Clay does not claim to have, UX or naming suggestions, working-but-confusing flows, general ideas.
   - Tiebreaker: if the user saw an error or unexpected result while doing something Clay supports, use `bug`; if it is still ambiguous, use `bug` without asking.

2. **Get feedback text.** Use the argument if provided (e.g. `/clay-feedback would love CSV export from the enrichment table`). Otherwise ask the user what feedback or bug report they'd like to send. For a bug, include the command that was run, the error output, and expected versus actual behavior in the message.

3. **Confirm.** Use your ask-user tool (`AskUserQuestion`; `askUser` inside the Clay app). List what the report will include, and offer "Send" / "Cancel":

   > This report will include:
   >
   > - Type: {bug or feedback}
   > - Your feedback: {feedback text}
   > - Environment info (auto-collected)
   >
   > Send this feedback?

4. **If confirmed**, send the message on stdin. The CLI reads the feedback from stdin. Do **not** pass it inline in the shell command (no heredoc, no `echo`): the feedback is arbitrary user text, and a here-doc delimiter or quote appearing in it would truncate or mis-parse the message — or let pasted text run as shell. Instead, write the text to a temp file with your file-writing tool (which never goes through the shell), then redirect that file into the command. Always pass `--type bug` or `--type feedback` from step 1.
   - Write the feedback text verbatim to a temp file with an unpredictable name (a shared
     fixed path lets other local sessions read or clobber it), e.g. `/tmp/clay-feedback-<random>.txt`.
   - Then run:

   ```bash
   clay feedback --type <bug|feedback> < /tmp/clay-feedback-<random>.txt
   rm -f /tmp/clay-feedback-<random>.txt
   ```
