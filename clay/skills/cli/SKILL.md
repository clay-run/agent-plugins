---
name: cli
description: Clay CLI — the primary scripting surface (JSON output, typed errors). Use when running or discovering `clay` commands. For what Clay can do and which skill to use, read the `clay` skill when it is available; otherwise run `clay --help`. Use `clay --help` for command names, flags, JSON shape, and error codes.
---

# The `clay` CLI

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

The `clay` CLI provides command-line access optimized for agents: JSON
output and typed error codes. For tool access or authentication problems, read the `clay` entry skill before continuing. The workspace is resolved from
the stored session — there is no workspace id to pass.

## Use workspace context internally

Once the CLI knows which workspace a credential is for, every successful command's JSON
carries a `workspace: { id, name }` key naming the workspace it authenticated as. Use this
information internally. Only mention authentication, the user, or the workspace when the
user asks or an actual account/workspace issue needs their attention. Running the first
command, receiving identity in a result, or loading this skill later in a conversation
does not call for an identity announcement. This applies to managed and standalone CLI
sessions. Don't ask the user for workspace information merely because the key is absent — it is
absent when a command never had to resolve the workspace, and when its result is a top-level
JSON array with nowhere to put it.

A browser sign-in covers every workspace the user selects on the consent screen, and leaves
the first one selected active; `clay login --device` covers one workspace per run. Either way
the workspaces already signed in are kept, so `clay login` again adds more rather than
replacing them. `clay workspaces list` shows the ids and `clay workspaces switch <id>` moves
between them, so switch explicitly to work in one the sign-in did not leave active. When a
payload carries no workspace key and you need to know, `clay workspaces current` answers
directly. Inside a managed Clay session none of this applies: the session runs in the one
workspace it was created in, and `clay login` / `clay logout` / `clay workspaces` are
unavailable there. Never ask the user to sign in — but if they ask to work in a different
workspace, tell them to switch workspaces in Clay and start a new chat there, since this
session cannot move.

## Discovering commands

When a user asks what they can do with Clay, use the `clay` skill when it is available — that is the table of
contents for product surfaces. This skill is how to invoke the CLI.

`clay --help` is the live list of top-level commands. The help text is a machine-readable
spec: use it for command names, flags, JSON output shape, and error codes. Do not treat
it as the answer to "what can I do with Clay?"

```bash
clay --help                 # top-level commands
clay <group> --help         # a group's subcommands
clay <group> <cmd> --help   # exact flags, JSON output shape, and error codes
```

## Prefer simple, single commands

Prefer running one plain `clay` command at a time. Avoid redirecting or
substituting (`&&`, `||`, `>`, `$(…)`, backticks, `$VAR`, etc.) unless it's genuinely
necessary — those forms fall through to a manual approval prompt, whereas a simple
`clay <group> <cmd>` call is auto-approved.

Piping (`|`) is fine when the other stages are common read-only helpers like `jq` that
transform stdin without opening files. Semicolon chaining (`;`) is narrower: each
clause must be `clay`, or a literal `echo` / `printf` (not `cat` / `jq` / …). Anything
else falls through to a prompt.

## When a command needs approval

Some commands that delete, send or run things at scale can answer `approval_required`
instead of running. Nothing has happened yet: tell the user what the request would do (from
the error's `details`) and let them decide. `clay approvals approve <requestId>` runs it and
`clay approvals deny <requestId>` drops it. Inside a managed Clay session the person decides in
Clay instead, and the `clay approvals` commands are unavailable.

When `clay approvals get <requestId>` shows an `offeredRule`, `clay approvals approve <requestId>
--always-allow` also saves it, so the user's later CLI calls for that action run without asking.
Only add `--always-allow` when the user asks for it. `clay approvals rules list` shows their saved
rules and `clay approvals rules delete <ruleId>` removes one.

## When to use the CLI vs the Public API

Use the CLI for scripting and agent-driven tasks in a shell. To build a service, app,
or integration that talks to Clay over HTTP, use the **Public API** (`public-api` skill).

Full developer documentation (CLI reference, Public API reference, concepts, OpenAPI
spec) lives at: https://developers.clay.com/llms.txt
