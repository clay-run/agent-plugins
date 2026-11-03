---
name: campaigns-events
description: Use when the user asks what happened to a campaign lead (replied, out of office, bounced, unsubscribed, stopped getting emails, needs resuming) or works in the Campaign events table, including how replies and out-of-office count in reply rate, reply categories, rep routing, and automations or workflows built on campaign events.
---

# Campaign events

Use this to explain, filter, or build on campaign activity: the **Campaign events** table, a column, workflow, or
automation that reads it, or a question such as "why did this lead stop getting emails?". Answer from this skill, not
from general sequencer knowledge: Clay configures its email provider in ways that differ from common defaults,
especially for out-of-office replies.

## The Campaign events table

Each workspace has one shared Campaign events table (named Campaign webhook events in older workspaces). Every
campaign writes to it, and each campaign also gets a view named `<campaign name> events` that is filtered to that
campaign. The table keeps only the most recent 10,000 events. Older rows move to the table's read-only archive,
which the user opens with the View archive button at the bottom right of the table. The table and its per-campaign
views therefore show only recent events, and columns, exports, and automations on the table never see archived rows.
For an older campaign's full history, point the user to the archive or the campaign's Activity tab, and use `clay
campaigns analytics` for totals.

Events usually appear within a few minutes of happening. Replies from a mailbox the user connected themselves (rather
than one bought in Clay) can be delayed or missing while that mailbox is disconnected.

Each row is one event. The raw payload is in the source column. Managed formula columns extract the common fields:

| Column                 | Payload path                                | Notes                                                                  |
| ---------------------- | ------------------------------------------- | ---------------------------------------------------------------------- |
| `Campaign ID`          | `smartlead.campaign_id`                     | The email provider's campaign id, not the Clay campaign id             |
| `Event type`           | `event_type`                                | One of the types below                                                 |
| `Lead ID`              | `smartlead.lead_id`                         | The email provider's lead id                                           |
| `Audience ID`          | `lead.audience_entity_id`                   | Links to the Audiences contact; `Audience record` looks the contact up |
| `Lead email address`   | `lead.email`, else `recipient.email`        | Always the enrolled lead                                               |
| `Last reply content`   | `reply.html`                                | Only `EMAIL_REPLY`                                                     |
| `Reply category`       | `reply.category_name`, else `category.name` | `EMAIL_REPLY` and `LEAD_CATEGORY_UPDATED`                              |
| `Sender email address` | `sender.email`                              | Direction depends on the event type; see `EMAIL_REPLY`                 |

The default view shows only `EMAIL_SENT`, `EMAIL_REPLY`, `EMAIL_OPEN`, `EMAIL_LINK_CLICK`, `EMAIL_BOUNCE`, and
`CAMPAIGN_STATUS_CHANGED`. Unsubscribes and category updates are still in the table. Remove the view filter or use
a different view to see them.

## Fields on every event

- `event_type`
- `event.description`
- `event.occurred_at`: when the event happened at the provider (for example, the send, open, click, or reply time).
  Use this field for time, not the row's creation time. It can be missing.
- `campaign.name`, `campaign.status`
- `clay_campaign_id`: the Clay campaign id, when Clay could resolve it.
- `smartlead.campaign_id`, `smartlead.lead_id`, `smartlead.lead_map_id`: the email provider's ids.

Every event type except `CAMPAIGN_STATUS_CHANGED` also has:

- `lead.email`, `lead.name`, `lead.audience_entity_id`: the enrolled lead, using the address they were enrolled with.
  Use `lead.email` to identify the lead.
- `sender.email`, `recipient.email`: the addresses as the email provider reported them.
- `sent` (all of these except `LEAD_CATEGORY_UPDATED`): the campaign email the event relates to (`subject`, `html`,
  `text`, `sequence_number`, `stats_id`). `sequence_number` is the 1-based step in the sequence.

## Event types

### `EMAIL_SENT`

A sequence step was sent to the lead. `sender.email` is your sending mailbox, and `recipient.email` is the lead. After
the final step is sent, the lead counts as completed.

`sent.subject` and `sent.html` are the exact copy that went out. Copy edits on a live campaign apply only to leads
enrolled after the edit, so use this event to check what a particular lead received.

### `EMAIL_OPEN` and `EMAIL_LINK_CLICK`

The lead opened the email (`engagement.opened_at`) or clicked a link (`engagement.clicked_at`,
`engagement.clicked_links`).

- These events only fire when open or click tracking is on. Plain-text campaigns always turn tracking off, so they
  never produce opens or clicks. If these events are missing, that does not mean nobody engaged.
- Every repeat open or click is a separate event. Campaign analytics count each sent email at most once.
- Opens are unreliable: mail clients and security scanners can trigger them automatically.
- These events never change a lead's status or stop a sequence.

### `EMAIL_REPLY`

The lead replied.

- **`sender.email` is usually your sending mailbox, not the lead.** For about 98% of replies, the email provider
  reports the reply with the sender and recipient the same way round as the original send: `sender.email` is the
  rep's sending mailbox and `recipient.email` is the lead. In the remaining cases they are swapped. Use `lead.email`
  for the lead. To find the sending mailbox reliably, take whichever of the two addresses is not the lead.
- The reply is in `reply.html` and `reply.text`, with a shorter `reply.preview_text`. `reply.cc_emails` lists anyone
  else on the reply.
- `reply.category_id` and `reply.category_name` hold the AI-assigned lead category, if there is one. `category_name`
  is filled only for the standard categories (listed below). A reply that is not categorized yet may be categorized
  later, which produces a `LEAD_CATEGORY_UPDATED` event.
- `links.reply_url` opens this reply in the Campaigns inbox. It is present only when the provider sent both lead ids.
- A reply stops that lead's sequence and marks the lead as replied, unless the reply is out of office (see below). If
  the campaign setting to pause other leads at the same domain on reply is on, those leads pause too.
- The table adds reply-only action columns:
  - `Get rep email` looks up the rep assigned to the mailbox in `sender.email` and returns `repEmail` and
    `repFullName`. It returns no data when no rep is assigned to that mailbox, or when `sender.email` is not one of
    the workspace's mailboxes (the swapped case above).
  - `Forward email` forwards the reply to that `repEmail`.
  - `Reply to lead email` sends the body written in the `Email reply: Body` column as a reply in the lead's thread.
    It does not run for replies categorized as Out Of Office, Wrong Person, Not Interested, or Do Not Contact.
  - `Add email to blocklist` blocks the lead's address. Unlike the other three, it can run on every event type.

### Out of office (OOO)

OOO is a reply category (`Out Of Office`, id 6), not a separate event type. An OOO auto-reply comes in as an
`EMAIL_REPLY` with that category.

- An OOO reply does **not** stop the sequence, mark the lead as replied, or count as a positive reply.
- The campaign's Analytics page **does** count OOO replies in its Reply rate, which is all replies divided by emails
  sent. Replies count once per email answered, so two replies to one email count once. The Reply rate tooltip gives
  the count excluding OOO, and a separate Out of office card shows how many replies were OOO. Answer reply-rate
  questions from these definitions, not from general sequencer conventions.
- Leads auto-resume. When the OOO message says when the person will be back and the sequence has at least one step
  left, the sequence is held and resumes on that date. If the return date is more than 30 days away, the sequence
  ends for that lead instead. Clay does not log an event for the hold, the resume, or the end; the next sign of
  activity is the next `EMAIL_SENT`. Do not tell the user to resume these leads by hand.
- The out-of-office check happens only when the reply arrives. If the reply was uncategorized on arrival, the lead is
  already counted as replied, and categorizing it as OOO later does not change that.
- The `Reply to lead email` action does not run on OOO replies.

### `EMAIL_BOUNCE`

The email bounced. The bounce message is in `bounce.html` and `bounce.text`, with a shorter
`bounce.reply_email_preview`.

- `bounce.is_sender_originated_bounce` separates the two kinds of bounce. `false` means the lead's address bounced:
  the lead is marked bounced and gets no more emails. `true` means the receiving server rejected your sending side,
  often because static copy was flagged as spam. The lead's address may still be good, and the lead is not marked
  bounced. Suggest more copy variation (spintax, AI snippets, sender and lead variables) to reduce these.
- `lead` can be missing on a bounce. Use `recipient.email` (the `Lead email address` column already falls back to
  it).
- A high bounce rate on a campaign triggers an email alert to the campaign creator.

### `LEAD_UNSUBSCRIBED`

The lead unsubscribed. They get no more emails, and the lead is marked unsubscribed.

This event comes from the unsubscribe link, which only HTML campaigns with the link turned on include. A lead who
replies asking to stop produces an `EMAIL_REPLY` instead; use `Add email to blocklist` for those.

- `smartlead.lead_id` is usually empty on this event, so match the lead by `lead.email`.
- `sender` and `recipient` can be missing.
- `unsubscribe.client_unsubscribed_at` maps each provider client id to the unsubscribe time.

### `LEAD_CATEGORY_UPDATED`

The lead's category changed, either because the AI categorized a reply or because someone changed it by hand.

- `category.id`, `category.name`, `category.sentiment` hold the new category. `category.old_id` and
  `category.old_name` hold the previous one (null if there was none).
- `lead_category_update.current_sequence` is the step the lead was on. `reply_body_html` and `preview_text` hold
  the reply that was categorized.
- Address direction follows the same rules as `EMAIL_REPLY`.
- A category change does not stop or resume the sequence by itself.

### `CAMPAIGN_STATUS_CHANGED`

The campaign's status changed: `status_change.previous_status` → `status_change.current_status`. The event has no
lead fields. It is campaign-level, so filter it out when counting lead activity.

### `MANUAL_STEP_REACHED`

A manual (call, LinkedIn, or to-do) step is due: `manual_step.current_sequence`, `manual_step.scheduled_at`. This
type is reserved. Do not depend on it appearing. Completing a manual step can show up as an `EMAIL_SENT` with no
mailbox and no step number, so do not count those as real sends.

## Lead categories

`Reply category` uses these standard categories:

| Category                   | Sentiment | Notes                                             |
| -------------------------- | --------- | ------------------------------------------------- |
| `Interested`               | Positive  |                                                   |
| `Meeting Request`          | Positive  |                                                   |
| `Information Request`      | Positive  |                                                   |
| `Out Of Office`            | Neutral   | Does not stop the sequence; the lead auto-resumes |
| `Wrong Person`             | Neutral   | `Reply to lead email` does not run                |
| `Uncategorizable by Ai`    | Neutral   |                                                   |
| `Not Interested`           | Negative  | `Reply to lead email` does not run                |
| `Do Not Contact`           | Negative  | `Reply to lead email` does not run                |
| `Sender Originated Bounce` | Negative  | The sending mailbox failed, not the lead          |

Custom categories also appear, by name, on `LEAD_CATEGORY_UPDATED`. On `EMAIL_REPLY`, a custom category has a
`category_id` but no `category_name`.

## Building on these events

- Filter on `Event type` first. Columns that read type-specific fields are empty on other event types.
- For "who replied", use `Lead email address`. Do not use `Sender email address`.
- For "which rep owns this reply", use the `Get rep email` column. Do not use `Sender email address` on its own.
- For "real replies", exclude the `Out Of Office` category, and treat an empty category as a real reply.
- For "did they bounce", check `bounce.is_sender_originated_bounce` is `false` before treating the lead's address
  as bad.
- The same event can occasionally arrive twice. When exact counts matter, de-duplicate on `event_type`, `lead.email`,
  `sent.stats_id`, and `event.occurred_at`. For campaign totals, prefer `clay campaigns analytics`.
