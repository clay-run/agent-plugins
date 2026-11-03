# Configure an ad sync's field mapping

The field mapping picks which audience field fills each ad platform field. One mapping covers all
of a sync's destinations.

The sync must be a draft or paused, with at least one destination. Pause a running sync first,
with the user's OK: `clay ad-syncs pause <adSyncId>`. Set the enrichment tier before mapping,
because it changes how `EMAIL` is mapped.

## Steps

1. Run `clay ad-syncs get <adSyncId>`. Map only its `eligibleFieldKeys`. `fieldMapping` is the
   saved mapping, `adSync.source.type` is `COMPANY_AUDIENCE_SEGMENT` for a company sync, and
   `adSync.enrichConfig` is null when there is no tier.
2. List the fields with `clay audiences fields list --entity-type people` for a people sync, or
   `clay audiences fields list --entity-type companies` for a company sync. A people sync needs the
   companies list too, because `COMPANY_NAME` takes a companies field.
3. Start from the saved mapping, or else the defaults below. Drop keys that are not in
   `eligibleFieldKeys`, and field ids that are not in the field lists. `hashed_email_1`,
   `hashed_email_2`, and `hashed_email_3` are allowed as `EMAIL` ids; see People Syncs Emails for
   when to include them.
4. Show the user each platform field next to the audience field's name, plus any eligible keys
   left unmapped, and apply their changes.
5. Run `clay ad-syncs field-mapping update <adSyncId> --input '<json>'`. It replaces the whole
   mapping. Compare the output with what you sent, because ineligible keys are dropped silently.

On a paused sync, the new mapping takes effect once the user resumes it in the Clay app.

## Defaults

These are the Clay app's defaults. People syncs, leaving out `EMAIL` when the sync has a tier:

```json
{
  "EMAIL": ["email"],
  "FIRST_NAME": "first_name",
  "LAST_NAME": "last_name",
  "TITLE": "title",
  "PHONE": "phone",
  "CITY": "location_city",
  "STATE": "location_state",
  "COUNTRY": "location_country",
  "COMPANY_NAME": "org_name"
}
```

Company syncs, where the first three keys are required:

```json
{
  "COMPANY_NAME": "org_name",
  "COMPANY_WEBSITE": "domain",
  "LINKEDIN_COMPANY_URL": "linkedin_url",
  "CITY": "location_city",
  "STATE": "location_state",
  "COUNTRY": "location_country"
}
```

`COUNTRY` should map a field of two-letter ISO country codes. A field of full country names also
works: Clay converts names on a best-effort basis, and a value it cannot convert is not sent.

`GENDER`, `ZIP_CODE`, and `MOBILE_ADVERTISER_ID` have no default. Map them only to a field the user
confirms.

## People Syncs Emails

- Without a tier, `EMAIL` must be mapped. Prefill `email`. Mapping `hashed_email_1`,
  `hashed_email_2`, and `hashed_email_3` is also fine.
- With a tier, Clay adds the enriched emails itself, so don't prefill `EMAIL`. Leave `email` and the
  `hashed_email_*` fields out when configuring the mapping, and leave `EMAIL` out entirely unless
  the user adds email fields. The saved mapping still lists the `hashed_email_*` fields, because
  Clay adds them.
- In both cases, ask the user whether they want to send additional email fields (for example,
  fields whose `dataType` is `email`). If the sync goes to LinkedIn, recommend sending as few emails
  as possible.
- LinkedIn matches best on work emails, and the other platforms on personal emails. Ask the user
  when a field's name doesn't say which it is.

## Rules

- Each audience field can fill only one platform field.
- Use ids from `fields list`, never ones guessed from display names, and no system fields.
