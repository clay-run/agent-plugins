---
name: cli
description: Clay CLI — the primary scripting surface (JSON output, typed errors). Discover the full command surface (workflows, tables, routines, webhooks, and more) and how to run any command; run `clay --help` for the authoritative list.
---

# The `clay` CLI

The `clay` CLI is Clay's primary programmatic surface, optimized for agents: JSON
output and typed error codes. It authenticates via **`clay login`** (browser OAuth;
run the `setup` skill once if `clay whoami` fails). The workspace is resolved from
the stored session — there is no workspace id to pass.

## Discovering what you can do

`clay --help` is the authoritative, up-to-date list of command groups — the help text
is a machine-readable spec written for you to read. Don't assume the surface is only
workflows: when a user asks "what can I do?", run `clay --help` and surface everything.

```bash
clay --help                 # all command groups (workflows, tables, routines, webhooks, …)
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

## When to use the CLI vs the Public API

Use the CLI for scripting and agent-driven tasks in a shell. To build a service, app,
or integration that talks to Clay over HTTP, use the **Public API** (`public-api` skill).

Full developer documentation (CLI reference, Public API reference, concepts, OpenAPI
spec) lives at: https://developers.clay.com/llms.txt
