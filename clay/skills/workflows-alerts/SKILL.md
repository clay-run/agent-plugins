---
name: workflows-alerts
description: Clay workflow alerts — use when the user wants to create, inspect, edit, enable, disable, or delete a workflow alert rule, or subscribe themselves to its email notifications.
allowed-tools: Bash(clay *), Bash(jq *), Read
---

# Workflow alerts

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

Alert rules watch a workflow's published runs and notify its subscribers. Commands live under
`clay workflows alerts`; run `clay workflows alerts <command> --help` for exact JSON shapes and
error codes.

| Need                                   | Command                                                                          |
| -------------------------------------- | -------------------------------------------------------------------------------- |
| Conditions this workspace can use      | `clay workflows alerts metrics list`                                             |
| A workflow's rules                     | `clay workflows alerts list <workflowId>`                                        |
| Create a rule                          | `clay workflows alerts create <workflowId> --input <json\|file\|->`              |
| Edit, enable, or disable a rule        | `clay workflows alerts update <workflowId> <ruleId> --input '{"enabled":false}'` |
| Delete a rule                          | `clay workflows alerts delete <workflowId> <ruleId>`                             |
| Repeat interval and delivery schedules | `clay workflows alerts settings get <workflowId>`                                |
| Recipients                             | `clay workflows alerts destinations get <workflowId>`                            |
| Subscribe yourself to alert emails     | `clay workflows alerts subscribe <workflowId>`                                   |

If the alert operations are unavailable, consult the `clay` entry skill for access guidance
or point the user to the workflow's Alerts panel in the Clay app. Do not work around the missing operations through direct API calls.

## Workflow

1. **Resolve the workflow and rule.** Use the workflow from the selected context, a supplied ID,
   or `clay workflows list`. Read it with `clay workflows get <workflowId>` and keep its real URL.
   Resolve rule IDs from `clay workflows alerts list`; never guess a rule ID, and ask when several
   rules match a name.
2. **Read current state before any change.** Fetch `metrics list`, `alerts list`,
   `settings get`, and `destinations get`. Offer only metrics `metrics list` returns, for new rules
   and metric changes alike. Do not infer availability from metric names you know, enum
   membership, or feature flags. If the metric the user wants is absent, report it unavailable
   rather than picking another.
3. **Translate intent with the returned condition.**
   - `condition.kind: "aggregate"`: choose one of its `operators`; give `threshold` in its `unit`
     (whole-number percent 0–100 or a run count) and one of its `windowMinutes`.
     Set `sampleFloor` only when `usesSampleFloor` is true and the user asked; it defaults to 10.
   - `condition.kind: "event"`: submit the returned `metric` as is, with no threshold, window, or
     floor, and do not ask for them. Use `{"name":"Notify on every failure","metric":"run_error"}`
     only when the user wants to hear about failures themselves ("notify me when it fails", "alert
     me on every failure"), and do not substitute a failure-count rule. "Immediately" is delivery
     timing, not a condition: for "alert me immediately when the failure rate exceeds 20%", create
     the aggregate rule that condition names and handle the timing as below.
     `clay workflows alerts create --help` describes when a `run_error` rule fires, repeats, and
     resolves.
   - Timing follows the delivery schedules, not the rule. Before creating a rule for "immediately"
     or saying when alerts arrive, read `emailDeliveryCadence` and `slackDeliveryCadence` from
     `settings get`. If either is `daily` or `weekly`, tell the user first that the channel's
     alerts arrive in a daily or weekly digest, not immediately, and that the schedule is changed
     in the Clay app; create the rule only if they still want it. Say "immediately" only for a
     channel whose cadence is `immediate`.
   - `gte` with a threshold of 0 is rejected because it would fire on every check. For "any
     failure in the window", use `gt` with 0, or `run_error` when the user wants each failing
     streak.
   - Ask only for intent that is genuinely missing. If the user asks for a condition the
     catalog doesn't offer (for example run duration or credits), say it isn't available.
4. **Avoid duplicates.** Match aggregate rules on metric, operator, threshold and window, plus
   sample floor only when the metric's `usesSampleFloor` is true (other metrics ignore a stored
   floor); match event rules on metric. Reuse an equivalent enabled rule; offer to enable a
   disabled match. Create a second similar rule only when the user explicitly asks for one. A
   workflow holds at most 10 rules. Evaluation timing is managed by Clay: there is no command or
   field to change how often rules are checked, so say so if asked.
5. **Make the change.** Submit only the fields that change; omit an unchanged `metric` from
   updates. Do not change the workflow graph, publish, or run it. Explain that changing a rule's
   definition or deleting it closes its open alert; renaming alone keeps it open. A rule's name
   does not follow its condition: when you change the condition of a rule whose name describes
   the old one (for example "Run failure rate (>20% in the last 1 hour)"), send a matching new
   name in the same update, and keep a name the user chose. A run error rule that fires again after
   resolving sends a fresh first notification. Before saying an open alert will repeat, read
   `renotifyMinutes` from `settings get`: a number is the repeat interval in minutes, and `null`
   means it notifies once and never repeats. Describe timing only as the delivery schedules
   above; do not promise a time beyond that.
6. **Keep email subscription separate.** Subscribing is explicit, workflow-wide, and only for the
   current user. Creating a rule subscribes no one. When the user says "alert me", check
   `isCurrentUserSubscribed` from `destinations get`, not whether the recipient list is empty.
   If it is false, ask whether to subscribe them by email; subscribing again is safe. Every rule,
   including `run_error`, notifies on the workflow's email and Slack delivery schedules; those
   schedules are read-only here. Changing schedules or the repeat interval, choosing a Slack
   channel, adding other users, unsubscribing, test sends, and resolving alerts happen in the Clay
   app. Point the user there instead of claiming success.
7. **Handle results.** On `approval_required`, use the host's approval flow with
   `details.actionApprovalRequestId`; never approve on the user's behalf, and never rerun the
   command after approval, because approving runs it. On a `not_found` that says alerts are not
   available, report that; do not publish or run the workflow or try to turn on a flag.
8. **Confirm from the server.** After a success or an approved change, read back with
   `alerts list` and `destinations get`. If the rule was created but a requested subscription
   failed, report the saved rule and the failed email setup; do not roll back and do not say
   notifications are set up. Report the rule name, condition, enabled state, the delivery
   schedules and recipients you read, and `[Open workflow](<url>)`. Do not report evaluation
   timing or flag state, and do not say a notification was sent because a rule was saved.

Rules evaluate published workflow runs; creating a rule does not publish or run the workflow.
