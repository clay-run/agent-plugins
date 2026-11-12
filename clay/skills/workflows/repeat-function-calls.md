# Repeat on workflow function calls and waterfalls

Read the parent skill's "List mode (Repeat)" section first: turning Repeat on, `listEntriesRef`,
and `listFailureMode` work the same way here. Repeat on a call or waterfall has its own workspace
gate. If it rejects with "Workflow function calls do not support Repeat yet", don't retry; use
Repeat nodes instead.

## Workflow function calls

A repeating `subworkflow_call` runs the function once per item, each item in its own run. That run
receives only the item's fields and the call's mapped inputs, so every input needs a mapping in the
call's `inputMappingConfig`:

- Varies per item: `item` (`{ "type": "item", "path": "$.field" }`).
- Fixed: `static`.
- Same upstream value for every item: `reference`, with each `{{variable}}` bound by a pinned input
  of that name (`sourceNodeId`/`sourcePath` on the `inputSchema` property). An unbound variable
  resolves to nothing.

A pinned input with no mapping isn't passed; a same-named item field fills it, or it is missing.
When turning on Repeat for an existing call, add a `reference` mapping
(`{ "type": "reference", "expression": "{{region}}" }`) for each pinned input that has none and stays
the same for every item, and keep the pin. `inputMappingConfig` replaces the existing mappings, so
send them all.

## Native waterfalls

`waterfallConfig` must be sent on its own, so turning on Repeat takes two updates:

1. Set `listMode` and `listEntriesRef`.
2. Send the complete `waterfallConfig` with each per-item input mapped to the current item, as `item`
   or `{{__item.field}}` in a `reference`. That covers shared inputs and provider-specific inputs in
   a provider's `inputOverrides`; one left on the upstream list passes the whole list to every item.
   Keep both sets of `inputRefs` (`{}` when there are none), e.g.
   `"sharedInputs": { "inputMappingConfig": { "company-domain": { "type": "item", "path": "$.domain" } }, "inputRefs": {} }`.

A waterfall that maps the current item can't be saved without Repeat. To turn Repeat off, remove
those mappings from the shared inputs and provider overrides first, then set `listMode` to `false`.
Either way, the draft is only half configured between the two updates, so test or run it only after
both.

## Several steps per item

When each item needs more than one step (enrich, then score, then draft), first try one workflow
function that does those steps for a single item, called with Repeat. Set `listMode` and
`listEntriesRef` when you create the call, so a rejection comes before any other wiring. If it is
rejected, delete the call if it was created and chain one Repeat node per step instead.

A repeating call is better because each Repeat node in a chain starts only after the previous one has
finished every item, while each item's function run moves through all its steps on its own and shows
them together. On plans with a run limit, each item's run counts toward the function's own allowance.

Build the function's nodes to handle one item, without Repeat. Don't use
`clay workflows groups publish-as-function` on existing Repeat nodes: it keeps their Repeat
settings, so the function takes the whole list. A single step per item stays a Repeat node.

## Partial failures

With `fail_at_end`, the default, a node fails once every item has finished if any of them failed, and
the run stops there:

- **Chain:** one failed item stops the run at the first step, so later steps never run, even for the
  items that succeeded.
- **Repeating call:** the items that succeed still finish every step; then the call fails and nothing
  after it runs.

Ask whether partial results are acceptable, then set `listFailureMode` explicitly on every Repeat
node in a chain, or on the call: `ignore_errors` to continue with the items that succeeded, or
`fail_at_end` when one bad item should stop the run. Don't rely on the saved value: a waterfall whose
Repeat was turned on in the editor already has `ignore_errors`. Remind the user that `ignore_errors`
only continues when some, not all, items fail.
