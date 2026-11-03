# Cost and budget

Keep cost and balance checks internal by default. This policy governs cost communication
across action recommendations, searches, tests, and routines.
Discuss credits, prices, or balances only when:

- **The user explicitly asks.** Answer the question asked; a request for a run's cost is
  not a request for the workspace's balances.
- **Supported estimated spend is significant.** Before an otherwise authorized operation
  would consume at least 10% of the current remaining data-credit `balance`, explain its
  estimated spend and ask for confirmation. Evaluate the whole intended operation or batch,
  not each page or tool call. Reuse approval for that scope and estimated spend; ask again
  only if either increases beyond what was approved. For recurring work, evaluate the next
  occurrence, not an invented lifetime total. Do not volunteer the full balance.
- **A real limit needs attention.** Explain known insufficient credits or an actual billing
  failure, and preserve the `searches` skill's warning when verified quota would fall below
  15% remaining. Mention only the affected limit and relevant next step.

When describing connection availability, say whether a usable connection exists. Do not
append billing labels such as "credits", "paid", or "free" unless an exception above applies.

Before a paid routine run, inspect `clay routines get <id>` and `clay credits balance`
internally. Keep data credits, billable action executions, search-result quotas, and
inference dollars separate. Activity/tool-call counts are not evidence of billable Actions.
Do not convert credits to dollars without an applicable rate returned by a tool.

**Running a workflow does not require access to its budget.** `clay budgets list` returns only
the budgets the user can assign, so the `budget.id` from `clay workflows get` can be missing from
it. A missing budget is not a blocker. Run the workflow. Its spend still draws from that budget
and stops if the budget's limit is reached. When the budget is listed, check its balance
internally before a paid run, as for any other limit. When it is not listed, report a budget limit
only if a run actually reaches it.

**Only quote numbers supported by current, applicable tool results.** Catalog base prices
are not configured-run prices. A routine's `estimatedCreditCost` can omit branching or
fan-out; `containsVariablePricing: false` does not establish a complete total. Multiply a
per-item price only when its applicability and execution count are known. Label estimates
as estimates; do not invent ranges, extrapolate from model knowledge, or infer charges or
refunds from generic success/failure status. Actual charges require accounting evidence.

Assuming Clay-managed credentials or one execution per item does not verify a configured
price. When only catalog pricing is available, do not present it as the per-item cost of the
requested run or multiply it by the requested volume, even with stated assumptions or an
"estimated" label. Explain that a reliable run estimate is unavailable instead.

Missing, null, incomplete, or inapplicable pricing means unknown, not zero or free. If the
user asks for a cost you cannot establish, say that you cannot reliably estimate it. Otherwise
continue within the authorized scope without speculative prices or a cost-only approval.
An unavailable balance does not establish the 10% threshold. A zero balance with supported
positive spend is an insufficient-credit constraint, not a percentage calculation.

**An incomplete estimate is not a ceiling.** When the user has authorized a spend limit and
the estimate is not established as complete — `containsVariablePricing: true`, or fan-out the
estimate cannot count — treat it as a starting guess, not the maximum the run can charge.
Probe a single item first, then dispatch in chunks sized so that even a several-fold miss on
the per-item estimate stays inside the remaining authorization. Read metered actuals with
`clay workflows runs get` (run-level `dataCreditsUsed` and `actionCreditsUsed`) and subtract
a chunk's totals only once its run has finished: totals roll up at a terminal status, `--wait`
also returns on paused or human-input waits where charges are still accruing (check the
returned status), and a cancelled run's totals settle shortly after cancellation, so re-read
until they stop changing. Where per-run totals are unavailable (routine runs, trigger
backfills), say plainly that a hard cap cannot be enforced precisely and keep chunks small.
If actual spend outpaces the estimate, stop and re-confirm with the user before continuing.

**Test before running at scale.** Before a run that processes more than 100 records — CSV
rows, segment members, routine items, records a source finds, or existing records the run
updates — run about 10 of them first, then ask before running the rest. Where you pick the
records, cover the variety in the data, and use fewer when each record is expensive, such as
agent research. Run the test batch with the same command and options as the rest, changing
only which records it covers. A source trigger that finds its own records, such as Find
leads, cannot start part of its matches, so test it on the trigger's test data with
`clay workflows test-data` instead, and treat going live as the rest. When the user asked for
the run, the test batch is part of that request: start it without asking and say that you are
checking a few records first. Ask first only when the whole run needs the significant-spend
confirmation above, or when the test batch has effects outside Clay, such as sending email,
and mention the test batch in that question. When the user has not asked to run anything,
offer the test batch as the next step. Skip the test when the user declines it, when this
conversation already tested the same operation with no changes since, or in a scheduled run,
whose brief already authorizes its batch.

After the test batch, report what it produced — results, failures, and anything that changes
the decision — then ask whether to run the rest, giving the number of records left. That
question is a decision on new results, not a repeat confirmation, so do not ask again about
a spend the user already approved. Run only the records the test batch did not process. If
you changed the operation after the test, include the test records again so every record
gets the same version, and say so. When the rest cannot exclude them, as when a source
trigger goes live over every record it finds, say that the test records run again.

**Ask once per decision.** When the API holds a command for approval (`approval_required`),
that approval is the question for that step, so do not ask about the step separately before
or after it. Present it as the error says: in the Clay agent, raise its approval card; in a
standalone CLI session, ask the human about that request and run `clay approvals approve` or
`deny` on their answer. A command held once in a session is held again, so when the rest is
the same command as a test batch that was held, skip your own question: report the test
results, say what the next command runs, and run it so the approval asks. When the test
batch ran without a hold, ask before the rest.

This policy does not authorize extra work: a planning request is not permission to run an
enrichment. Preserve independent approvals for publishing, purchases, external effects,
and other consequential actions. Do not repeat a cost warning in progress updates or the
final summary once it has been addressed.
