# Manager reporting completeness: Shift money flow, time-based analytics and phased reporting gaps

## Problem Statement

Managers cannot reliably answer which Shift handled money, when it actually moved, or which Business Days, calendar dates and hours were busiest. Existing reports mix order cohorts with collection attribution, omit some stored operational evidence, and have genuine historical coverage gaps. Some explanations incorrectly describe implemented finance and costing inputs as absent. Extending charts alone would make incomplete evidence look authoritative.

The 29 October 2026 reporting audit covers all 13 Manager report families. This specification preserves its confirmed decisions and full backlog, with accurate Shift money flow and busiest-period analytics as the first delivery phase. It does not claim access to live restaurant data or completed implementation.

## Solution

Give Managers an auditable reporting workspace in which every supported total, chart, contributing row and export has a consistent scope, time basis and evidence disclosure. Default to Business Day reporting while offering actual calendar date/time in Asia/Karachi. Separate order workload, valid sales, customer collections, physical drawer custody, external funding and noncash accruals.

Deliver in phases: establish attribution and time evidence; add peak views; expose existing operational evidence; extend financial evidence under explicit policies; finish broader report usability. Preserve original closed Business Days and sealed reports throughout. Unavailable history remains unavailable.

## User Stories

1. As a Manager, I want Business Day reporting by default, so that overnight trading stays in its assigned operational period.
2. As a Manager, I want an actual calendar date/time view, so that I can understand activity after midnight separately from its Business Day.
3. As a Manager, I want Pakistan time on every displayed timestamp, so that comparisons use one visible time zone.
4. As a Manager, I want distinct Business Days even when they open on the same date, so that their activity is not silently merged.
5. As a Manager, I want event time and immutable recording time separately, so that late entry does not misrepresent when money moved.
6. As a Cashier, I want new payment events to retain their receiving Shift and Business Day, so that my drawer accountability is accurate.
7. As a Manager, I want originating order Shift and receiving collection Shift separately, so that later collections do not move the original order.
8. As a Manager, I want Shift-owner Cashier, recorded-by and approved-by identities separately, so that staff responsibilities are clear.
9. As a Manager, I want one selected-Shift reconciliation, so that opening float, receipts, payouts and counted cash explain its Discrepancy.
10. As a Manager, I want linked customer receipts, refunds, rider handovers and Cash Movements, so that the same money is not counted twice.
11. As a Manager, I want drawer cash, bank/digital money and owner funds separated, so that external funding does not inflate drawer cash.
12. As a Manager, I want salary accruals and unpaid supplier purchases excluded from money flow, so that obligations are not mistaken for payments.
13. As a Manager, I want all confirmed orders counted once for workload, so that later cancellations and revisions do not erase or multiply activity.
14. As a Manager, I want cancellations, refunds, sales value and collections separately, so that workload is not confused with earnings or cash.
15. As a Manager, I want order-count and value rankings separately, so that I can distinguish the busiest periods from the highest-value periods.
16. As a Manager, I want hourly, daily, weekly and monthly trends, so that I can plan staffing and operations.
17. As a Manager, I want weekday totals and completed-Business-Day averages with denominators, so that unequal weekday counts do not bias rankings.
18. As a Manager, I want current incomplete periods labeled separately, so that partial trading is not compared with completed periods.
19. As a Manager, I want weekday-by-hour activity, so that I can identify recurring busy times.
20. As a Manager, I want inflow, outflow and net-flow rankings by Payment Source, so that I can explain when money enters and leaves each stream.
21. As a Manager, I want unknown historical payment times and missing attribution disclosed, so that legacy order cohorts are not presented as actual collection history.
22. As a Manager, I want original sealed reports preserved alongside any supported correction-adjusted view, so that subsequent evidence does not rewrite a closure.
23. As a Manager, I want October salary attributed to October's earned month and November payment to November's money flow, so that payroll and cash timing remain distinct.
24. As a Manager, I want transaction-time names distinguished from current names, so that renaming staff, suppliers or categories does not rewrite history.
25. As a Manager, I want meaningful domain filters, so that totals, contributors and exports answer the same question.
26. As a Manager, I want private and shared saved report presets and true Month to date, so that recurring reporting survives restarts.
27. As a Manager, I want preceding-period and comparable-weekday comparisons with exact windows, so that changes are interpretable.
28. As a Manager, I want to open a metric's contributing records, so that I can reconcile it to orders, stock, Vendor Khata, payroll or expenses.
29. As a Manager, I want optional Windows report printing alongside Save PDF, so that I can print the selected report when needed.
30. As a Manager, I want progress and cancellation during large exports, so that reporting remains responsive and completed files remain safe.
31. As a Manager, I want as-of supplier payable reconciliation and aging, so that historical obligations can be explained at a disclosed cutoff.
32. As a Manager, I want defensible Menu Item and Deal net sales and margins, so that allocated values reconcile to order and global totals.
33. As a Manager, I want ingredient opening-to-ending quantity reconciliation and disclosed valuation coverage, so that stock movement and value are understandable.
34. As a Manager, I want normalized acquisition prices and purchase frequency by supplier, so that procurement trends are comparable.
35. As a Manager, I want supplier punctuality only where promised and actual delivery evidence exists, so that unknown deliveries are not classified as failures.
36. As a Manager, I want food and packaging COGS separately, so that fulfillment costs can be explained without changing historical classifications.
37. As a Manager, I want labor productivity only where worked-hours evidence exists, so that Cashier Shift length is not mistaken for paid attendance.
38. As a Manager, I want observed preparation and ready durations with sample coverage, so that missing milestones do not become fabricated service times.
39. As a Manager, I want active Hold aging and clearly bounded lifecycle history, so that unconfirmed carts stay outside orders and revenue.
40. As a Manager, I want delivery reasons, reattempts, area/rider timing and aging separately, so that returned attempts are not mistaken for final failed orders.
41. As a Manager, I want verified customer collection and cashier handover evidence separately, so that customer debt, rider-held cash and accepted drawer cash remain distinct.
42. As a Manager, I want first-time versus returning customer classification across available history, so that a single selected-range purchase is not automatically called a new customer.
43. As a Manager, I want redacted configuration, operations and security history, so that I can investigate actions without exposing credentials or sensitive data.
44. As a Manager, I want durable verified backup health history, so that a configured destination is not mistaken for a successful backup.
45. As a Manager, I want schema, formula, filter, time-basis and coverage metadata in every export, so that the saved result can be traced to its source snapshot.

## Implementation Decisions

### Existing architecture and invariants

- Evolve the existing SQLite storage, domain controllers, authorized analytics service, immutable snapshots, report projections and shared export serializer in place. Retain the standalone offline architecture and existing authorization boundaries; no ORM or state-management rewrite.
- Preserve the two interactive roles, Cashier and Manager. Reporting does not authorize Managers to collect customer tenders, perform checkout or operate Cashier Shifts. Owner funds describe a Payment Source, not a third permission tier.
- Keep money in Integer Paisa, preserve Cash Rounding evidence, and reconcile signed amounts without floating-point monetary aggregation. Cash customer receipts use retained tender/change evidence; linked refunds or Cash Movements must not be counted again.
- Preserve original source IDs, relationships, available historical name snapshots and UTC/offset evidence. Current names may be shown separately. Label missing historical names and naive legacy timestamp assumptions rather than backfilling today's facts into the past.
- A snapshot captures its source schema version, formula/report version, query, cutoff, included Business Day IDs and evidence quality. Totals, charts, contributors and exports consume that same snapshot. Authorization is revalidated at existing load/export boundaries.

### Phase 1A: attribution and evidence

- Extend the payment-recording contracts and SQLite schema to retain independent receipt/refund events: stable event identity, original order link, event kind and signed amount, method/Payment Source, actual event time, immutable recording time, receiving Shift/Business Day where applicable, recording actor, optional approval actor and linked tender/movement/settlement identities. Persist the event atomically with the authorized financial operation; use stable links to prevent duplicate posting on retries.
- Immediate entries default actual time to entry time. Late entries retain explicitly supplied actual time without changing recording time. Reject inconsistent attribution rather than guessing a receiving Shift from the order. External bank/owner records may legitimately lack a physical Shift; show that explicitly.
- Preserve originating order Shift/Business Day. A subsequent collection is selected through receiving/event attribution even when its order lies outside the selected order cohort. Show both relationships on contributing rows. Distinguish customer-to-rider collection from rider-to-drawer custody transfer; delivered status is not collection evidence.
- Consolidate authoritative linked evidence for existing settlement, finance and drawer operations. A tender plus a matching Cash Movement represents one financial effect, not two. Unlinked legacy evidence is disclosed; do not deduplicate merely because amounts and times look similar.
- Apply Cashier/Shift filters to the owning/receiving relationships appropriate to the displayed measure. Recorded-by filtering is a separately labeled dimension. Dining Type and other order-only predicates must not silently alter whole-drawer reconciliation. Clearly label narrower activity breakdowns and any outside-scope totals.
- The selected-Shift bridge shows Opening Float + customer cash accepted + rider handovers + other pay-ins - cash refunds - expenses - supplier payments - payroll/advances - cash drops = expected cash. Classify each physical effect once. Show Blind Count when available and signed Discrepancy as counted minus expected; an uncounted open Shift has unavailable Discrepancy, not zero. Opening Float remains a balance component, not sales revenue.
- Every contributing cash row exposes Business Day, Shift, Shift-owner Cashier, event time, recording time, source reference, Payment Source and actors where known. Shift rows include start/end times. Format known times in Asia/Karachi and retain original UTC/offset values in source/export details.
- Include actual cash, bank/digital and owner inflow/outflow in separate streams. Accruals, unpaid credit purchases and transfers between already-counted custody locations must not inflate consolidated customer receipts or business inflow. Preserve transfer legs for reconciliation and identify internal transfers separately.
- Legacy order-cohort reporting remains explicitly labeled. Missing event times do not enter actual-time buckets, and missing receiving attribution does not enter a fabricated Shift. Show included/excluded counts and amounts where determinable; withhold a complete-looking total where missing evidence prevents reconciliation.

### Phase 1B: time selection and peak analytics

- Extend the analytics query and workspace with explicit Business Day versus actual calendar-time basis, grouping and funding-stream selection. Use inclusive-start/exclusive-end ranges. Business Day scope selects assigned IDs; calendar scope selects the relevant order/event timestamps independently of the original order cohort.
- Preserve distinct Business Day IDs even for identical opening dates. Label Business Day weekday by assigned operational date, calendar weekday by actual local date, and hourly buckets by actual Asia/Karachi clock hour. Weekly grouping uses Monday-start local weeks; monthly grouping uses local calendar months. Export these definitions and exact boundaries.
- Workload counts every confirmed Order once by its original creation time, including subsequently cancelled/refunded Orders. Holds are excluded and Order Revisions never create extra Orders. Show cancellation/refund measures separately. Keep existing valid-sales definitions distinct; disclose the value basis for order value and average ticket, using the corresponding eligible count rather than workload count indiscriminately.
- Rank order count and sales value independently. Include all periods tied for a peak; sort tied rows chronologically. Show 24 hourly buckets where the selected evidence supports them. An observed bucket with no activity is zero; absent historical coverage is unavailable. Do not invent zero-activity Business Days that were never opened.
- Primary weekday ranking is confirmed-order total for completed Business Days of that weekday divided by the number of those selected completed Business Days, including opened days with zero Orders. Display numerator, denominator and aggregate total. Keep open Business Days separate. A zero denominator yields unavailable. Calendar weekday totals remain explicitly distinct from this operational average.
- Provide busiest distinct Business Days, calendar dates and hours, weekly/monthly trends and a weekday-by-hour table or heatmap. In Business Day mode a post-midnight hour retains its Business Day weekday; calendar mode uses the actual weekday. Label the basis next to the view.
- Money peaks use actual event time, separate nonnegative inflow/outflow magnitudes and signed net = inflow - outflow. Offer highest inflow, highest outflow and greatest/least net rankings with ties disclosed. Do not substitute order value or recording time for actual money movement.
- Exports of these views must reproduce scope, bucket definitions, ties, missing-evidence disclosures and source relationships. Include schema-version provenance now; broader export UX follows later.

### Historical corrections and earned-period payroll boundaries

- Original closed Business Days, X/Z reports, hashes and original posting/recording dates remain immutable. A later correction must be append-only, link the affected Business Day and original evidence, and distinguish actual event time from recording time. A correction-adjusted analytical view must identify its correction cutoff and reconcile adjustments separately from the original sealed result.
- Do not post a new physical Cash Movement today for cash already moved historically, infer the old receiving Shift, or treat a reporting annotation as a newly collected tender. Correction approval authority, persistence, reversal and reconciliation mechanics were not settled by the audit. Phase 1 must not introduce a correction-write workflow until a separate decision resolves those mechanics within the two-role policy. Show existing evidence and coverage limits meanwhile.
- Preserve monthly earned-period payroll as the confirmed reporting direction: October salary belongs in October's earned view even if posted or paid in November; November payment belongs to November money flow. Keep original posting view and recording time, and never charge salary expense again on payment. Detailed partial-month, department, advance-offset and retroactive allocation formulas require a separate approved policy before extending earned-period calculations.

### Later phases: complete audit coverage

The following requirements remain part of this specification's delivery scope. Policy-dependent work is explicitly gated; a ready label must not be interpreted as choosing an undisclosed financial policy.

| Audit area | Required behavior and delivery gate |
| --- | --- |
| Domain filters | Add applicable product/category/Deal/discount, Delivery Area/rider/customer segment, supplier, stock/expense category and department filters with stable IDs, readable names, clear/reset and matching rows/totals/export metadata. Disclose unavailable historical dimensions. |
| Saved presets | Persist named private and Manager-shared report/family/filter configurations across restarts, with reopen/edit/delete. Provide operational shortcuts and true Month to date. Explicitly distinguish dynamic relative ranges from fixed ranges; validate access and unsupported filters on reopen. |
| Comparisons | Offer equal preceding period and comparable-weekday selection only for supported activity/flow measures. Show exact windows, values, absolute changes, denominators and coverage. Keep zero-baseline percentages unavailable and withhold live/incomplete comparisons without equivalent elapsed evidence. Do not compare current balances as historical snapshots. |
| Contributors | KPI selection opens exactly its contributing snapshot rows and reconciled total, with authorized read-only source navigation for orders, stock, Vendor Khata, payroll and expenses. Preserve query provenance and safe missing-source handling. |
| Report printing | Offer report-only standard Windows print dialog for the immutable selected snapshot, including scope/quality metadata. Cancellation prints nothing; Save PDF remains available. This does not add customer Receipt printing. |
| Export responsiveness | Add stage/row progress and cancellation during generation and writing, partial-file cleanup, authorization-expiry handling and a durable completed path. Retain the last completed output. Move expensive serialization off the UI isolate where required by measurement. |
| F1: supplier payable history | Reconcile as-of opening + purchases/adjustments - payments/credits = closing payable, with allocation/reversal history and a disclosed cutoff. Partition known-due outstanding into current/not-yet-due, 0–7 overdue, 8–30, 31–60 and over-60-day buckets without overlap. Disclose unknown due dates and unversioned opening edits; do not promise complete reconstruction without evidence. |
| F2: Menu Item/Deal margins | Define and persist discount/tax/fee and ingredient-cost allocation to sold lines, Deal components and modifiers; reconcile revisions/returns and allocated totals to order/global totals. Gate implementation on an explicit allocation/rounding policy. Global historical COGS already exists; legacy line-level allocations do not. |
| F3: inventory reconciliation/value | Reconcile normalized-unit opening, receipts, consumption, Kitchen Wastage, returns, adjustments and ending quantity. Disclose missing openings. Historical valuation requires a separately chosen valuation policy; acquisition-rate sales COGS is not stock valuation. |
| F4: procurement trends | Report ingredient/base-unit prices, purchase frequency and unified linked supplier acquisitions without counting a procurement and its Vendor Khata entry twice. Identify unlinked purchases. Supplier punctuality requires promised and actual receipt evidence; unknown is not failed. |
| F5: food/packaging COGS | Snapshot event-time classification, split food/packaging costs by Order and Dining Type, reconcile to combined COGS and disclose legacy unclassified costs. Later category changes do not rewrite classification. |
| F6: labor | Capture worked-hours evidence and effective historical staff classifications before productivity or department allocations. Do not use Cashier Shift duration as paid attendance. Earned-period allocation follows the separately specified payroll policy above. |
| O1: preparation | Expose observed status milestones with durations, median/p90, sample coverage and late thresholds. Specify repeated-transition/end-point rules before calculation; unknown milestones stay unknown and preparation remains separate from delivery travel. |
| O2: Holds | Show current Hold age, Cashier and stale threshold. Add durable lifecycle events before reporting historical recall/discard/conversion statistics; current persistence alone is insufficient. |
| O3: delivery | Safely expose recorded reasons, distinct attempts and unique Orders, area/rider timing, late thresholds and unsettled aging. Define final-outcome and aging evidence; a returned attempt alone is not final failure. |
| O4: rider accountability | Link independently confirmed customer collections, actual handovers, shortages and authorized write-offs before claiming verified rider liability. Distinguish Collection Due, rider-held cash and drawer cash, respecting settlement locks and collection/delivery separation. |
| O5: customer history | Determine first eligible purchase across available history before classifying first-time/returning customers. Preserve selected-range repeat rate as its own measure, masking and guest/phone/history coverage caveats. |
| O6: operations/security audit | Project recorded configuration/operations actors, actions, times and redacted changes. Add missing authentication/PIN events only under an explicit access/retention policy. Never expose raw configuration JSON, credentials, PIN hashes or sensitive customer data in exports. |
| O7: backup health | Persist attempts, initiator, target-specific results, verification status and safe failure category. Report age of last verified success and primary/secondary health; preserve failures and distinguish scheduled-but-never-run work. |
| A1–A3 | Distinct Shift-owner/actor identity, consistent Pakistan-time presentation and source schema version are required in Phase 1, not postponed until later reporting features. |

- Update stale Manager guidance and report explanations alongside the relevant implementation: stored preparation events versus missing old milestones; current Holds versus incomplete lifecycle; existing global COGS versus missing item allocation; supplier archiving versus unversioned opening/allocation history; stored cost history versus valuation; stored operations/configuration audit versus missing security events. Keep genuine limitations visible.
- The Audit Timestamp glossary wording conflicts with the UTC-storage/display distinction. Follow master UTC audit evidence and Asia/Karachi display policy; record a glossary clarification through the domain documentation workflow rather than interpreting this specification as permission to rewrite historical timestamps.

## Testing Decisions

- **Confirmed primary seam:** exercise existing authorized domain commands against a real temporary SQLite database, then read through the public analytics service into immutable report snapshots. Assert user-visible totals, attribution, buckets, coverage and contributing identities. Prefer this existing service/database boundary over mocks of SQL or private builders; no new test-only production interface is proposed.
- Use the existing analytics service, historical analytics and projection-contract suites as prior art. Existing finance/controller and migration suites cover atomic writes and upgrades. Extend existing workspace and export suites only for interactions/serialization that the service seam cannot observe. These are supporting checks around the same reporting contract, not a new set of independently mocked calculation layers.
- Phase 1 scenarios include an overnight Order on 29 October with activity at 01:00 on 30 October; two Business Days opened on one date; a receiving Shift different from the originating Shift; a Manager recording a finance movement on a Cashier-owned Shift; and bank/owner entries without drawer attribution. Assert both time bases and selected-Shift scope.
- Verify split tenders, change, partial receipts, refunds, rider settlement and linked Cash Movements count each effect once. Verify retries cannot duplicate financial evidence, a failed atomic write leaves no partial event, and existing legacy balances/reports remain unchanged after migration.
- Verify cancelled/refunded confirmed Orders count once for workload, revisions and Holds add no Orders, value/count rankings differ where expected, tied peaks remain visible, completed zero-order Business Days enter weekday denominators, open days remain separate and absent evidence never becomes zero.
- Verify naive legacy, UTC and explicit-offset timestamps including local midnight boundaries; unknown event time is excluded from actual-time buckets and disclosed. Verify historical names remain stable after renaming and current names are labeled separately.
- Compare displayed metrics, charts, contributor sums and parsed CSV/XLSX/PDF output from one snapshot, including query, schema/formula versions, event/recording time and coverage. Retain formula-injection protection and privacy tests. Revoke Manager access or change session during load/export and verify safe failure.
- For later phases, add behavior tests as each policy becomes concrete: payable/stock bridges, allocation reconciliation, observed-milestone coverage, customer-history classification and backup evidence. Do not write tests that merely duplicate private implementation logic or encode an undecided policy as fact.
- Exercise large representative snapshots in remote CI for export cancellation, cleanup and application responsiveness; use Windows CI/integration coverage for platform print behavior. Native print-dialog acceptance may need manual verification where automation cannot drive native UI.
- All Flutter/framework tests, compilation and packaging run exclusively in GitHub Actions. This specification task requires only document review and tracker verification; no local framework execution is authorized or needed.

## Out of Scope

- Implementing the application changes during specification creation, claiming runtime verification, querying restaurant data or declaring actual busiest periods.
- Replacing SQLite, adopting a new ORM/state-management stack, adding a server or integrating payment gateways.
- Creating a third interactive role or allowing Managers to perform Cashier billing, tender collection or Shift operations.
- Rewriting closed Business Days, sealed reports, original recording timestamps, historical cost classifications or missing historical evidence.
- Selecting unspecified correction authority/reconciliation, financial allocation, inventory valuation, labor allocation, security retention or delivery SLA policies implicitly. Those decisions gate their respective later capabilities; they do not block the well-defined Phase 1 work.
- Treating acquisition-rate COGS as FIFO/weighted-average stock value, Shift time as attendance, delivery as proof of collection, or all-time balances as historical snapshots.
- Customer Receipt hardware printing and optional retention/churn/cohort analysis beyond the audited first-time/returning requirement.

## Further Notes

- Source: the Manager reporting gaps and documentation audit reviewed on 29 October 2026. Its evidence is source inspection, not live data or new runtime tests. This document captures eight original timing/Shift gaps, six report-experience gaps, F1–F6, O1–O7 and A1–A3 without treating stale explanations as additional missing ledgers.
- Existing ADRs governing standalone SQLite, multiple Shifts per Business Day, in-place migrations, two-role authorization, Integer Paisa, Order Revision/settlement locks and COD separation remain binding. No ADR is superseded here.
- Suggested release sequence: Phase 1A attribution/evidence and Phase 1B peak views first; then stored operational evidence; then policy-backed finance/evidence extensions; then remaining presets/comparisons/printing/export usability. Scoped exports, identity/time correctness and provenance ship with the first phase.
- The user confirmed the test seams and authorized publication on 29 October 2026. Publish as one specification issue with `ready-for-agent`. That label authorizes the specified, ungated implementation scope; it does not resolve the explicitly listed policy gates. Subsequent implementation tickets should retain these dependencies and acceptance constraints.
