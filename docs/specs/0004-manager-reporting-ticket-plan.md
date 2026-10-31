# Proposed child tickets for specification #60

Draft for user approval. No child issues have been published. Numbers below are proposal IDs, not GitHub issue numbers.

- **dependencies:** Only prerequisites, not preferred release order. Numbers are local proposal IDs until publication.
- **priority:** Deliver 1–9 first; other independent tickets may proceed when prioritized. Policy decisions do not gate unrelated work.
- **verification:** Use authorized domain commands and real temporary SQLite through analytics snapshots, with existing widget/export checks where needed. All framework tests and builds run only in GitHub Actions.
- **invariants:** Retain standalone SQLite, in-place migrations, two interactive roles, Integer Paisa, settlement locks, original closed reports and immutable recording times. Use Context7 before implementation/refactoring. Each implementation includes scoped UI, safe source details, matching exports, coverage explanations, documentation and remote CI checks; reuse existing schema where sufficient.

Every implementation ticket includes its relevant schema/domain operation, authorized report UI, matching source/export behavior, coverage documentation and remote CI validation. Reuse existing storage where no migration is needed. Policy tickets deliver approved decision records and worked acceptance examples; they do not silently select business policy.

## 1. Show auditable identities, Pakistan time and snapshot provenance

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Report rows and CSV/XLSX/PDF distinguish Shift-owner Cashier from recording/approval actors, display known timestamps in Asia/Karachi and retain the source schema version.

### Acceptance criteria

- [ ] Display Business Day and Shift start/end where known; distinguish event and recording timestamps without fabricating missing fields.
- [ ] Preserve original UTC/offset evidence and disclose naive legacy assumptions, including local-midnight examples.
- [ ] Capture schema/report version at snapshot load; show/export scope, cutoff and quality consistently, with Manager authorization preserved.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 2. Record independent checkout receipts and refund events

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Cashiers record cash/digital receipts and refunds with their actual time, immutable recording time and receiving Shift independently of the originating Order.

### Acceptance criteria

- [ ] Persist stable event/order/tender/movement links, signed Integer Paisa, Payment Source, receiving Business Day/Shift and actors atomically with the authorized operation; retain change and rounding evidence.
- [ ] Default prompt entries to entry time; support explicit late actual time only within authorized open-period operations; do not create a closed-day correction workflow.
- [ ] Expose events and originating/receiving relationships in Manager source rows and exports, including cross-Shift collections; prevent retry duplicates and partial writes.
- [ ] Migration preserves legacy balances and sealed reports; unknown historical timing/attribution remains disclosed rather than backfilled.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 3. Trace COD settlement to the actual receiving Shift

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers can trace a rider handover or confirmed digital settlement to its actual receiving Shift without moving the original Order or counting both tender and Cash Movement.

### Acceptance criteria

- [ ] Use stable settlement/event/movement links and actual handover time; preserve existing settlement locks and Cashier-only tender authority.
- [ ] Display order origin, receiving Shift and recorded-by separately; direct digital settlement adds no drawer cash.
- [ ] Show unavailable customer-to-rider collection evidence honestly; delivered status and expected pouch amounts remain insufficient proof of collection.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

Proposal ticket 2

## 4. Report finance payments by actual time and Payment Source

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Expense, supplier and payroll/advance payments appear in a dated finance timeline with drawer, bank/digital and owner streams separated.

### Acceptance criteria

- [ ] Retain actual and recording time plus stable links to existing finance records and physical Cash Movements, adding evidence atomically where absent.
- [ ] Show Manager recorder separately from Shift owner; non-drawer payments legitimately have no physical Shift and never alter drawer cash.
- [ ] Exclude accruals and unpaid credit purchases from flow, classify internal transfers separately and prevent linked finance/movement double counting.
- [ ] Prompt and authorized open-period late entries are supported; unknown historical times stay unknown and closed-period corrections are excluded.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 5. Reconcile one selected Cashier Shift end to end

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Selecting a Cashier/Shift produces one reconciled physical cash bridge with matching source rows and exports.

### Acceptance criteria

- [ ] Reconcile Opening Float, customer receipts, rider handovers, pay-ins, refunds, expenses, supplier payments, payroll/advances and cash drops exactly once.
- [ ] Show expected cash, Blind Count and signed counted-minus-expected Discrepancy; an uncounted Shift has unavailable variance.
- [ ] Use receiving/owning Shift scope, retain cross-cohort collections and keep recorded-by distinct; label order-only breakdowns without narrowing whole-drawer accountability.
- [ ] Show legacy gaps and withheld complete totals where authoritative reconciliation is impossible; do not deduplicate by amount/time similarity.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

Proposal ticket 2, Proposal ticket 3, Proposal ticket 4

## 6. Select Business Day or calendar-time order activity

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers switch Order activity between assigned Business Days and actual Asia/Karachi calendar date/time, with matching ranges and exports.

### Acceptance criteria

- [ ] Default to Business Day; use inclusive-start/exclusive-end boundaries and preserve distinct Business Day IDs even on one opening date.
- [ ] Show both order timestamp and assigned Business Day; an overnight Order changes calendar bucket without changing its assignment.
- [ ] Persist time basis/grouping in the query and immutable snapshot; explain calendar versus operational weekday, Monday-start weeks and local months.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 7. Rank busiest Order days and hours separately from sales value

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers see distinct daily/hourly workload and value rankings, with cancellations, refunds and average ticket explained separately.

### Acceptance criteria

- [ ] Count every confirmed Order once including later cancellations/refunds; Holds and Order Revisions create no extra Orders.
- [ ] Retain valid-sales definitions and label value/average-ticket eligibility; use corresponding eligible count rather than workload count indiscriminately.
- [ ] Include all tied peaks, sort ties chronologically and show 24 observed hourly buckets; distinguish true zero from missing coverage.
- [ ] Chart, contributors and exports reconcile for both time bases; preserve distinct Business Days.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

Proposal ticket 6

## 8. Compare weekdays fairly and explore recurring Order peaks

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers see weekday totals, completed-Business-Day averages, weekday-by-hour activity and weekly/monthly trends.

### Acceptance criteria

- [ ] Primary weekday ranking displays completed-day numerator/denominator, includes opened zero-order days, separates open days and returns unavailable for zero denominator.
- [ ] Label operational weekday versus actual calendar weekday, including post-midnight hours; do not invent unopened Business Days.
- [ ] Render a weekday/hour table or heatmap and Monday-start weekly/local-month trends with identical export buckets and coverage.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

Proposal ticket 7

## 9. Explore actual-time inflow, outflow and net-flow peaks

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers rank money-flow periods by actual time and funding stream, independently of Order workload or sales value.

### Acceptance criteria

- [ ] Apply the explicit time-basis query to canonical finance and receipt evidence, including receiving events whose Orders are outside the selected cohort.
- [ ] Show nonnegative inflow/outflow magnitudes and signed net; rank highest inflow/outflow and greatest/least net with all ties.
- [ ] Separate drawer, bank/digital and owner streams, disclose internal transfers and exclude accruals, unpaid purchases and duplicate custody legs from consolidated receipts.
- [ ] Unknown event time/receiving attribution is excluded from unsupported buckets with coverage; retain a clearly labeled legacy order-cohort view.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

Proposal ticket 5, Proposal ticket 6

## 10. Preserve transaction-time staff, supplier and category names

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

New relevant records retain historical names while reports distinguish transaction-time and current identities.

### Acceptance criteria

- [ ] Keep stable IDs and existing snapshots; add missing event-time snapshots at relevant writes without rewriting old history.
- [ ] Display/export current names only as separately labeled context and mark unavailable old names.
- [ ] Verify rename/archive scenarios across representative staff, supplier and category records with existing authorization unchanged.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 11. Decide closed-day correction authority and reconciliation policy

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-human`

### What to build

A reviewed policy resolves who may append historical corrections and how they reconcile while preserving the two-role boundary.

### Acceptance criteria

- [ ] Decide approval authority, append-only evidence, source links, reversals, reconciliation and correction cutoff semantics, with worked late-payment examples.
- [ ] Keep sealed reports/hashes immutable and forbid a new current-day drawer movement for cash already moved historically.
- [ ] Resolve how to record historical evidence without giving Managers live tender/Shift authority; record explicit approval before enabling implementation.

### Blocked by

None (can start immediately).

## 12. Append approved historical corrections and show adjusted reports

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Authorized users can append policy-backed historical corrections and Managers can compare original and correction-adjusted results.

### Acceptance criteria

- [ ] Implement the approved authority/reversal rules and link actual time, recording time, affected Business Day and original evidence.
- [ ] Display adjustment bridge and cutoff separately from immutable original X/Z reports; export both bases clearly.
- [ ] Reject duplicate or unreconciled physical effects; prove original balances, sealed content/hashes and recording timestamps are unchanged.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

Proposal ticket 5, Proposal ticket 11

## 13. Decide earned-period payroll and labor allocation rules

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-human`

### What to build

A reviewed policy defines monthly earned payroll and the attendance/department allocation inputs needed for reliable labor reporting.

### Acceptance criteria

- [ ] Resolve partial months, effective changes, advances/offsets, retroactive corrections, rounding and earned versus posting period with examples.
- [ ] Define worked-hours eligibility and effective department attribution, distinguishing actual attendance from Cashier Shift duration.
- [ ] Keep salary payment separate from expense recognition and original posting/recording/sealed reports unchanged; record explicit approval.

### Blocked by

None (can start immediately).

## 14. Show monthly earned payroll alongside posting and payment views

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

October earned salary appears in October while November payment remains in November money flow under the approved allocation policy.

### Acceptance criteria

- [ ] Implement approved earned-period rules with salary accrued/paid/unpaid and advances clearly distinguished.
- [ ] Retain posting and immutable recording evidence and payment-source links; never recognize salary expense twice.
- [ ] Explain unsupported historical allocation and reconcile UI/export values without rewriting closed reports.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

Proposal ticket 4, Proposal ticket 13

## 15. Decide preparation and delivery measurement definitions

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-human`

### What to build

A reviewed measurement contract defines observed milestones, repeated transitions, late thresholds, delivery final outcomes and aging clocks.

### Acceptance criteria

- [ ] Specify preparation/ready endpoints, repeated-transition handling, eligible samples and percentile conventions.
- [ ] Specify area/rider delivery endpoints, late SLA, final-failure evidence and unsettled-aging origin; returned attempt alone is not final failure.
- [ ] Document coverage and examples for missing/out-of-order events; explicitly approve business thresholds rather than inferring them.

### Blocked by

None (can start immediately).

## 16. Report observed preparation and ready times

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers see preparation/ready durations, median/p90 and late counts from recorded lifecycle events.

### Acceptance criteria

- [ ] Apply approved milestone/repetition rules and show sample/population coverage in rows, charts and exports.
- [ ] Keep missing old milestones unavailable and preparation separate from delivery travel.
- [ ] Replace blanket claims that lifecycle events are absent while preserving real historical limits.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

Proposal ticket 15

## 17. Show current Hold age and Cashier ownership

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers can inspect persisted active Holds, their age and Cashier, with an explicit configurable stale threshold.

### Acceptance criteria

- [ ] Read current stored Holds and display creation/age consistently in Pakistan time, with safe source/export details.
- [ ] Label the stale threshold and avoid claiming deleted Hold history exists.
- [ ] Keep Holds outside confirmed Order counts, Tokens and revenue; replace stale memory-only explanations.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 18. Retain and report Hold lifecycle history

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Recall, replacement, discard and conversion become durable observed Hold events that Managers can report over time.

### Acceptance criteria

- [ ] Persist lifecycle events atomically at authorized Hold operations with stable Hold/source links and actors.
- [ ] Show historical lifecycle counts/ages only from observed events, with pre-feature coverage caveats.
- [ ] Conversion links to its eventual Order without counting the Hold as another Order or allocating extra Tokens.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

Proposal ticket 17

## 19. Report recorded delivery reasons and reattempts

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers inspect safely projected recorded delivery reasons and distinguish attempts from unique Orders and reattempts.

### Acceptance criteria

- [ ] Load stored reason evidence with safe redaction and link attempts to Orders, riders and Delivery Areas.
- [ ] Show reason/attempt breakdowns without interpreting returned attempts as final failures or delivery as collection.
- [ ] Ensure contributor rows and exports reconcile and disclose absent historical reason evidence.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 20. Report delivery timing, final outcomes and unsettled aging

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers compare valid area/rider timing, late delivery and unsettled aging under approved measurement rules.

### Acceptance criteria

- [ ] Use approved endpoints, SLA, final-outcome evidence and aging clocks with sample coverage.
- [ ] Separate unique final-failed Orders from attempts/returns and travel from preparation.
- [ ] Show missing events as unavailable across metrics, contributors and exports.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

Proposal ticket 15, Proposal ticket 19

## 21. Separate verified rider-held cash from customer debt

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Cashiers retain independent customer collection evidence and Managers reconcile verified rider-held cash to actual handovers.

### Acceptance criteria

- [ ] Capture authorized confirmed collection with actual/recording time and stable Order/rider links; retain collection-before-handover separation.
- [ ] Reconcile independently confirmed collection, accepted handover and recorded authorized shortage/write-off evidence; do not invent write-off authority or new settlement privileges.
- [ ] Display Collection Due, rider-held cash and accepted drawer cash separately with coverage, source links and matching exports; keep settled-trip locks intact.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

Proposal ticket 3

## 22. Classify first-time and returning customers across available history

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers see first-time versus returning customers based on the first eligible purchase in available history.

### Acceptance criteria

- [ ] Look beyond the selected cohort to first eligible purchase and preserve selected-range repeat rate as a distinct measure.
- [ ] Disclose earlier-history and guest/phone-identity limits; preserve masking and contact-information authorization.
- [ ] Verify repeat customers outside the selected range and unavailable identity/history in report rows and exports.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 23. Expose stored configuration and operations audit safely

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers inspect recorded management/configuration actions with actor, action, time and safely redacted source changes.

### Acceptance criteria

- [ ] Project existing evidence rather than claiming all security/configuration history is absent.
- [ ] Allowlist safe change fields; never expose raw configuration JSON, credentials, PIN hashes or sensitive customer information.
- [ ] Preserve Manager authorization, source provenance and safe export parity, with missing authentication history disclosed.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 24. Decide security-event access and retention policy

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-human`

### What to build

An approved policy defines which authentication/PIN events are retained, for how long and who may inspect them.

### Acceptance criteria

- [ ] Define failed-login, PIN-reset and other required security event fields, retention/deletion and Manager access.
- [ ] Exclude credentials, PIN hashes and unnecessary personal data; decide safe failure/reason categories.
- [ ] Provide approved examples and retention boundaries before collection/reporting is extended.

### Blocked by

None (can start immediately).

## 25. Capture and report missing authentication and PIN events

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

New required authentication/PIN events appear in the authorized audit view under the approved access/retention policy.

### Acceptance criteria

- [ ] Persist safe event evidence without changing login throttles, PIN authorization or exposing secrets.
- [ ] Apply approved retention and show newly observed coverage rather than fabricating older history.
- [ ] Verify access, redaction and export behavior for successful/failed and reset scenarios.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

Proposal ticket 23, Proposal ticket 24

## 26. Persist verified backup attempts and health history

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers see last verified backup success age, primary/secondary results and failed attempts from durable evidence.

### Acceptance criteria

- [ ] Persist attempt time, initiator, target-specific outcome, verification status and safe failure category.
- [ ] Distinguish configured or scheduled-but-never-run work from verified success; preserve failed attempts and secondary warnings.
- [ ] Show authorized health/source details and exports without inferring old history from paths or archives.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 27. Reconcile supplier payables and aging at a historical cutoff

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers see an as-of opening-to-closing Vendor Khata bridge and nonoverlapping payable aging buckets.

### Acceptance criteria

- [ ] Retain allocation/reversal and opening-adjustment history needed for future cutoffs; do not reconstruct unversioned prior edits as fact.
- [ ] Reconcile opening plus purchases/adjustments minus payments/credits to closing using only evidence available at the disclosed cutoff.
- [ ] Partition known-due outstanding into current/not-yet-due, 0–7, 8–30, 31–60 and over-60 overdue days; separate unknown due dates.
- [ ] UI/export disclose coverage and supplier archiving; do not use current/all-time allocations as historical balances.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 28. Decide line-level sales and cost allocation policy

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-human`

### What to build

An approved allocation policy explains Menu Item/Deal discounts, tax, fees, modifiers, ingredient costs and rounding.

### Acceptance criteria

- [ ] Specify allocation units, rounding residuals, Deal expansion and revision/return behavior with worked reconciled examples.
- [ ] Reconcile line allocations to Order/global sales and cost totals without claiming existing global COGS is absent.
- [ ] Define legacy missing-allocation coverage and record explicit policy approval before implementing margins.

### Blocked by

None (can start immediately).

## 29. Report allocated Menu Item and Deal net sales and margins

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers see defensible line/Deal/modifier net sales and margins under the approved allocation policy.

### Acceptance criteria

- [ ] Persist required allocations at authorized sale/revision/return operations and apply the approved rounding policy.
- [ ] Reconcile line costs/values to Order/global totals and expose safe contributors in reports/exports.
- [ ] Keep legacy unallocated history explicit instead of silently estimating old item profits.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

Proposal ticket 28

## 30. Reconcile ingredient opening-to-ending quantities

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers inspect normalized-unit stock bridges from opening through receipts, consumption, waste, returns and adjustments to ending quantity.

### Acceptance criteria

- [ ] Classify retained movement causes, BOM and posted physical-count evidence without double counting.
- [ ] Reconcile known opening/ending balances and disclose missing openings or gaps.
- [ ] Expose ingredient contributors and export parity; describe recorded cost history separately from stock valuation.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 31. Decide historical inventory valuation policy

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-human`

### What to build

A reviewed policy chooses historical stock valuation and defines its evidence/coverage boundaries.

### Acceptance criteria

- [ ] Resolve method, normalized units, returns/adjustments, negative stock and rounding with worked examples.
- [ ] Distinguish acquisition-rate sales COGS from inventory valuation and preserve existing cost events.
- [ ] Approve the method and legacy coverage limits explicitly before reporting stock values.

### Blocked by

None (can start immediately).

## 32. Value reconciled historical inventory under the approved policy

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers see historical inventory values that reconcile to the quantity bridge under the approved valuation method.

### Acceptance criteria

- [ ] Persist required valuation evidence and apply approved return/adjustment/negative-stock rules.
- [ ] Show method, cutoff, unavailable/estimated coverage and contributing values in UI/exports.
- [ ] Reconcile bridge totals and preserve existing acquisition-rate sales COGS without relabeling it.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

Proposal ticket 30, Proposal ticket 31

## 33. Compare normalized acquisition prices and purchase frequency

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers compare ingredient/base-unit acquisition trends and unified supplier purchases.

### Acceptance criteria

- [ ] Normalize recorded quantities/prices and use stable procurement/Vendor Khata links to count a purchase once.
- [ ] Show supplier breakdowns, price series and purchase frequency with exact scope and matching exports.
- [ ] Identify unlinked purchases and unavailable units/history rather than guessing matches.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 34. Capture promised and actual supplier receipt evidence

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Authorized procurement users retain promised/actual receipt evidence and Managers see evidence-backed supplier punctuality.

### Acceptance criteria

- [ ] Preserve promised time, actual receipt time and recording time with acquisition/supplier links; retain changes rather than overwriting earlier promises silently.
- [ ] Compare actual receipt with the recorded commitment and disclose unknown promises/receipts instead of classifying them as failed deliveries.
- [ ] Show valid-sample coverage and safe contributors in report/export output without inventing unapproved SLA or supplier scores.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 35. Separate food and packaging COGS using event-time classification

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers see food versus packaging costs by Order and Dining Type, reconciled to existing combined COGS.

### Acceptance criteria

- [ ] Snapshot ingredient food/packaging classification when future cost events occur and preserve it through revisions/returns.
- [ ] Keep legacy unclassified costs explicit and do not rewrite history after category/name changes.
- [ ] Reconcile subtotals and contributors to combined COGS across UI/charts/exports.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 36. Capture worked hours and report labor productivity

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers record policy-backed worked-hours evidence and see eligible Orders per labor hour with department/coverage context.

### Acceptance criteria

- [ ] Retain effective staff/department and worked-hours evidence under approved definitions; Cashier Shift duration is not attendance.
- [ ] Use eligible denominators and distinguish absent/zero hours; expose coverage before productivity or allocation totals.
- [ ] Apply only approved department/labor allocation rules and avoid salary-payment expense duplication in reports/exports.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

Proposal ticket 13

## 37. Filter Order, menu, delivery and customer reports by their domains

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers narrow relevant reports by Menu Item/category/Deal/discount, Delivery Area/rider and customer segment.

### Acceptance criteria

- [ ] Use stable IDs and readable names with clear/reset; define segment membership from supported evidence and disclose unavailable lifetime classifications until supported.
- [ ] Apply identical predicates to metrics, charts, contributors and exports, including historical-dimension coverage.
- [ ] Label unrelated report domains outside scope; do not silently filter physical drawer balances through an Order dimension.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 38. Filter supplier, expense and staff reports by their domains

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers select suppliers, expense categories and departments in their applicable financial/staff reports.

### Acceptance criteria

- [ ] Add stable-ID controls, clear/reset and readable names without implying unsupported historical department/category snapshots.
- [ ] Match applicable totals/contributors/export filters and explicitly label outside-scope current-state balances.
- [ ] Retain current authorization and disclose missing historical dimensions.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 39. Filter inventory and procurement reports by stock dimensions

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers select applicable stock categories, ingredients and supplier acquisition dimensions in inventory/procurement reporting.

### Acceptance criteria

- [ ] Use meaningful stable-ID controls with clear/reset and explain unsupported historical categories.
- [ ] Ensure report totals, chart buckets, contributors and exported scope use the same predicates.
- [ ] Keep unrelated domains explicitly outside scope and retain current report behaviors when no filter is chosen.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 40. Save private/shared Manager report presets and operational shortcuts

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers save/reopen/edit/delete named report configurations across restarts and use true Month to date and documented shortcuts.

### Acceptance criteria

- [ ] Persist report/family and supported filters; distinguish dynamic relative dates from fixed date windows.
- [ ] Implement private ownership and Manager-shared access without a separate Owner tier.
- [ ] Revalidate access and unsupported/deleted filters on reopen; show the resolved range and preserve safe metadata on subsequent exports.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 41. Choose preceding-period or comparable-weekday report comparisons

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers select meaningful comparisons for supported activity/flow measures with explicit windows and coverage.

### Acceptance criteria

- [ ] Show exact current/prior windows, values, absolute change, denominator and coverage for each supported measure.
- [ ] Keep zero-baseline percentages unavailable and withhold incomplete/live comparisons without equivalent elapsed evidence.
- [ ] Do not compare current balances as historical snapshots; mark unsupported families clearly and export comparator provenance.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

Proposal ticket 6

## 42. Open KPI contributors and authorized underlying records

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Selecting a supported KPI opens its exact contributing snapshot rows and read-only Order, stock, Vendor Khata, payroll or expense source.

### Acceptance criteria

- [ ] Reconcile contributor values to the metric formula, including signed components and aggregate metrics.
- [ ] Preserve original query/snapshot/cutoff provenance when inspecting a source; label subsequent source changes rather than recomputing the displayed snapshot.
- [ ] Revalidate Manager access, preserve masking and handle missing/archived legacy sources safely; reuse existing source/chart inspection.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 43. Print the selected report through the Windows print dialog

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers explicitly print the displayed immutable report snapshot while retaining Save PDF.

### Acceptance criteria

- [ ] Open the standard Windows dialog only on explicit action and include period, filter and quality metadata.
- [ ] Cancellation prints nothing and authorization expiry fails safely; no customer Receipt hardware-printing flow is added.
- [ ] Verify report contents through existing snapshot/export checks and use remote Windows CI plus documented native-dialog manual acceptance where needed.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).

## 44. Cancel large exports with progress and durable completed outputs

### Parent

[Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60)

**Proposed label:** `ready-for-agent`

### What to build

Managers see stage/row progress and can cancel export generation or writing without losing the last completed output or blocking the application.

### Acceptance criteria

- [ ] Provide cancellation during generation and writing, partial-file cleanup and a durable completed destination.
- [ ] Keep source snapshot, privacy and CSV/XLSX/PDF formula protections unchanged; handle authorization/session expiry during export.
- [ ] Exercise representative large exports in remote CI and measure UI/Cashier responsiveness; move serialization off the UI isolate where necessary.
- [ ] Verify through the confirmed real-SQLite/domain-command to analytics-snapshot seam; add relevant UI/export checks and run all framework validation only in GitHub Actions. Consult Context7 before implementation/refactoring and preserve the parent specification invariants.

### Blocked by

None (can start immediately).
