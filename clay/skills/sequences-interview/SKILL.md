---
name: sequences-interview
description: Use when a fresh Clay sequence (formerly campaign) has no meaningful subject or body copy and needs its first draft.
---

# Fresh sequence interview

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

If the `sequences` skill is not already loaded, load it before acting. Use it for sequence discovery, context, target selection, commands, and mutation boundaries. Use this skill for the interview and first-draft decisions.

Use this skill whenever a fresh `clay sequences get` shows that the target sequence has no meaningful subject or body copy. It may require no questions. Do not trigger merely because one step is blank in an otherwise authored sequence.

## Gather context first

Before asking the user anything:

- Read the user's request and the relevant conversation.
- Read the sequence goal.
- Resolve AI context, then read the selected skill instructions, My Business Context, and selected reference content that it returns.
- Inspect the configured audience, sequence settings, and every step.

Context resolution and audience inspection are best-effort. Treat unavailable sources as absent, never imply that they were read, and continue from the context gathered successfully unless the user explicitly requires the missing source.

Ask only about an unresolved gap when different answers would materially change the draft, and ask it through the question tool. Do not use a preset questionnaire, question order, grouping, or target count. Do not ask about tone, number of steps, or personalization when the available context supports a credible choice. When there is enough context, state the assumptions that matter and continue without asking. Omit unsupported proof instead of blocking or inventing it.

## Sequence goal

Use the gathered context to assess the sequence goal. Propose a concise goal when the existing goal is empty or materially conflicts with the intended audience, relevant situation, offer, or desired recipient action. Otherwise preserve it. Never replace a non-empty goal unless the user explicitly asks for or accepts the proposed replacement, and continue drafting if the user declines.

After the user accepts a proposed goal:

1. Run `get` again immediately before saving it. If the current goal changed during the conversation, do not overwrite it; reconcile the goals with the user first.
2. If the fresh status is `draft` or `paused`, save the goal to `claygentContext.campaignIntent` with a separate context edit. If it is `active` or `completed`, do not attempt the edit; explain that sequence settings are locked and keep the accepted goal in the conversation.
3. Resolve AI context before drafting the steps. Read the sequence again only when the context-edit response lacks the state needed to report the saved goal or resolve AI context.

Move directly to the draft when the material context is sufficient; a brief summary and approval of the step plan are not required. Never expose sequence, variant, step, segment, or field ids.
