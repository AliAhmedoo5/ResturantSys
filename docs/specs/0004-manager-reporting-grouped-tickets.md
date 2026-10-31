# Approved grouped tickets for specification #60

38 tickets cover all 44 original proposal slices. Numbers below are local plan IDs until the publication manifest records GitHub issue numbers. The user authorized grouping and publishing all tickets on 29 October 2026.

Priority remains actual Shift money flow and peak analytics first. Dependencies are prerequisites, not artificial phase barriers. Human policy tickets remain separate gates.

## 1. Show auditable reporting identities, historical names, times and provenance

**Original slices:** 1, 10. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** None.

### Show auditable identities, Pakistan time and snapshot provenance

Report rows and CSV/XLSX/PDF distinguish Shift-owner Cashier from recording/approval actors, display known timestamps in Asia/Karachi and retain the source schema version.

- [ ] Display Business Day and Shift start/end where known; distinguish event and recording timestamps without fabricating missing fields.
- [ ] Preserve original UTC/offset evidence and disclose naive legacy assumptions, including local-midnight examples.
- [ ] Capture schema/report version at snapshot load; show/export scope, cutoff and quality consistently, with Manager authorization preserved.

### Preserve transaction-time staff, supplier and category names

New relevant records retain historical names while reports distinguish transaction-time and current identities.

- [ ] Keep stable IDs and existing snapshots; add missing event-time snapshots at relevant writes without rewriting old history.
- [ ] Display/export current names only as separately labeled context and mark unavailable old names.
- [ ] Verify rename/archive scenarios across representative staff, supplier and category records with existing authorization unchanged.

## 2. Record independent checkout receipts and refund events

**Original slices:** 2. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** None.

### Record independent checkout receipts and refund events

Cashiers record cash/digital receipts and refunds with their actual time, immutable recording time and receiving Shift independently of the originating Order.

- [ ] Persist stable event/order/tender/movement links, signed Integer Paisa, Payment Source, receiving Business Day/Shift and actors atomically with the authorized operation; retain change and rounding evidence.
- [ ] Default prompt entries to entry time; support explicit late actual time only within authorized open-period operations; do not create a closed-day correction workflow.
- [ ] Expose events and originating/receiving relationships in Manager source rows and exports, including cross-Shift collections; prevent retry duplicates and partial writes.
- [ ] Migration preserves legacy balances and sealed reports; unknown historical timing/attribution remains disclosed rather than backfilled.

## 3. Trace COD settlement to the actual receiving Shift

**Original slices:** 3. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** 2.

### Trace COD settlement to the actual receiving Shift

Managers can trace a rider handover or confirmed digital settlement to its actual receiving Shift without moving the original Order or counting both tender and Cash Movement.

- [ ] Use stable settlement/event/movement links and actual handover time; preserve existing settlement locks and Cashier-only tender authority.
- [ ] Display order origin, receiving Shift and recorded-by separately; direct digital settlement adds no drawer cash.
- [ ] Show unavailable customer-to-rider collection evidence honestly; delivered status and expected pouch amounts remain insufficient proof of collection.

## 4. Report finance payments by actual time and Payment Source

**Original slices:** 4. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** None.

### Report finance payments by actual time and Payment Source

Expense, supplier and payroll/advance payments appear in a dated finance timeline with drawer, bank/digital and owner streams separated.

- [ ] Retain actual and recording time plus stable links to existing finance records and physical Cash Movements, adding evidence atomically where absent.
- [ ] Show Manager recorder separately from Shift owner; non-drawer payments legitimately have no physical Shift and never alter drawer cash.
- [ ] Exclude accruals and unpaid credit purchases from flow, classify internal transfers separately and prevent linked finance/movement double counting.
- [ ] Prompt and authorized open-period late entries are supported; unknown historical times stay unknown and closed-period corrections are excluded.

## 5. Reconcile one selected Cashier Shift end to end

**Original slices:** 5. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** 2, 3, 4.

### Reconcile one selected Cashier Shift end to end

Selecting a Cashier/Shift produces one reconciled physical cash bridge with matching source rows and exports.

- [ ] Reconcile Opening Float, customer receipts, rider handovers, pay-ins, refunds, expenses, supplier payments, payroll/advances and cash drops exactly once.
- [ ] Show expected cash, Blind Count and signed counted-minus-expected Discrepancy; an uncounted Shift has unavailable variance.
- [ ] Use receiving/owning Shift scope, retain cross-cohort collections and keep recorded-by distinct; label order-only breakdowns without narrowing whole-drawer accountability.
- [ ] Show legacy gaps and withheld complete totals where authoritative reconciliation is impossible; do not deduplicate by amount/time similarity.

## 6. Select Business Day or calendar-time order activity

**Original slices:** 6. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** None.

### Select Business Day or calendar-time order activity

Managers switch Order activity between assigned Business Days and actual Asia/Karachi calendar date/time, with matching ranges and exports.

- [ ] Default to Business Day; use inclusive-start/exclusive-end boundaries and preserve distinct Business Day IDs even on one opening date.
- [ ] Show both order timestamp and assigned Business Day; an overnight Order changes calendar bucket without changing its assignment.
- [ ] Persist time basis/grouping in the query and immutable snapshot; explain calendar versus operational weekday, Monday-start weeks and local months.

## 7. Rank busiest Order days and hours separately from sales value

**Original slices:** 7. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** 6.

### Rank busiest Order days and hours separately from sales value

Managers see distinct daily/hourly workload and value rankings, with cancellations, refunds and average ticket explained separately.

- [ ] Count every confirmed Order once including later cancellations/refunds; Holds and Order Revisions create no extra Orders.
- [ ] Retain valid-sales definitions and label value/average-ticket eligibility; use corresponding eligible count rather than workload count indiscriminately.
- [ ] Include all tied peaks, sort ties chronologically and show 24 observed hourly buckets; distinguish true zero from missing coverage.
- [ ] Chart, contributors and exports reconcile for both time bases; preserve distinct Business Days.

## 8. Compare weekdays fairly and explore recurring Order peaks

**Original slices:** 8. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** 7.

### Compare weekdays fairly and explore recurring Order peaks

Managers see weekday totals, completed-Business-Day averages, weekday-by-hour activity and weekly/monthly trends.

- [ ] Primary weekday ranking displays completed-day numerator/denominator, includes opened zero-order days, separates open days and returns unavailable for zero denominator.
- [ ] Label operational weekday versus actual calendar weekday, including post-midnight hours; do not invent unopened Business Days.
- [ ] Render a weekday/hour table or heatmap and Monday-start weekly/local-month trends with identical export buckets and coverage.

## 9. Explore actual-time inflow, outflow and net-flow peaks

**Original slices:** 9. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** 5, 6.

### Explore actual-time inflow, outflow and net-flow peaks

Managers rank money-flow periods by actual time and funding stream, independently of Order workload or sales value.

- [ ] Apply the explicit time-basis query to canonical finance and receipt evidence, including receiving events whose Orders are outside the selected cohort.
- [ ] Show nonnegative inflow/outflow magnitudes and signed net; rank highest inflow/outflow and greatest/least net with all ties.
- [ ] Separate drawer, bank/digital and owner streams, disclose internal transfers and exclude accruals, unpaid purchases and duplicate custody legs from consolidated receipts.
- [ ] Unknown event time/receiving attribution is excluded from unsupported buckets with coverage; retain a clearly labeled legacy order-cohort view.

## 10. Decide closed-day correction authority and reconciliation policy

**Original slices:** 11. **Label:** `ready-for-human`.

**Blocked by plan tickets:** None.

### Decide closed-day correction authority and reconciliation policy

A reviewed policy resolves who may append historical corrections and how they reconcile while preserving the two-role boundary.

- [ ] Decide approval authority, append-only evidence, source links, reversals, reconciliation and correction cutoff semantics, with worked late-payment examples.
- [ ] Keep sealed reports/hashes immutable and forbid a new current-day drawer movement for cash already moved historically.
- [ ] Resolve how to record historical evidence without giving Managers live tender/Shift authority; record explicit approval before enabling implementation.

## 11. Append approved historical corrections and show adjusted reports

**Original slices:** 12. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** 5, 10.

### Append approved historical corrections and show adjusted reports

Authorized users can append policy-backed historical corrections and Managers can compare original and correction-adjusted results.

- [ ] Implement the approved authority/reversal rules and link actual time, recording time, affected Business Day and original evidence.
- [ ] Display adjustment bridge and cutoff separately from immutable original X/Z reports; export both bases clearly.
- [ ] Reject duplicate or unreconciled physical effects; prove original balances, sealed content/hashes and recording timestamps are unchanged.

## 12. Decide earned-period payroll and labor allocation rules

**Original slices:** 13. **Label:** `ready-for-human`.

**Blocked by plan tickets:** None.

### Decide earned-period payroll and labor allocation rules

A reviewed policy defines monthly earned payroll and the attendance/department allocation inputs needed for reliable labor reporting.

- [ ] Resolve partial months, effective changes, advances/offsets, retroactive corrections, rounding and earned versus posting period with examples.
- [ ] Define worked-hours eligibility and effective department attribution, distinguishing actual attendance from Cashier Shift duration.
- [ ] Keep salary payment separate from expense recognition and original posting/recording/sealed reports unchanged; record explicit approval.

## 13. Show monthly earned payroll alongside posting and payment views

**Original slices:** 14. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** 4, 12.

### Show monthly earned payroll alongside posting and payment views

October earned salary appears in October while November payment remains in November money flow under the approved allocation policy.

- [ ] Implement approved earned-period rules with salary accrued/paid/unpaid and advances clearly distinguished.
- [ ] Retain posting and immutable recording evidence and payment-source links; never recognize salary expense twice.
- [ ] Explain unsupported historical allocation and reconcile UI/export values without rewriting closed reports.

## 14. Decide preparation and delivery measurement definitions

**Original slices:** 15. **Label:** `ready-for-human`.

**Blocked by plan tickets:** None.

### Decide preparation and delivery measurement definitions

A reviewed measurement contract defines observed milestones, repeated transitions, late thresholds, delivery final outcomes and aging clocks.

- [ ] Specify preparation/ready endpoints, repeated-transition handling, eligible samples and percentile conventions.
- [ ] Specify area/rider delivery endpoints, late SLA, final-failure evidence and unsettled-aging origin; returned attempt alone is not final failure.
- [ ] Document coverage and examples for missing/out-of-order events; explicitly approve business thresholds rather than inferring them.

## 15. Report observed preparation and ready times

**Original slices:** 16. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** 14.

### Report observed preparation and ready times

Managers see preparation/ready durations, median/p90 and late counts from recorded lifecycle events.

- [ ] Apply approved milestone/repetition rules and show sample/population coverage in rows, charts and exports.
- [ ] Keep missing old milestones unavailable and preparation separate from delivery travel.
- [ ] Replace blanket claims that lifecycle events are absent while preserving real historical limits.

## 16. Show current Hold age and Cashier ownership

**Original slices:** 17. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** None.

### Show current Hold age and Cashier ownership

Managers can inspect persisted active Holds, their age and Cashier, with an explicit configurable stale threshold.

- [ ] Read current stored Holds and display creation/age consistently in Pakistan time, with safe source/export details.
- [ ] Label the stale threshold and avoid claiming deleted Hold history exists.
- [ ] Keep Holds outside confirmed Order counts, Tokens and revenue; replace stale memory-only explanations.

## 17. Retain and report Hold lifecycle history

**Original slices:** 18. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** 16.

### Retain and report Hold lifecycle history

Recall, replacement, discard and conversion become durable observed Hold events that Managers can report over time.

- [ ] Persist lifecycle events atomically at authorized Hold operations with stable Hold/source links and actors.
- [ ] Show historical lifecycle counts/ages only from observed events, with pre-feature coverage caveats.
- [ ] Conversion links to its eventual Order without counting the Hold as another Order or allocating extra Tokens.

## 18. Report recorded delivery reasons and reattempts

**Original slices:** 19. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** None.

### Report recorded delivery reasons and reattempts

Managers inspect safely projected recorded delivery reasons and distinguish attempts from unique Orders and reattempts.

- [ ] Load stored reason evidence with safe redaction and link attempts to Orders, riders and Delivery Areas.
- [ ] Show reason/attempt breakdowns without interpreting returned attempts as final failures or delivery as collection.
- [ ] Ensure contributor rows and exports reconcile and disclose absent historical reason evidence.

## 19. Report delivery timing, final outcomes and unsettled aging

**Original slices:** 20. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** 14, 18.

### Report delivery timing, final outcomes and unsettled aging

Managers compare valid area/rider timing, late delivery and unsettled aging under approved measurement rules.

- [ ] Use approved endpoints, SLA, final-outcome evidence and aging clocks with sample coverage.
- [ ] Separate unique final-failed Orders from attempts/returns and travel from preparation.
- [ ] Show missing events as unavailable across metrics, contributors and exports.

## 20. Separate verified rider-held cash from customer debt

**Original slices:** 21. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** 3.

### Separate verified rider-held cash from customer debt

Cashiers retain independent customer collection evidence and Managers reconcile verified rider-held cash to actual handovers.

- [ ] Capture authorized confirmed collection with actual/recording time and stable Order/rider links; retain collection-before-handover separation.
- [ ] Reconcile independently confirmed collection, accepted handover and recorded authorized shortage/write-off evidence; do not invent write-off authority or new settlement privileges.
- [ ] Display Collection Due, rider-held cash and accepted drawer cash separately with coverage, source links and matching exports; keep settled-trip locks intact.

## 21. Classify first-time and returning customers across available history

**Original slices:** 22. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** None.

### Classify first-time and returning customers across available history

Managers see first-time versus returning customers based on the first eligible purchase in available history.

- [ ] Look beyond the selected cohort to first eligible purchase and preserve selected-range repeat rate as a distinct measure.
- [ ] Disclose earlier-history and guest/phone-identity limits; preserve masking and contact-information authorization.
- [ ] Verify repeat customers outside the selected range and unavailable identity/history in report rows and exports.

## 22. Expose stored configuration and operations audit safely

**Original slices:** 23. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** None.

### Expose stored configuration and operations audit safely

Managers inspect recorded management/configuration actions with actor, action, time and safely redacted source changes.

- [ ] Project existing evidence rather than claiming all security/configuration history is absent.
- [ ] Allowlist safe change fields; never expose raw configuration JSON, credentials, PIN hashes or sensitive customer information.
- [ ] Preserve Manager authorization, source provenance and safe export parity, with missing authentication history disclosed.

## 23. Decide security-event access and retention policy

**Original slices:** 24. **Label:** `ready-for-human`.

**Blocked by plan tickets:** None.

### Decide security-event access and retention policy

An approved policy defines which authentication/PIN events are retained, for how long and who may inspect them.

- [ ] Define failed-login, PIN-reset and other required security event fields, retention/deletion and Manager access.
- [ ] Exclude credentials, PIN hashes and unnecessary personal data; decide safe failure/reason categories.
- [ ] Provide approved examples and retention boundaries before collection/reporting is extended.

## 24. Capture and report missing authentication and PIN events

**Original slices:** 25. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** 22, 23.

### Capture and report missing authentication and PIN events

New required authentication/PIN events appear in the authorized audit view under the approved access/retention policy.

- [ ] Persist safe event evidence without changing login throttles, PIN authorization or exposing secrets.
- [ ] Apply approved retention and show newly observed coverage rather than fabricating older history.
- [ ] Verify access, redaction and export behavior for successful/failed and reset scenarios.

## 25. Persist verified backup attempts and health history

**Original slices:** 26. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** None.

### Persist verified backup attempts and health history

Managers see last verified backup success age, primary/secondary results and failed attempts from durable evidence.

- [ ] Persist attempt time, initiator, target-specific outcome, verification status and safe failure category.
- [ ] Distinguish configured or scheduled-but-never-run work from verified success; preserve failed attempts and secondary warnings.
- [ ] Show authorized health/source details and exports without inferring old history from paths or archives.

## 26. Reconcile supplier payables and aging at a historical cutoff

**Original slices:** 27. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** None.

### Reconcile supplier payables and aging at a historical cutoff

Managers see an as-of opening-to-closing Vendor Khata bridge and nonoverlapping payable aging buckets.

- [ ] Retain allocation/reversal and opening-adjustment history needed for future cutoffs; do not reconstruct unversioned prior edits as fact.
- [ ] Reconcile opening plus purchases/adjustments minus payments/credits to closing using only evidence available at the disclosed cutoff.
- [ ] Partition known-due outstanding into current/not-yet-due, 0–7, 8–30, 31–60 and over-60 overdue days; separate unknown due dates.
- [ ] UI/export disclose coverage and supplier archiving; do not use current/all-time allocations as historical balances.

## 27. Decide line-level sales and cost allocation policy

**Original slices:** 28. **Label:** `ready-for-human`.

**Blocked by plan tickets:** None.

### Decide line-level sales and cost allocation policy

An approved allocation policy explains Menu Item/Deal discounts, tax, fees, modifiers, ingredient costs and rounding.

- [ ] Specify allocation units, rounding residuals, Deal expansion and revision/return behavior with worked reconciled examples.
- [ ] Reconcile line allocations to Order/global sales and cost totals without claiming existing global COGS is absent.
- [ ] Define legacy missing-allocation coverage and record explicit policy approval before implementing margins.

## 28. Report allocated Menu Item and Deal net sales and margins

**Original slices:** 29. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** 27.

### Report allocated Menu Item and Deal net sales and margins

Managers see defensible line/Deal/modifier net sales and margins under the approved allocation policy.

- [ ] Persist required allocations at authorized sale/revision/return operations and apply the approved rounding policy.
- [ ] Reconcile line costs/values to Order/global totals and expose safe contributors in reports/exports.
- [ ] Keep legacy unallocated history explicit instead of silently estimating old item profits.

## 29. Reconcile ingredient opening-to-ending quantities

**Original slices:** 30. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** None.

### Reconcile ingredient opening-to-ending quantities

Managers inspect normalized-unit stock bridges from opening through receipts, consumption, waste, returns and adjustments to ending quantity.

- [ ] Classify retained movement causes, BOM and posted physical-count evidence without double counting.
- [ ] Reconcile known opening/ending balances and disclose missing openings or gaps.
- [ ] Expose ingredient contributors and export parity; describe recorded cost history separately from stock valuation.

## 30. Decide historical inventory valuation policy

**Original slices:** 31. **Label:** `ready-for-human`.

**Blocked by plan tickets:** None.

### Decide historical inventory valuation policy

A reviewed policy chooses historical stock valuation and defines its evidence/coverage boundaries.

- [ ] Resolve method, normalized units, returns/adjustments, negative stock and rounding with worked examples.
- [ ] Distinguish acquisition-rate sales COGS from inventory valuation and preserve existing cost events.
- [ ] Approve the method and legacy coverage limits explicitly before reporting stock values.

## 31. Value reconciled historical inventory under the approved policy

**Original slices:** 32. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** 29, 30.

### Value reconciled historical inventory under the approved policy

Managers see historical inventory values that reconcile to the quantity bridge under the approved valuation method.

- [ ] Persist required valuation evidence and apply approved return/adjustment/negative-stock rules.
- [ ] Show method, cutoff, unavailable/estimated coverage and contributing values in UI/exports.
- [ ] Reconcile bridge totals and preserve existing acquisition-rate sales COGS without relabeling it.

## 32. Report supplier acquisition prices, frequency and receipt punctuality

**Original slices:** 33, 34. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** None.

### Compare normalized acquisition prices and purchase frequency

Managers compare ingredient/base-unit acquisition trends and unified supplier purchases.

- [ ] Normalize recorded quantities/prices and use stable procurement/Vendor Khata links to count a purchase once.
- [ ] Show supplier breakdowns, price series and purchase frequency with exact scope and matching exports.
- [ ] Identify unlinked purchases and unavailable units/history rather than guessing matches.

### Capture promised and actual supplier receipt evidence

Authorized procurement users retain promised/actual receipt evidence and Managers see evidence-backed supplier punctuality.

- [ ] Preserve promised time, actual receipt time and recording time with acquisition/supplier links; retain changes rather than overwriting earlier promises silently.
- [ ] Compare actual receipt with the recorded commitment and disclose unknown promises/receipts instead of classifying them as failed deliveries.
- [ ] Show valid-sample coverage and safe contributors in report/export output without inventing unapproved SLA or supplier scores.

## 33. Separate food and packaging COGS using event-time classification

**Original slices:** 35. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** None.

### Separate food and packaging COGS using event-time classification

Managers see food versus packaging costs by Order and Dining Type, reconciled to existing combined COGS.

- [ ] Snapshot ingredient food/packaging classification when future cost events occur and preserve it through revisions/returns.
- [ ] Keep legacy unclassified costs explicit and do not rewrite history after category/name changes.
- [ ] Reconcile subtotals and contributors to combined COGS across UI/charts/exports.

## 34. Capture worked hours and report labor productivity

**Original slices:** 36. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** 12.

### Capture worked hours and report labor productivity

Managers record policy-backed worked-hours evidence and see eligible Orders per labor hour with department/coverage context.

- [ ] Retain effective staff/department and worked-hours evidence under approved definitions; Cashier Shift duration is not attendance.
- [ ] Use eligible denominators and distinguish absent/zero hours; expose coverage before productivity or allocation totals.
- [ ] Apply only approved department/labor allocation rules and avoid salary-payment expense duplication in reports/exports.

## 35. Apply domain filters consistently across Manager reports and exports

**Original slices:** 37, 38, 39. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** None.

### Filter Order, menu, delivery and customer reports by their domains

Managers narrow relevant reports by Menu Item/category/Deal/discount, Delivery Area/rider and customer segment.

- [ ] Use stable IDs and readable names with clear/reset; define segment membership from supported evidence and disclose unavailable lifetime classifications until supported.
- [ ] Apply identical predicates to metrics, charts, contributors and exports, including historical-dimension coverage.
- [ ] Label unrelated report domains outside scope; do not silently filter physical drawer balances through an Order dimension.

### Filter supplier, expense and staff reports by their domains

Managers select suppliers, expense categories and departments in their applicable financial/staff reports.

- [ ] Add stable-ID controls, clear/reset and readable names without implying unsupported historical department/category snapshots.
- [ ] Match applicable totals/contributors/export filters and explicitly label outside-scope current-state balances.
- [ ] Retain current authorization and disclose missing historical dimensions.

### Filter inventory and procurement reports by stock dimensions

Managers select applicable stock categories, ingredients and supplier acquisition dimensions in inventory/procurement reporting.

- [ ] Use meaningful stable-ID controls with clear/reset and explain unsupported historical categories.
- [ ] Ensure report totals, chart buckets, contributors and exported scope use the same predicates.
- [ ] Keep unrelated domains explicitly outside scope and retain current report behaviors when no filter is chosen.

## 36. Save Manager report workflows and inspect their KPI contributors

**Original slices:** 40, 42. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** None.

### Save private/shared Manager report presets and operational shortcuts

Managers save/reopen/edit/delete named report configurations across restarts and use true Month to date and documented shortcuts.

- [ ] Persist report/family and supported filters; distinguish dynamic relative dates from fixed date windows.
- [ ] Implement private ownership and Manager-shared access without a separate Owner tier.
- [ ] Revalidate access and unsupported/deleted filters on reopen; show the resolved range and preserve safe metadata on subsequent exports.

### Open KPI contributors and authorized underlying records

Selecting a supported KPI opens its exact contributing snapshot rows and read-only Order, stock, Vendor Khata, payroll or expense source.

- [ ] Reconcile contributor values to the metric formula, including signed components and aggregate metrics.
- [ ] Preserve original query/snapshot/cutoff provenance when inspecting a source; label subsequent source changes rather than recomputing the displayed snapshot.
- [ ] Revalidate Manager access, preserve masking and handle missing/archived legacy sources safely; reuse existing source/chart inspection.

## 37. Choose preceding-period or comparable-weekday report comparisons

**Original slices:** 41. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** 6.

### Choose preceding-period or comparable-weekday report comparisons

Managers select meaningful comparisons for supported activity/flow measures with explicit windows and coverage.

- [ ] Show exact current/prior windows, values, absolute change, denominator and coverage for each supported measure.
- [ ] Keep zero-baseline percentages unavailable and withhold incomplete/live comparisons without equivalent elapsed evidence.
- [ ] Do not compare current balances as historical snapshots; mark unsupported families clearly and export comparator provenance.

## 38. Print reports and control large exports with progress and cancellation

**Original slices:** 43, 44. **Label:** `ready-for-agent`.

**Blocked by plan tickets:** None.

### Print the selected report through the Windows print dialog

Managers explicitly print the displayed immutable report snapshot while retaining Save PDF.

- [ ] Open the standard Windows dialog only on explicit action and include period, filter and quality metadata.
- [ ] Cancellation prints nothing and authorization expiry fails safely; no customer Receipt hardware-printing flow is added.
- [ ] Verify report contents through existing snapshot/export checks and use remote Windows CI plus documented native-dialog manual acceptance where needed.

### Cancel large exports with progress and durable completed outputs

Managers see stage/row progress and can cancel export generation or writing without losing the last completed output or blocking the application.

- [ ] Provide cancellation during generation and writing, partial-file cleanup and a durable completed destination.
- [ ] Keep source snapshot, privacy and CSV/XLSX/PDF formula protections unchanged; handle authorization/session expiry during export.
- [ ] Exercise representative large exports in remote CI and measure UI/Cashier responsiveness; move serialization off the UI isolate where necessary.
