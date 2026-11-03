---
name: workflows-claygent
description: Build and run Claygent agent nodes in Clay workflows. Use when the user asks for custom LLM research, reasoning, classification, drafting, or summarization over records; when no existing routine fits a Claygent task; or when creating or editing a workflow `agent` node.
---

# Claygents in workflows

A Claygent in a workflow is a dedicated `nodeType: "agent"` node. It is not a Clay action
or function, so its absence from `clay workflows actions list` does not make Claygent
unavailable. Use `/workflows-discover-actions` only for tool nodes.

If an existing routine already performs the requested task, use the `/routines` skill.
Otherwise build the Claygent workflow here. Read the main `/workflows` skill for graph,
publishing, testing, and presentation rules.

## Create or reuse the Claygent

- To reuse a regular Claygent, find it with `clay claygents list --search <text>` and read it
  with `clay claygents get <id>` to check its inputs, outputs, and tools. Then set only
  `agentClaygentId` on the node. Do not also send its name, prompt, model, or outputs.
- To create one, send `agentName`, `agentPrompt`, and `agentModel` together in the agent
  node's first `clay workflows nodes create` call. Use the user's requested model when it is
  available; do not silently substitute a different model.
- Put every prompt variable in top-level `inputSchema.properties`. Wire upstream values with
  `sourceNodeId` and `sourcePath`, then use the property name as `{{variable}}` in the prompt.
- Set `outputSchema` to a flat field map with a useful description on every field. A
  `select` field's `options` value is a JSON-encoded string containing a non-empty array of
  objects with non-empty `text`, for example:

```json
{
  "signal": {
    "type": "select",
    "description": "Strength of the evidence",
    "options": "[{\"text\":\"Strong\"},{\"text\":\"Weak\"},{\"text\":\"None\"}]"
  }
}
```

If a write rejects an output field or schema, use the validation message to correct it
before testing. Do not retry the same shape.

If the user asks for a numeric score within a bounded set of ranges (for example "80–100
strong, 35–65 mixed, 0–25 weak"), the Claygent prompt must say that the score has to fall
inside one of those ranges.

## Connected tools

A Claygent's tools — MCP servers such as Linear or Notion, routines, document sources, and
web search — are configured on the Claygent, not on the workflow node. An agent node's
`tools` field is always empty, so it says nothing about what the Claygent can use. Read
`clay claygents get <id>` and check `tools`, `internetSearchEnabled`, and
`peopleAndCompaniesSearchEnabled`.

An agent node's `agentInternetSearchEnabled` shows whether its Claygent can search the web.
Set it with `clay workflows nodes update` to turn web search on or off for a regular
Claygent; the change applies everywhere that Claygent runs. Clay models always search the
web, so web search cannot be turned off for them.

When the agent needs a resource behind authentication, such as a private Linear attachment,
first look for a connected tool that already holds that account's credentials, and tell the
Claygent in its prompt to use it. Do not build a separate fetch-and-rehost chain of workflow
nodes for something a connected tool can reach. Connecting a new tool is done in the
Claygent's settings in Clay.

## Choose the source

- For a bounded Clay Search population, use a Find leads trigger and follow the trigger
  guidance in the main `/workflows` skill. Preserve the latest search query and its explicit
  overall limit; never use an estimated result count as the run limit or turn search results
  into workflow inputs by hand.
- For Audiences records, use the trigger/backfill guidance in the main `/workflows` skill.
- For explicit inputs supplied by the caller, use a manual trigger and wire its input schema.

Each Find Leads or Audiences source record starts one workflow run, so the downstream
Claygent reads one person's or company's fields directly from the trigger node.

## Research responsibility

When the task requires public evidence, put the research criteria and source expectations in
the Claygent prompt. The Claygent performs the per-record web research during its run; the
host agent should not manually research every record before launching it.

When the user needs an exact criterion checked by the research — a funding event's date, a
launch in the last 12 months — have the Claygent return it as an output field, left empty when
the evidence does not establish it rather than guessed. Add a conditional that stops
non-matching records only when the user asked to keep just the matches ("only companies
that…", "skip anyone without…"); otherwise every record continues with the field as returned.
Do not claim the Claygent's future research has already verified it.

## Test, run, and deliver

1. Validate the graph.
2. Test the Claygent on one representative record before launching the batch. Inspect the
   actual node output and correct schema, model, prompt, or tool failures first.
3. Bound and preflight the full run using the source query limit and the cost policy from
   `workflows-discover-actions/cost-and-budget.md`.
4. Publish when the source trigger requires the live graph, start the source, and record the
   launch time.
5. List the runs created by that trigger, follow pagination, and wait for terminal states.
   Read actual Claygent outputs with `clay workflows runs get`; use `--node-id` or
   `--verbose` when needed.
6. Build requested CSVs or reports from completed run outputs, not Search preview rows.
   Include completed/failed counts and identify failed records in partial deliveries.
