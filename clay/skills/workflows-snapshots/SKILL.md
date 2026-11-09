---
name: workflows-snapshots
description: 'Clay workflows — version history: view snapshots, see what changed, and restore or undo a previous state. Use when the user mentions snapshots or asks to undo an edit.'
allowed-tools: Bash(clay *), Bash(jq *), Read
---

# Workflow snapshots & version history

Before using this skill, read the `clay` entry skill if you haven’t already this session, and follow its access guidance.

Snapshots are immutable, point-in-time captures of the entire workflow graph — nodes, edges, prompts, scripts, tools, and positions.

## Key concepts

- **Automatic creation**: after every graph-mutating node edit
  (`clay workflows nodes` create|update|delete) and when a
  run starts. `data[0]` is newest-by-`createdAt`, **not** necessarily the current
  graph. Sharing/binding a trigger onto an existing node does **not** snapshot —
  undo that create by deleting the trigger, not restore. Settings-only trigger
  update/delete also do not snapshot — revert or recreate the settings; do not
  delete the trigger and do not restore. `graph format` takes two snapshots when
  validation has no errors (pre-layout, then post-layout); details under Undo.
- **Restore does not reshuffle the list**: `snapshots restore` rewrites the draft but does not create or reorder snapshots. Duplicate hashes reuse the existing row without updating `createdAt`. After a restore, `data[0]` can be a later history entry that is not the current graph, so the next edit's `data[1]` is often that stale entry rather than the pre-edit graph. Compare the latest snapshot to the current graph (or find the list row that matches) before treating `data[1]` as the undo target.
- **Content-addressed**: Each snapshot has a SHA-256 hash of its contents. Identical workflow states deduplicate to the same hash
- **Immutable**: Once created, a snapshot's graph content never changes
- **Run isolation**: Runs are pegged to a specific snapshot. Editing the workflow doesn't affect in-flight runs

### Draft-history vs published versions

The same snapshot table holds two roles:

| Role                  | When                                  | Purpose                                                                                |
| --------------------- | ------------------------------------- | -------------------------------------------------------------------------------------- |
| **Draft-history**     | Auto on edits / run start             | Undo log and run pegging. No release number.                                           |
| **Published version** | User clicks **Publish** in the editor | Numbered release (`version`, optional `name`). Becomes the live graph automation runs. |

Publishing marks a snapshot of the current draft as a numbered release; it does not create a separate store. See the workflows entry-point skill's `publishing.md` for draft vs live.

**This skill is for undo/history** (`list` / `get` / `restore`). Publishing is a separate command (`clay workflows publish`). `clay workflows snapshots list` returns only the most recent snapshots (newest first) and is not a complete or reliable index of published versions — an older release can fall outside its window. To map a version like "V4" to its snapshot id (e.g. to filter runs by version), use `clay workflows versions list <workflowId>`, which lists every published version with its `number`, `label`, and `id`; select by the unique `number` for a `V{n}` version (or by `label` for a named one) and use that `id`.

## CLI reference

For tool access or authentication problems, read the `clay` entry skill before continuing.

### List recent snapshots

```bash
clay workflows snapshots list <workflowId>
```

Returns `{ data: [...] }`, newest first, each with `id`, `hash`, `createdAt`, and
`nodeCount`/`edgeCount`. So `data[0]` is the most recent snapshot by `createdAt`,
which may not be the current graph (see restore above). This list is capped at the
most recent snapshots — to look up a published version, use `versions list` (below).

### List published versions (label → snapshot id)

```bash
clay workflows versions list <workflowId>
```

Returns `{ data: [...] }` of every published version, ordered by version `number`
descending, each with `id`, `number`, `name`, `label`, and `publishedAt`. This is the
complete, reliable index for mapping a version the user names ("V4", or a published name)
to its snapshot `id` — e.g. to filter runs by version. Published names are not guaranteed
unique, so a `label` can match more than one entry; prefer the unique `number`
(`select(.number==4)`) when the user names a `V{n}` version, and only match on `label` for a
named version. Unlike `snapshots list`, it is not
capped and excludes draft-history snapshots. Note the highest `number` is not necessarily
the currently-live version: restoring an older version and republishing reuses that
version's number, so it can outrank later ones. To find which version a run actually used,
read `workflowSnapshot.id` from a recent run row (`clay workflows runs query run` / `runs list`) rather than assuming `data[0]`.

### Show a snapshot (whole graph, or one node)

```bash
clay workflows snapshots get <workflowId> <snapshotId>
clay workflows snapshots get <workflowId> <snapshotId> --node-id <nodeId>
```

Returns the full captured graph: `nodes` (with types, prompts, code, tools) and
`edges`. `--node-id` narrows `nodes` to a single node (edges are left intact).

### Diff two snapshots

There is no built-in diff. Fetch both and compare with `jq` — but this raw `diff`
is the underlying mechanism, not the thing you show the user:

```bash
clay workflows snapshots get <workflowId> <oldSnapshotId> | jq '.nodes' > old.json
clay workflows snapshots get <workflowId> <newSnapshotId> | jq '.nodes' > new.json
diff <(jq -S . old.json) <(jq -S . new.json)
```

**Translate the diff into a plain-language change summary** rather than pasting the
raw `diff` output — e.g. "Node _Find Email_'s prompt changed; the edge _Research →
Draft_ was removed; a new _Score Lead_ agent node was added." When the change alters
the graph's structure (nodes or edges added/removed/rewired), render before/after
Mermaid diagrams so the user can see it, not just read it (see the workflows
entry-point skill's `presenting.md`).

The only built-in diagram command always renders the workflow's **current** graph:

```bash
clay workflows diagram <workflowId> | jq -r '.diagram'   # always the current graph
```

There's no diagram command for an arbitrary snapshot id, so hand-write a small
node/edge list from that snapshot's `nodes`/`edges` for its side. Label the diagrams
by the direction of the change: "before" is the state you're changing _from_, "after"
is the state you're ending up _with_ — and use the command above for whichever side is
the current graph. When previewing a restore (see "Restore to a snapshot" below), the
restore overwrites the current graph with the snapshot, so the current graph is the
"before" and the snapshot you're restoring to is the "after".

### Restore to a snapshot

```bash
clay workflows snapshots restore <workflowId> <snapshotId>
```

Restores the workflow to the exact state captured in the snapshot. This replaces
all current nodes, edges, prompts, scripts, and tools. Restore is destructive and
does NOT snapshot the current graph first, and does **not** move the restored
snapshot to the top of `list` — `data[0]` can still be a later history entry.
The pre-restore state is recoverable only if a later edit or run already
triggered a fresh snapshot capturing it (snapshots are taken automatically
**after** each graph-mutating edit and at run start). If the current graph has
unsnapshotted changes you might want back, run `snapshots list` first and note
the snapshot that **matches** the current graph, not blindly `data[0]`.

**Restore ≠ publish.** Restore rewrites the **draft** only. It does not change which
snapshot is live, and undoing an edit does not roll back live automation. If the
user wants live triggers to match the restored draft, they must **Publish** again
in the editor (see the workflows entry-point skill's `publishing.md`).

**Before restoring, show the user what will change.** Summarize the difference
between the current graph and the target snapshot in plain language, and — when the
structure differs — show before/after diagrams (see "Diff two snapshots" above),
so the user can confirm the revert before it destructively overwrites the current
state. After restoring, render the restored graph so they can see the result.

## Common workflows

### Undo the last edit

Every **graph**-mutating write schedules a snapshot **after** it completes — fire-and-forget,
so the new row may lag. Do **not** assume `data[0]` is the current graph or that `data[1]` is
the pre-edit graph.

Trigger create only snapshots when it allocates a **new** canvas node. Sharing an existing
`workflowNodeId` is not in the snapshot hash — undo that create with
`clay workflows triggers delete`, not restore. Settings-only
trigger update/delete also are not snapshotted: revert or recreate the settings; do not
delete the trigger and do not restore.

`graph format` is two steps when validation has **no errors**: a **pre-layout** snapshot is
awaited, then a **post-layout** snapshot is scheduled. Restore the pre-layout id (same
nodes/edges, different positions). If validation had errors, the pre-layout snapshot is
skipped — `.data[1]` may be an older unrelated snapshot; do not restore it. If the graph
had no prior snapshot, wait until the post-layout row has landed before treating
`.data[1]` as the undo target.

**Compare `snapshots get` vs the current graph** (`clay workflows graph get --mode full`) to tell current from newest-by-`createdAt`. If no
row matches, the post-edit snapshot may still be in flight — poll or restore `.data[0]`
(step 4); do not search for a snapshot of the unsnapshotted current graph. Poll by repeating the snapshot list operation rather than running a shell
`for`/`seq`/`sleep` loop.

```bash
clay workflows snapshots list <workflowId> | jq -r '.data[0].id'   # newest — not always current
clay workflows snapshots list <workflowId> | jq -r '.data[1].id'   # next older — not always pre-edit
clay workflows snapshots restore <workflowId> <snapshotId>
```

1. **Find `before_id` before the edit:** if `.data[0]` matches the current graph, `before_id`
   is `.data[0].id`. If not, walk the list until a row matches — that id is `before_id`. If
   none match, there is no restorable pre-edit snapshot; do not pass a null id to `restore`.
2. **With `before_id` (node/trigger edits):** after the write, restore **`before_id`**. Do not
   restore `.data[1]` as a proxy — after a restore that id can be a later history entry.
3. **With `before_id` (after `graph format`):** restore **`before_id`** only if that id
   matched the current graph **before** format. If you had no matching snapshot before
   format, call `list` until `.data[0]` matches the current (post-layout) graph, then
   restore `.data[1].id` **only if it is the pre-layout graph** (same nodes/edges, different
   positions). If validation had errors, that pre-layout row was never created — `.data[1]`
   can be an older unrelated snapshot; if so (or if `.data[1]` is missing), report no
   restorable pre-layout snapshot rather than rolling back more than the layout.
4. **Without `before_id` (late undo):** compare `.data[0]` to the current graph. If they
   match, restore `.data[1].id` **only if it exists** — and only when you know `.data[0]` was
   already the current snapshot before the last edit (usual linear history). If `.data[1]` is
   missing, report no restorable pre-edit state. If they do **not** match, walk the list for
   a row that matches the current graph. If an **older** row matches (post-restore), restore
   **that** id — not `.data[1]`, which can roll the workflow forward. If **no** row matches,
   the post-edit snapshot has not landed (fire-and-forget lag): poll `list` a few times. If
   `.data[0]` then matches, follow the match case above. If still none, restore `.data[0]`
   (still the pre-edit graph in linear history). Do not look for a snapshot of the current
   unsnapshotted graph — it cannot exist until that async row lands. Do not pass a null
   snapshot id to `restore`.

To undo multiple edits, pick an older snapshot id from the list instead.

Remember: this only rolls back the draft. Live automation (if already published)
keeps running the previously published version until the user publishes again.

### Compare current state to a previous version

List snapshots, then diff two of them with the `jq` recipe above.

### Review what a run executed

Since runs are pegged to snapshots, inspect the exact workflow state a run used by
looking up the run's snapshot id and passing it to `snapshots get`.
