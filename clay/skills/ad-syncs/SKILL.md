---
name: ad-syncs
description: Clay ad syncs — push an audience segment to ad platforms (LinkedIn, Meta, Google, Bing, Reddit, Vibe) as a custom audience. Use to create, edit, pause, or map the fields of an ad sync, or to check its status, match rate, or run history.
---

# Ad syncs

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

An ad sync pushes an audience segment to ad accounts on ad platforms, called its destinations. Each
platform matches the records and builds an audience to advertise to.

## Supported commands

- `clay ad-syncs list [--limit <n>] [--cursor <cursor>]`
- `clay ad-syncs get <adSyncId>`
- `clay ad-syncs get-by-source --source-id <segmentId> --entity-type <people|companies>`
- `clay audiences get <segmentId>`
- `clay ad-syncs create --name <name> --source-id <segmentId> --entity-type <people|companies> --schedule-type <ONE_TIME|RECURRING>`
- `clay ad-syncs update <adSyncId> [--name <name>] [--schedule <ONE_TIME|RECURRING>] [--tier <PREMIUM|STANDARD>]`
- `clay app-accounts list --filter type=<provider>-ad-audience`
- `clay ad-syncs ad-accounts list <appAccountId> --provider <provider>`
- `clay ad-syncs destinations create <adSyncId> --provider <provider> --app-account-id <appAccountId> --ad-account-id <accountId> [--ad-user-data-consent <status> --ad-personalization-consent <status>]`
- `clay ad-syncs destinations update <adSyncId> --destination-id <destinationId> [--app-account-id <appAccountId>] [--ad-account-id <accountId>] [--ad-user-data-consent <status>] [--ad-personalization-consent <status>]`
- `clay ad-syncs destinations delete <adSyncId> --destination-id <destinationId>`
- `clay ad-syncs field-mapping update <adSyncId> --input '<json>'`
- `clay ad-syncs pause <adSyncId>`
- `clay ad-syncs runs list <adSyncId> [--limit <n>]`

Run `clay ad-syncs <subcommand> --help` before a subcommand's first use. It has the exact output
shape, value sets, and error codes. `<provider>` is `LinkedIn`, `Meta`, `Google`, `Bing`, `Reddit`,
or `Vibe`, written in lowercase inside `type=<provider>-ad-audience` (e.g.
`type=linkedin-ad-audience`). An `<accountId>` is an `accountId` from `ad-accounts list`, and a
`<destinationId>` is a `providerSyncConfigs[].id` from `get`.

## Limits

- You can always create an ad sync, and edit it while it is a draft or paused.
- You cannot delete an ad sync: the user deletes it in the Clay app. A segment can have only one ad
  sync, so create one only for a segment the user confirmed.
- Pause a running sync only when the user asks. Before running `pause`, tell them what pausing does
  (see Statuses) and ask them to confirm, even when they asked for it. Never start or resume one:
  the user does that in the Clay app, from the sync's `url`.

## Schedules

- `ONE_TIME`: it exports once, when the user starts it.
- `RECURRING`: it syncs continuously to its destinations, so they stay up to date with the people
  or companies the user wants to target.

## Statuses

Tell the user the label in parentheses, not the raw value.

- `DRAFT` (Draft): not started yet.
- `PROCESSING` (Processing): an export is running, including enrichment when the sync has a tier.
- `ACTIVE` (Active): a recurring sync whose latest export reached every destination. It exports
  again on its schedule.
- `DONE` (Exported): a one-time sync that reached every destination.
- `WARNING` (Warning): some destinations failed. A one-time sync reached only some of them, or a
  later export of a recurring sync failed on at least one, and the sync stays live. `runs list`
  shows which destinations failed.
- `FAILED` (Failed): a one-time sync that failed on every destination, or a recurring sync whose
  first export failed on any destination.
- `BULK_ENRICHMENT_FAILED` (Enrichment failed): the enrichment step failed.
- `PAUSED` (Paused): the user paused it. Clay stops enriching new records in the segment, so it
  stops spending credits, and stops pushing new records to the ad platforms. The audiences already
  on the platforms stay as they are until the user resumes the sync in the Clay app.

## Create

Confirm each choice with the user before running the command that makes it.

1. **Draft.** Read the segment's `entityType` with `clay audiences get <segmentId>`, then run
   `clay ad-syncs get-by-source --source-id <segmentId> --entity-type <entityType>`. If it returns a
   sync, use that one. If it returns `not_found`, ask whether the sync should run once or on a
   recurring schedule, and create it:

   ```bash
   clay ad-syncs create --name "<name>" --source-id <segmentId> --entity-type <entityType> --schedule-type <ONE_TIME|RECURRING>
   ```

2. **Accounts.** For each platform, run `clay app-accounts list --filter type=<provider>-ad-audience`.
   If it returns one connection, pick it. If it returns more than one, list them by name and ask the
   user which to use. Don't check any connection's ad accounts before the user picks one, even if
   you expect only one to work.

   You MUST check the picked connection before using it, every time, including when it is the only
   one: run `clay ad-syncs ad-accounts list <appAccountId> --provider <provider>`. Never pass an
   `--app-account-id` to any command until that check has succeeded for it in this conversation. If
   the check errors, don't use the connection: tell the user it couldn't load its ad accounts and
   ask them to pick another one.

   An ad account is usable when `canManageAudiences` is true, `restrictions` is empty, and it has
   not already been added to this ad sync: compare its `accountId` with the
   `providerSyncConfigs[].providerAdAccount.id` values from `clay ad-syncs get <adSyncId>`. If there
   are none, the user sets them up in the Clay app from the sync's `url`. Continue once they're done.

3. **Destinations.** Ask which ad accounts to advertise to, then add each one:

   ```bash
   clay ad-syncs destinations create <adSyncId> --provider <provider> --app-account-id <appAccountId> --ad-account-id <accountId>
   ```

   Company syncs go to LinkedIn only. For Google, ask the user for both consent values and add
   `--ad-user-data-consent <status> --ad-personalization-consent <status>`. Send `UNSPECIFIED` if
   they don't track consent.

4. **Enrichment tier** (people syncs only). Best match rates is
   `clay ad-syncs update <adSyncId> --tier PREMIUM`, Good match rates is
   `clay ad-syncs update <adSyncId> --tier STANDARD`, and none means skipping this step. A tier
   costs credits and can't be changed once set. To see what each tier costs, the user opens the
   sync's `url` in the Clay app.

5. **Field mapping.** Read `field-mapping.md` and follow it.

Then give the user the sync's `url` so they can review it and start it in the Clay app.

## Edit

Check `adSync.status` with `clay ad-syncs get <adSyncId>` first. `DRAFT` and `PAUSED` syncs can be
edited. A running sync (`PROCESSING`, `ACTIVE`, or `WARNING`) has to be paused first. Tell the
user it has to be paused and what pausing does, and ask them to confirm before running
`clay ad-syncs pause <adSyncId>`. `DONE`, `FAILED`, and `BULK_ENRICHMENT_FAILED` syncs
can't be edited.

- Rename: `clay ad-syncs update <adSyncId> --name "<name>"`
- Change the schedule: `clay ad-syncs update <adSyncId> --schedule <ONE_TIME|RECURRING>`
- Set a tier, only if it has none: `clay ad-syncs update <adSyncId> --tier <PREMIUM|STANDARD>`
- Add a destination: follow steps 2 and 3 of Create.
- Change the ad account for a destination: `clay ad-syncs destinations update <adSyncId> --destination-id <destinationId> --ad-account-id <accountId>`,
  adding `--app-account-id <appAccountId>` if that ad account is under another connection. The
  synced audience will then exist in a different ad account, so confirm the change with the user
  first. A Google destination needs both consent flags again when its ad account changes.
- Switch the connection a destination syncs through, keeping its ad account: `clay ad-syncs destinations update <adSyncId> --destination-id <destinationId> --app-account-id <appAccountId>`
- Remove a destination, on drafts only: `clay ad-syncs destinations delete <adSyncId> --destination-id <destinationId>`
- Change the field mapping: follow `field-mapping.md`.

A paused sync stays paused. The edit takes effect once the user resumes it in the Clay app.

## Read

1. Find the sync with `clay ad-syncs list`, paging with `--cursor <cursor>`, or with
   `clay ad-syncs get-by-source --source-id <segmentId> --entity-type <people|companies>` when the
   user names the segment.
2. Read its setup with `clay ad-syncs get <adSyncId>`.
3. Read its results with `clay ad-syncs runs list <adSyncId> --limit 100`. The default returns only
   the 20 newest runs across all destinations, so a destination's latest run can be missing without
   the higher limit. If a destination has no run in the result, say so rather than guessing. Report
   each destination's latest run in plain words (status, match rate, and audience size), and link
   the sync's `url`. Google and Bing have no single audience size: report the size for each
   network in the run's `google` or `bing` object. For a failed run, relay its `errorMessage`, which says what went wrong
   and what the user can do about it.
