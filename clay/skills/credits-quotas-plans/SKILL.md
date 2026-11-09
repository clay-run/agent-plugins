---
name: credits-quotas-plans
description: Use when the user asks about credits, quotas, or plan limits, or verified usage requires a significant-spend warning or reveals a limit. Covers data-credit balance, action-execution balance, search result caps, period quotas, and upgrade paths before starting work that would only partially complete.
---

# Credits, quotas, and plans

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

Follow the shared cost policy in `workflows-discover-actions/cost-and-budget.md`. Check headroom internally before paid work;
do not announce balances or suggest purchases just because a tool returned billing data.
Stop and explain a verified shortfall rather than knowingly starting a partial run.
An unknown cost does not establish a shortfall or require a cost-only approval.

## Triage

After checking what remains (below), route by what is short:

- **`balance` short** — CLI top-up or billing UI (`addCredits`). Prefer auto top-up.
- **`actionExecutionBalance` short** (when the field is present) — plan selector only.
  There is no top-up for action executions. Do not offer `once`, `auto`, or
  `addCredits`.
- **`user.balance` short** (when `user.limit` is not null) — the
  user's personal monthly credit limit. A top-up does not raise it; a workspace admin
  does, from the MCP page in Clay. It applies only to runs billed to the user, so
  mention it as a possible blocker rather than refusing the run on it alone.
- **Search `quota_exceeded` or period cap exhausted** — plan selector and/or wait for
  the named reset in the error message. Defer shrink/retry rules to the `search`
  skill; do not invent a top-up path for result caps.

Plan selector URL (upgrade or change plan):

```bash
clay whoami | jq -r '.workspace.id'
```

`https://app.clay.com/workspaces/<workspaceId>/billing/plan-selector`

## Check what remains

```bash
clay credits balance | jq '{ balance, actionExecutionBalance, user }'
```

`balance` is the data-credit pool. `actionExecutionBalance` is optional — present
only on action-execution pricing plans; omit or ignore it when the field is null
or absent (legacy billing). Plenty of one does not cover the other.

For routine runs, `clay routines get <id>` includes per-item cost estimates.
When the estimate applies to the configured execution and its counts are known, multiply
each cost by the number of items and compare against the matching balance. See the
`routines` skill for estimate limitations and the stop-before-partial-run rule.

`user` identifies the user (`id`, `name`, `email`) and carries their personal monthly
credit `limit` and remaining `balance`, both null when they have no personal limit. That limit can also stop a run billed to the user while
workspace credits remain. These fields are not a complete capacity check: a credit budget
assigned to the user can also stop a run, and this command does not report it.

Read `clay credits balance --help` for field semantics.

## CLI top-up

Applies to data-credit `balance` only — not `actionExecutionBalance`.

**Prefer auto top-up.** Lead with enabling (or confirming) auto so the workspace
stays funded without another interrupt. Only offer a one-time purchase if the
user pushes back against auto, or if auto is unavailable.

Read `clay credits top-up <subcommand> --help` for the exact JSON output shape,
flags, and examples; that help is the contract.

```bash
clay credits top-up auto get
clay credits top-up auto enable --threshold <n> --credits <n> [--daily-spend-limit-cents <n|none>]
clay credits top-up auto disable
clay credits top-up once --credits <n> [--open]   # only if user declines auto, or auto unavailable
```

**Auto enable limits:**

- `--credits`: at least 250 data credits; the plan-specific maximum is the number
  of credits currently equivalent to $1000
- `--daily-spend-limit-cents`: optional rolling 24-hour cap, 3000–500000, or
  `none` to clear; must cover the current price of one top-up
- `--threshold`: credit balance that triggers a top-up; must be at least 15% of
  the workspace subscription-cycle credit allowance (the server error includes
  the exact minimum when too low)

If the current `balance` is already at or below `--threshold` when auto is
enabled, a top-up runs **immediately** — it does not wait for the next charge.
Tell the user that enabling auto can purchase credits right away when they are
already under the threshold.

**Auto get/disable** return the same policy shape as enable.

**Once (fallback):** `--credits` must be at least 250. Returns a checkout `url`;
`--open` launches it in the browser. Credits land only after checkout completes —
do not treat command exit as a topped-up balance.

**Errors worth knowing** (from `credits balance` / `credits top-up`):

- `auth_forbidden` (exit 3) — billing-management access required
- `not_found` (exit 6) — auto top-up unavailable for this workspace, or disable
  when not currently enabled; fall back to `once` or the billing UI

**Do not run top-up without explicit user confirmation.** `credits top-up`
commands are gated from auto-approval in the plugin — present options and wait
for the user before `auto enable`, `once`, or checkout `--open`.

## Billing UI

Prefer automatic top-up first. Use the billing UI when the user wants the browser, or as
the one-time fallback after they decline auto / auto is unavailable:

```bash
clay whoami | jq -r '.workspace.id'
```

`https://app.clay.com/workspaces/<workspaceId>/home?addCredits=true`

The `addCredits=true` query opens the buy-credits modal directly.

## Search and result-cap quotas

These operations do not top up search result caps or period quotas. Auto top-up only
replenishes **credit** shortfalls — it does not raise per-search or per-period
result limits.

`quota_exceeded` (exit 1, HTTP 402) is a plan result cap or credit/usage limit —
not a transient failure (do not retry with backoff). Prefer the plan selector over top-up unless the
message is clearly a data-credit shortfall that top-up can fix. When the error
is about results already requested vs a cap, or a named period reset, stop
paging; for shrink/retry rules follow the `searches` skill's Quotas section — do
not invent a top-up path for result caps.

Plan selector:

```bash
clay whoami | jq -r '.workspace.id'
```

`https://app.clay.com/workspaces/<workspaceId>/billing/plan-selector`
