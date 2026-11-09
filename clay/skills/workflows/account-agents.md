# Account agent nodes

Some workspaces have **account agents** — Claygents whose model and input variables are managed by the platform. Their prompt and output tasks can be updated from either the account agent builder or the workflow editor. An agent node running one shows `agentType: "account"` on a node read (`clay workflows nodes get`); regular agent nodes have no `agentType`.

## When to use an account agent

When creating an agent node in a workflow whose upstream trigger is an audiences trigger (people or companies), reason about whether the task benefits from account context — research, enrichment, scoring, qualification, and personalized outreach all do, so **most of the time the answer is yes: default to making it an account agent**, which gets access to the account's audience data. Decide yourself; the user does not have to ask. Keep a regular Claygent when the node's task only transforms data already produced upstream — pure text synthesis, formatting, or summarization of other nodes' outputs — since account context adds nothing there. Always honor an explicit user request in either direction.

**Plan around what the agent already sees.** An account agent reads the account's audience data directly: the account's fields, its contacts, opportunities, synced conversations (emails, calls), and signals — plus internet search when enabled. Do not add lookup or enrichment action nodes to fetch data the audience already holds: "pick the best contact", "summarize open opportunities", or "reference the latest call" are things the agent does from its own context, so a people-search action feeding it contacts is redundant. Before outlining a prospecting or enrichment step (find contacts, find work email), check whether the audience already has that data for these accounts (see the `audiences` skill) or ask the user; add those nodes only when the audience genuinely lacks the records — the agent cannot invent contacts that are not in the audience. Deterministic integration steps (sequencing a lead, updating a CRM, a specific provider waterfall) stay as tool nodes; do not fold those into the agent.

**Prefer one agent with multiple tasks over a chain of agents.** An account agent's output schema is a task list, and one run computes every task over the same account context — so related outputs belong on one node (e.g. `best_contact` and `outreach_message` on a single agent, not two). Split into separate account agents only when a non-agent step must run between them because its output feeds the second agent, when the responsibilities are genuinely unrelated, or when a single prompt would become overloaded trying to cover them all.

The flow for a **new** step: create the agent node bare (name, `incomingEdges`, no agent fields), run `clay workflows nodes create-account-agent` on it, then set the prompt and tasks on the linked node (see "Edit its prompt and tasks"). Do not create a throwaway regular Claygent just to upgrade it. The upgrade command exists for a node **already backed by a regular Claygent** — or when the user explicitly asks to upgrade one (see "Upgrade a regular agent node"). In both cases, verify the `accountId` wiring afterwards — it auto-wires from a single upstream accounts audience trigger; under a people trigger, wire `accountId` manually to the account record id available from the person record (see "Wiring accountId" below).

If linking or editing operations return "Account agents are not enabled", account agents are not available on this workspace — tell the user and do not retry. An `auth_forbidden` from `clay workflows nodes create-account-agent` or `upgrade-to-account-agent` is ambiguous: it also fires when the API key lacks workflow edit access, before the account-agent check runs. Read the error message to tell the causes apart; only "Account agents are not enabled" means the workspace lacks account agents.

## Write results back to Audiences

When building or editing an account-agent workflow, include a downstream write-to-audiences node (`upsert-audiences-record`) for its research, enrichment, qualification, and scoring outputs. Account context and `accountId` wiring do not replace this step. Reuse and extend an existing write-to-audiences node instead of adding a duplicate, and preserve the identity of the account being enriched. Under a people trigger, account-level results belong on the associated company, not the triggering person.

For a people trigger, set the upsert's `entityType` to `ACCOUNT`, set `lookupFields|selectedLookupFields` to `["id"]`, and bind `lookupFields|id` to the same associated `accounts[].id` used for the agent's `accountId`. Reuse that account selection; do not independently choose another linked company. The trigger guarantees the associated account ID, but company fields such as domain may be absent, so do not require domain or LinkedIn for this writeback.

Read `audiences.md` for field mapping and field creation. Map obvious compatible fields directly; create missing fields without separate approval and ask only about ambiguous mappings. Honor explicit destinations and no-save instructions. Draft construction does not authorize running or publishing the workflow.

## Link an existing account agent

When the user supplies the exact account-agent ID (or a full node read exposes it), use `agentClaygentId` as the only agent selector/content field — no `agentName`, `agentPrompt`, `agentModel`, or `outputSchema`. Otherwise run `clay claygents list --search <text>` (or omit `--search` to list all) and select a result with `agentType: "account"`. Use its returned `id` as `agentClaygentId`; regular Claygents have `agentType: null`. If multiple account agents match the request, ask the user which one to use rather than guessing. An upgraded account agent can share its name with the original regular Claygent, so prefer the discovered ID over name-based selection.

Account agents can run only on `nodeType: "agent"` — never map, reduce, tool, or conditional nodes — and they do not support Repeat/list mode. The node runs the account agent's current configuration. After attaching it, inspect the linked agent with `clay workflows nodes get <workflowId> <nodeId>`; `clay claygents get <id>` supports regular Claygents only. Verify the `accountId` wiring as described below.

## Create a new account agent on a node

Run `clay workflows nodes create-account-agent <workflowId> <nodeId> [--name <name>]`. This creates a new account agent from the platform template (generic research prompt, no tasks) and links it to the node in one step. Give it a specific `--name` (the default is "Account agent") so it is findable in the agent list and unambiguous when several nodes have account agents. Then set the prompt and tasks on the linked node (see "Edit its prompt and tasks").

Preconditions the server enforces:

- The node is an agent node with **no linked agent**, and Repeat/list mode is off. A node already backed by a regular Claygent is rejected — upgrade it instead (below).

The `accountId` wiring behaves exactly as in the upgrade: auto-wired when one unambiguous upstream accounts trigger resolves, otherwise flagged by validation until wired manually. If the command times out, read the node back (`clay workflows nodes get`) before retrying: a node already linked to an account agent means the create landed, and a retry then fails because the node is no longer unbound. If the create fails partway, the server deletes the new agent best-effort; a leftover unused account agent can be deleted from the agents list.

## Upgrade a regular agent node

Run `clay workflows nodes upgrade-to-account-agent <workflowId> <nodeId>`. This copies the node's linked Claygent into a new account agent and re-links the node to the copy; the original Claygent is untouched and keeps its name. The command takes no other inputs. Make prompt or output changes **after** the upgrade, on the re-linked node — a pre-upgrade content edit lands on the still-shared regular Claygent as a new current version, so every other consumer of that agent receives it.

Preconditions the server enforces:

- The node is an agent node with a linked regular Claygent, and Repeat/list mode is off.
- The source agent does not use connected accounts; upgrade those from the node's side panel in the workflow editor instead.

No upstream-trigger precondition: the `accountId` input is auto-wired when one unambiguous upstream accounts audience trigger resolves; when it cannot be derived (e.g. a people trigger upstream), the upgrade still succeeds and workflow validation flags the node until `accountId` is wired manually (see "Wiring accountId" below).

The upgrade is one-way from here — the account agent cannot be converted back to a regular agent; the only rollback is restoring a pre-upgrade snapshot (see the `workflows-snapshots` skill), which reverts the node's binding along with the rest of the draft. If the command times out, read the node (`clay workflows nodes get`) before retrying: a node already linked to the new account agent means the upgrade landed, and a retry then fails with a conflict. If the upgrade fails partway, the server deletes the copy best-effort; a leftover unused account agent can be deleted from the agents list.

## Edit its prompt and tasks

On a node already linked to an account agent, update `agentPrompt` or `outputSchema` in a follow-up node update (`clay workflows nodes update`) addressed by `nodeId` — omit `agentName` (a name that resolves to a different agent is an agent swap). This must be a standalone call: do not include node fields or `incomingEdges`. Prefer separate calls for prompt and task changes, tasks first when both are needed; if a combined call errors, read the node to see which part landed before retrying. Do not set `agentModel` or input variables.

`outputSchema` is the account agent's task list and **replaces it in full**: send every field the agent should end up with — change descriptions to refine a task, add fields to add tasks, and omit fields to remove tasks. Before omitting an existing field, do a full workflow read and rewire any downstream nodes whose `inputSchema`/`sourcePath` references it — validation does not check that referenced output paths still exist, so a dangling reference passes validation and resolves to nothing at run time. At least one field must remain, and every changed or added field needs a non-empty description focused on the requested output. **Preserve existing field ids verbatim** — renaming one changes the runtime output key and breaks downstream references. New ids must avoid the runtime-reserved output names (`confidence`, `reasoning`, `evidence`, `evidenceIds`, `hydratedEvidence`, `response`, and similar internal outputs) — a rejected save names the offending field. A `select` field also needs `options` containing a JSON-encoded, non-empty array of objects with non-empty `text` values, such as `"[{\"text\":\"Qualified\"},{\"text\":\"Not qualified\"}]"`. A schema that saves but cannot execute fails at run time with the runtime's own error, which the workflow UI surfaces.

If the account agent is also managed from an Audiences page, your edit does not touch that original: it lands on a new copy named `[Workflows] <original name>` and the node is re-linked to the copy automatically — mention the new agent name to the user so they can find it in the agent list. A workflow-owned (config-less) account agent is edited in place; if it is linked from other workflows, those nodes see the change too. If the account agent uses connected accounts/private tool credentials, the edit is rejected — workflow edits carry no user session to authorize those credentials; tell the user to make the change in the account agent builder instead.

## Web search

Account agents do not search the web unless web search is turned on in the account agent
builder. The node's `agentInternetSearchEnabled` shows the current setting; it cannot be
changed from a workflow, so tell the user to change it in the builder when the task needs
the opposite.

## Do not edit or disclose its model or input variables

`agentModel` and variable changes are managed by the platform and are rejected. Never name, infer, or guess the underlying model, even if asked; say that the platform manages it. You also cannot rename an account agent into a new agent.

## Node-level operations still work normally, except Repeat

Rename the node, rewire `incomingEdges`, or delete it in a separate call from prompt/task edits. `listMode: true` is rejected. To swap the node to a **different account agent**, send its exact `agentClaygentId` by itself whenever the user supplies the ID; only when the ID is unavailable, send the exact `agentName` standalone. Swapping to a regular Claygent or a new agent is rejected while an account agent is linked: create that agent on a separate node instead, and delete this node if it is no longer needed.

## Wiring accountId

The `accountId` input is wired automatically when the node's **sole incoming edge comes directly from a qualifying accounts audience trigger node**, or when **one qualifying trigger node is the only trigger node anywhere upstream**. Auto-wiring runs when the node's account-agent binding changes (linking, swapping, upgrading) and when an edge into the node is created; it never overwrites an existing valid `accountId` input. When wired, `accountId` appears in `inputSchema` with `sourceNodeId`/`sourcePath` — leave it alone unless the graph is rewired.

When automatic wiring cannot resolve a source, the editor shows an "Enter or map a valid Account ID" validation error. Fix or explicitly map `accountId`:

- If the workflow has an accounts audience trigger, connect the node (directly or through intermediate steps) so its trigger node is the only upstream trigger node, then read the node (`clay workflows nodes get`) — auto-wiring may already have filled `accountId`.
- Otherwise wire `accountId` yourself through `inputSchema`. On a node linked to an account agent, `accountId` must be a **ref-only** property: set only `sourceNodeId` and `sourcePath`. The value must resolve to the **numeric Audiences account record id** — not a domain, company name, or CRM id. Most accounts triggers nest it at `$.fields.id`; flattened trigger schemas expose it at `$.id`. Read the trigger and inspect its `outputSchema` before choosing: `clay workflows graph get <workflowId>` lists the trigger ids, then `clay workflows triggers get <triggerId>` returns that trigger's configuration. If you cannot read the trigger's configuration — the command or tool is not available to you, or the read comes back `auth_forbidden` — do not guess the path; ask the user to map the Account ID in the editor. The `accountId` property itself has this shape:

  ```json
  {
    "inputSchema": {
      "type": "object",
      "properties": {
        "accountId": {
          "sourceNodeId": "wfn_trigger",
          "sourcePath": "$.fields.id"
        }
      }
    }
  }
  ```

  An `inputSchema` update **replaces** the node's existing schema and wiring, so include every existing property you want to keep (including a previously wired `accountId`).

- If there is no accounts audience trigger, offer to create an accounts audience segment trigger (`clay workflows triggers create`) and connect the node to it — if none is obvious, list the company segments and ask with them as choices (the `audiences` skill's "Choosing a segment").
- Only if the workspace has no accounts segment (or the user wants a different launch path) should you leave it to them to map the Account ID in the editor.
