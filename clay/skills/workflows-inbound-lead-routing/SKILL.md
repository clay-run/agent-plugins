---
name: workflows-inbound-lead-routing
description: Guide customers through building an inbound lead-routing workflow in Clay Workflows. Use when a customer wants to route inbound leads from a form, webhook, data warehouse, or other source to a rep, sequence, or CRM.
---

# Inbound lead routing

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

## Description

Guide customers through building an inbound lead routing workflow in Clay Workflows. Use this skill when a customer wants to route inbound leads — from a form, webhook, data warehouse, or other source — to a rep, sequence, or CRM. Be opinionated and directive. Recommend the right approach, explain why, and keep the build moving forward.

---

## Trigger

When a customer asks to build an inbound lead routing workflow, or describes a use case involving routing form submissions, webhook events, or inbound signups to reps or sequences.

---

## Instructions

Follow the host agent's existing policies for reasoning, planning, requesting user input, and approvals. This skill supplies routing requirements and workflow guidance; it does not define a separate interaction policy. Treat the example questions below as inputs to establish, not a mandatory interview script.

### Step 1 — Establish the Trigger

Start by telling the customer:

> "For inbound lead routing, we'll use a **webhook** as the trigger. This is the standard approach because it lets your form, data warehouse, or website fire events directly into Clay in real time."

Available triggers (present as alternatives only if the customer pushes back or has a specific constraint):

- Manual CSV upload
- Manual trigger with manual inputs
- Schedule-based
- Signal/intent-based
- New audience member added
- Audience segment updated on schedule
- **Webhook (recommended default)**

Establish the lead source if it is not already known:

> "Are you capturing leads through an inbound form, like Typeform, or is this coming from another source like your data warehouse or website?"

- If yes to a form → confirm webhook is the right trigger, proceed.
- If another source → confirm it can emit a webhook. If not, explore schedule or CSV alternatives.

---

### Step 2 — Establish the Routing Requirements

Establish the five inputs below, along with the trigger, enrichment level, scoring criteria, and routing tiers. Reuse information already provided or available in the workspace. Let the host agent’s policies determine which remaining decisions require user input and how to request it.

**Q1 — CRM**

> "Which CRM are you using?"

For every CRM, including Salesforce and HubSpot, follow `workflows-discover-actions` to verify a suitable write action in the live workspace catalog and confirm the user can access the required connected account before proposing that route. If the action exists but no usable account is connected, establish that setup requirement. Recommend a webhook only if no suitable native action is available.

**Q2 — Scoring Model**

> "Do you have an existing lead scoring model, or do we need to build one?"

- Has one → use the existing scoring logic; you'll implement it in a Run Code node
- Doesn't have one → tell them: "No problem. We'll build one together in a Run Code node. It'll use firmographic data, form fields, and intent signals from your enrichment steps."

**Q3 — Rep Routing**

> "When a tier 1 lead comes in, how do you want the rep to be notified?"

Options (pick one):

- Slack message
- CRM task
- Email

**Q4 — Sequencer**

> "Are you using an external sequencer like Outreach or Salesloft, or Clay's native sequencer?"

- External sequencer → will need a webhook or native integration node to push to it
- Clay sequencer → can be handled natively within the workflow

**Q5 — Disqualification Handling**

Collect both preferences together:

- "Add disqualified leads to a nurture sequence?"
- "Tag or update disqualified leads in the CRM?"

If both answers are no, end without further action.

---

### Step 3 — Build the Workflow

Keep enrichment and scoring steps sequential. Use the conditional step to branch into the tier-specific routing outcomes.

**The standard happy path:**

```
Webhook Trigger
  → Run Enrichment (firmographic + contact data)
  → Run Code (scoring model)
  → Conditional Logic (tier routing)
  → Route (rep notification / sequence / disqualify)
```

Walk the customer through each node:

#### Node 1: Run Enrichment

> "First, we'll enrich the inbound lead to fill in any missing data — company size, industry, job title, and any intent signals. This gives the scoring model everything it needs."

Use the person-level, company-level, or combined enrichment requirement established above.

#### Node 2: Run Code (Scoring Model)

> "Next, we'll run a scoring model to tier the lead. This code node will take the enriched data and output a score or tier (e.g., Tier 1 / Tier 2 / Disqualified)."

If building from scratch:

Translate the established lead-quality criteria into a scoring formula.

Typical inputs to the scoring model:

- Firmographic data (company size, industry, revenue)
- Form fields (role, use case, company name)
- Intent signals (from enrichment nodes)

#### Node 3: Conditional Logic

Use the established tiers to route based on the score.

Standard structure:

- Tier 1 → notify rep immediately
- Tier 2 → add to marketing/sales sequence
- Disqualified → handle per customer preference (dead, nurture, CRM tag)

Additional conditional branches to offer if relevant:

- Language/market-based routing (e.g., route French-speaking leads to a French sequence)
- Company segment routing (e.g., SMB vs. Enterprise)

#### Node 4: Route

Build the routing outcome based on answers from Step 2:

**If routing to a rep:**

- Slack → set up a Slack message node with their preferred format
- CRM task → create a task in Salesforce or HubSpot
- Email → send a notification email with lead summary

**If adding to a sequence:**

- Clay sequencer → add directly via native node
- External sequencer (Outreach, Salesloft, etc.) → push via webhook or native integration

**If disqualifying:**

- Dead end → no further action needed
- Nurture → add to a nurture sequence
- CRM tag → update lead/contact record in CRM

---

### Step 4 — Summarize and Build

Summarize the proposed workflow as part of the host agent’s planning process:

> Here's the workflow we're going to build:
>
> 1. [Selected trigger] trigger from [source]
> 2. Enrich at [person/company/both] level
> 3. Score the lead using [existing model / model we'll build] based on [inputs]
> 4. Route Tier 1 leads to [rep via Slack/CRM task/email], Tier 2 to [sequence], and disqualified leads to [dead end/nurture/CRM tag]

Follow the host agent’s approval policy before making changes.

When building, follow the workflows entry-point skill for the actual node and
graph edits — this skill is the consultative playbook only.

---

## Tone Guidelines

- Be **opinionated and directive**. Don't present every option as equal — recommend the right approach and explain why.
- If a customer proposes something that will make the workflow harder to maintain (e.g., parallel branches, skipping enrichment), push back and explain the tradeoff.
- Use plain language. Avoid jargon unless the customer introduces it first.
