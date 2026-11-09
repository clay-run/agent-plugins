---
name: workflows-optimize-credits
description: Clay workflows — reduce a workflow's credit and LLM cost via the CLI (`clay workflows` commands). Identifies expensive patterns and suggests cheaper alternatives.
---

# Reducing workflow credit & LLM cost

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

Analyze the current workflow and suggest changes to reduce credit consumption and LLM costs without sacrificing quality.

## Process

1. **Read the workflow** using `clay workflows graph get <workflowId> --mode full` to get all node details
2. **Identify cost drivers** — LLM calls, Clay action usage, model selection
3. **Present optimization opportunities** with estimated impact, alongside a render of the **current graph** (`clay workflows diagram <workflowId>`) with the expensive nodes called out so the user can see where the cost lives
4. **Apply authorized changes** — edit the workflow only when the user's request authorizes modifications, via `clay workflows nodes update`/`create`/`delete`. Once authorized, apply clearly safe optimizations as you go and ask before changes with a material quality or behavior trade-off
5. **Show the result** — after applying, run `clay workflows graph format <workflowId>` and render the **updated graph** so the change is visible

Narrate throughout and prefer the diagram over raw node JSON — see the `workflows` skill's `presenting.md`.

## Cost Drivers in Clay Workflows

### LLM Calls (biggest cost driver)

Every regular (LLM) node makes at least one LLM call per execution. More capable models cost more.

**Optimizations:**

- **Replace with code nodes:** If a node does deterministic work (data transformation, filtering, formatting), replace it with a code node — zero LLM cost
- **Use cheaper models:** Simple tasks (parameter extraction, basic classification) can use smaller/faster models. Reserve powerful models for complex reasoning
- **Merge nodes:** Two sequential LLM nodes doing related work can often be one node with a combined prompt — cuts LLM calls in half
- **Pre-map action parameters:** When a node calls a Clay action, configure `static` or `reference` input mappings (`inputMappingConfig`, see the `workflows` skill's `data-passing.md`) for parameters that don't need LLM inference. If ALL parameters are pre-mapped, the LLM parameter mapping call is skipped entirely

### Clay Action Credits

Each Clay action execution consumes credits based on the action's pricing tier.

**Optimizations:**

- **Avoid redundant enrichments:** If the same data was already fetched in an earlier node, reference it via a pinned input (`sourceNodeId`/`sourcePath`) instead of calling the action again
- **Use conditional routing:** Skip expensive enrichments for items that don't need them (e.g., skip company research for companies you already have data on)
- **Choose cheaper alternatives:** Some actions have cheaper equivalents. Use `clay workflows actions list` (see `/workflows-discover-actions`) to compare options and their priority tier

### Model Selection

Different models have different cost/capability profiles.

**Optimizations:**

- **Match model to task complexity:**
  - Simple extraction/classification → use a smaller, faster model
  - Complex reasoning, multi-step analysis → use a more capable model
  - Creative writing, nuanced decisions → use the most capable model
- **Downgrade where safe:** Review each regular node's prompt. If the task is straightforward, try a cheaper model

### Repeat Node Efficiency

Nodes in Repeat mode (`listMode: true`) multiply costs by the number of items processed.

**Optimizations:**

- **Code over agent:** If the per-item processing is deterministic, use a code node (zero LLM cost per item)
- **Filter before repeating:** Add a code node before the Repeat node to filter out items that don't need processing

### Conditional Routing

Use conditional nodes to skip expensive branches for items that don't need them.

**Example:**

```
Instead of:  [All items] → [Expensive enrichment] → [Process]
Do this:     [All items] → [Conditional: has data?] → Yes → [Process]
                                                    → No  → [Enrichment] → [Process]
```

## Analysis Output Format

For each optimization opportunity, present:

1. **Node(s) affected** — which nodes to change
2. **Current cost pattern** — what's expensive and why
3. **Suggested change** — specific modification
4. **Estimated impact** — qualitative (high/medium/low) cost reduction
5. **Risk** — any quality trade-offs

Prioritize suggestions by impact (highest savings first). Pair the list with the current-graph render, with the expensive nodes called out, so each is easy to locate.

For analysis or recommendation requests, present the opportunities without editing. If the user asks you to modify the workflow, apply clearly safe savings as you identify them and state your assumptions. Ask only when an optimization has a meaningful quality, cost, or behavior trade-off. Then validate with `clay workflows graph format <workflowId>` and show the updated graph so the user can see the before/after difference.
