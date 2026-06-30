---
name: clay-feedback
description: Clay feedback — send a bug report or product feedback to the Clay team via the `clay feedback` CLI, optionally including this session's transcript.
allowed-tools: Bash(clay *), Bash(ls *), Bash(pwd), Bash(sed *), Bash(head *), Bash(rm *), Write, AskUserQuestion
---

# Clay Feedback

Send feedback or a bug report to the Clay team using `clay feedback`. It reads the message from **stdin** and automatically attaches environment details. To include this conversation's transcript, you attach it explicitly with `--transcript-file` — the CLI does not look for it on its own.

The transcript is the **current conversation**, so confirm with the user before sending (the CLI does no confirmation of its own).

## Steps

1. **Get feedback text.** Use the argument if provided (e.g. `/clay-feedback the enrichment table returns no results`). Otherwise ask the user what feedback or bug report they'd like to send.

2. **Find this session's transcript — you attach it, the CLI won't.** You are responsible for locating the current conversation's transcript file and passing its path to `--transcript-file` in step 4. Use whatever your runtime exposes:

   - **Claude Code:** the newest `.jsonl` under the project dir whose name is the working directory with `/` and `.` replaced by `-` (checking the normal home and the Cowork mount):

     ```bash
     proj="$(pwd | sed 's#[/.]#-#g')"
     ls -t "$HOME"/.claude/projects/"$proj"/*.jsonl "$HOME"/mnt/.claude/projects/"$proj"/*.jsonl 2>/dev/null | head -1
     ```

   - **Other runtimes (Codex, Cursor, …):** locate the current session transcript the way your client stores it.

   If you can't determine a transcript path, proceed without one — the report still sends.

3. **Confirm.** Use AskUserQuestion. List what the report will include:

   > This report will include:
   >
   > - Your feedback: {feedback text}
   > - This conversation's transcript *(only if step 2 found one)*
   > - Environment info (auto-collected)
   >
   > Send this feedback?

   - If step 2 found a transcript, offer "Send with transcript" / "Send without transcript" / "Cancel". The transcript is the full conversation, so let the user opt out (e.g. privacy-sensitive) by sending without it.
   - If step 2 found none, drop the transcript line and offer just "Send" / "Cancel".

4. **If confirmed**, send the message on stdin. The CLI reads the feedback from stdin. Do **not** pass it inline in the shell command (no heredoc, no `echo`): the feedback is arbitrary user text, and a here-doc delimiter or quote appearing in it would truncate or mis-parse the message — or let pasted text run as shell. Instead, write the text to a temp file with your file-writing tool (which never goes through the shell), then redirect that file into the command. Substitute the path from step 2 directly — each Bash call is a fresh shell, so a variable set in step 2 won't survive here. Include `--transcript-file` only if the user chose to send the transcript:

   - Write the feedback text verbatim to a temp file, e.g. `/tmp/clay-feedback.txt`.
   - Then run:

   ```bash
   clay feedback --transcript-file <path from step 2> < /tmp/clay-feedback.txt
   rm -f /tmp/clay-feedback.txt
   ```

   To send without the transcript, omit `--transcript-file` entirely.

5. **Interpret the JSON output** (printed on success, exit 0):

   ```json
   { "ok": true, "includedTranscript": true, "environment": { ... } }
   ```

   `transcriptError` appears only when you passed `--transcript-file` but it couldn't be attached (missing, unreadable, or too large).

   - If `includedTranscript` is `false` and `transcriptError` is set, the report was **still sent** — only the transcript was skipped. Tell the user; double-check the path from step 2 before retrying.
   - `validation_error` (exit 2) — the stdin message was empty or nothing was piped. Make sure the temp file has the feedback text and is redirected in (`< /tmp/clay-feedback.txt`).
   - `auth_missing_api_key` (exit 3) — Clay isn't authenticated. Run the `setup` skill or `clay login`, then retry.
   - `rate_limited` (exit 4) — too many reports recently; surface `details.retryAfter` and try again later.

6. Tell the user it was sent, noting whether the transcript was included. If cancelled, do nothing.
