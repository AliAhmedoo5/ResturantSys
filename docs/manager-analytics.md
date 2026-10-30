# Manager analytics

Open **Dashboard** directly from the main sidebar. The **Manager** destination contains staff, settings and administrative tools; its Dashboard tab also opens the same reporting workspace. Dashboard is a read-only view of the local restaurant database. It covers live activity and historical Business Days. It requires an active Manager session; it does not give a Manager access to cashier operations.

## Reading the dashboard

The first four measures lead each report. Overview also includes the daily sales chart; additional measures and source tables follow below. Hover or long press a truncated metric explanation or a chart bar for the full definition or exact value. Expand **Measure definitions & scope** and **Reporting scope & methodology** for scope rules, comparison restrictions and source limitations. Missing-data states remain visible on the cards.

Use **Live** for the active Business Day, including a day opened before midnight. Automatic refresh runs while the dashboard is visible; **Refresh** requests a new snapshot. The last successful refresh time describes the data currently displayed. Closing or locking the session clears reporting data from the screen.

For history, select a preset or custom Business Day opening-date range. The upper boundary is exclusive internally. An overnight order stays with its assigned Business Day, rather than moving into the next day's totals. Time displays and grouping use Asia/Karachi.

Select **Overview** or one of the 13 report families:

| Report | What to inspect |
| --- | --- |
| Sales | Recorded value, order volume, discounts, tax, delivery fees, rounding, received tenders and trends |
| Order operations | Status counts, revisions, cancellations, refund exposure and separately labeled current Hold aging |
| Delivery | Area activity, trips, delivery/return evidence, Collection Due and settlement exposure |
| Customers | Known/guest coverage, repeat purchase rate, known-customer average ticket and masked customer activity |
| Menu & deals | Recorded quantities and line values, popular and zero-selling catalog entries |
| Inventory | Current low/negative stock, recorded movement history and quantity evidence |
| Procurement | Recorded purchase spend, converted quantities and unit costs |
| Supplier Khata | Current payable, credit purchases and payments by funding source |
| Cash & shifts | Float, receipts, movements, expected/count cash and discrepancies |
| Expenses | Recorded outflows and categories, with financial classifications explained |
| Staff & payroll | Salary rates, posted accruals, payments, advances/recoveries, current balances and separately labeled cashier activity |
| Profitability | Historical global order COGS and revenue, with cost coverage and policy-dependent allocation limits |
| Control & audit | Recorded revision/token/rounding/report evidence and export/delivery health |

Read each metric's explanation and quality state. **Missing data** is not zero. **Not applicable** indicates no applicable population or denominator. **Estimated** identifies incomplete evidence or approximate methodology. Coverage counts explain which records contribute to timing and rate statistics.

In **Order operations**, current active Holds show their ID, owning Cashier,
creation time, age at snapshot cutoff and stale classification. Open **Filters**
and set **Hold stale after (minutes)**; the default is 30 minutes, and a Hold is
stale at or above the selected threshold. The setting survives period/filter
changes and is included in CSV, Excel and PDF snapshot metadata. Cashier filters
scope Hold ownership; date/time, Shift, Dining Type and payment filters do not
reconstruct historical Holds or assign them to a Business Day. Holds remain
outside confirmed Order counts, Tokens, sales and workload charts.

Only currently persisted Holds are available. Deleted/recalled lifecycle history
is unavailable. Reporting excludes draft labels, items, customer contact and
delivery content. Cashier names are labeled current; missing historical names
are not inferred. New Hold creation timestamps retain UTC evidence; old naive
timestamps retain the disclosed Asia/Karachi assumption. Unknown/future creation
evidence has unavailable age and stale classification, with age coverage shown.

Cashier and Shift filters describe the originating order cohort and owning/receiving drawer separately. Dining Type and payment filters narrow order/activity breakdowns only. A split-payment order must be counted once even if it has several tender rows. The report states where a filter applies: current stock, staff and supplier balances must not appear filtered by an unrelated order selection. Current balances remain labeled current when browsing historical activity.

Trend tables and detail tables provide the values behind the visual display. Source details identify recorded evidence without exposing staff PIN hashes, report credentials or unmasked customer contact information.

## Interpreting the calculations

- **Recorded order value** includes valid committed orders, including Collection Due. It excludes canceled, voided and fully refunded orders. It is distinct from tax-exclusive recognized revenue.
- **Known-customer average ticket** divides eligible recorded order value for known normalized phone identities by their eligible order count, with the denominator displayed. Guests are excluded. This weights orders equally; it does not average customer means. Customer aggregate rows show each masked identity's own average and contributing source orders separately from order history. With no known orders, the average is Not applicable.
- **Collected tender** is recorded tender minus change, with explicit refund rows applied. Legacy payments are grouped by their order's Business Day; their tables do not support a complete actual-receipt-time cash-flow statement.
- **Expected drawer** follows the cashier ledger. Cash refunds recorded as PAY_OUT reduce the drawer once, rather than being subtracted again through negative tender rows. A missing blind count leaves variance unknown.
- **Collection Due** remains separate from physical delivery. An unsettled trip's expected amount is cash exposure; it is not proof that the rider collected it.
- **Purchases**, **supplier credit**, **supplier payments** and **operating expenses** are different measures. Adding them together would double-count activity. Likewise, current purchase prices cannot establish historical sales COGS.
- **Period comparisons** disclose the baseline and the absolute difference in the metric's unit. A zero baseline retains that absolute difference and has no percentage growth. Comparisons are withheld for live/open coverage without an equivalent elapsed baseline.

Monetary aggregation uses integer paisa. Existing legacy rupee fields are converted per record before summing; this reporting behavior does not imply that every historical database field has been migrated to integer storage.

## History and missing evidence

The database stores salary rates and immutable payroll accrual, payment, advance and recovery ledgers; expense categories and immutable expense postings; supplier invoice due dates and payment allocations; and historical global order COGS at retained event-time acquisition rates. Reports distinguish these existing inputs from missing old evidence. New linked finance payment events retain actual time independently of recording time. Earlier finance postings without those events do not establish actual money timing. Salary earned-period allocation, historical supplier opening/allocation reconstruction and Menu Item/Deal margin allocation still require their stated policy and evidence boundaries; acquisition-rate COGS does not establish stock valuation.

Inventory movement coverage began with schema v14. Schema v16 retains observed cashier status milestones without reconstructing older preparation history. Current Holds are persisted, while complete Hold lifecycle history is unavailable. Supplier archiving and stored cost history exist; they do not make earlier supplier opening edits versioned. Operations and configuration audit records exist, while complete security-event capture and the reporting projections remain separate coverage gaps. Corresponding reports should disclose those specific limits rather than describe the implemented ledgers as absent.

Closed Z-reports are immutable saved snapshots with their own revision/hash. A historical dashboard query over current records is exploratory and can differ after a later correction; it must not overwrite or silently replace the sealed report. Open **Z-Reports & Backups** for the original saved day-close report and its delivery archive.

## Export and verification

Dashboard exports use the displayed immutable query snapshot, carrying the selected period, filters, time zone, units, quality and source metadata. CSV and Excel text is protected against spreadsheet formula interpretation; numeric money remains numeric. Exporting does not automatically email or otherwise transmit a report.

The implementation specification and confirmed test boundaries are in [0002-manager-analytics.md](specs/0002-manager-analytics.md). Framework analysis, tests, screenshots and builds run in GitHub Actions only.

Finance payment timeline (reporting version 2)

The Expenses family includes a dated finance payment timeline. Expense, supplier settlement, salary payment and advance commands atomically retain a linked payment event with signed Integer Paisa, actual time, immutable recording time, recording Manager, approval, assigned Business Day and physical Shift where applicable. The Shift owner remains separate from the Manager recorder. Bank/digital and owner payments have no physical Shift and cannot change drawer cash.

Finance flow totals use those events once; linked Cash Movements and expense/payroll/supplier ledger contributors are supporting views and must not be added again. Payroll accruals, advance offsets and unpaid credit purchases are excluded. Open-period late entries accept explicit Pakistan time. Entries cannot precede the assigned open day or physical Shift, use a future actual time, or correct closed historical periods. Returned funds within an open period produce separately linked reversal events.

Legacy finance records without linked time evidence remain visible as coverage gaps and in their original posting views. Their posting timestamp is not substituted for actual money time. Actual-time calendar totals exclude unknown times; incomplete evidence is disclosed and totals marked estimated. Transaction recording evidence and original sealed reports remain immutable. Shared CSV/XLSX/PDF serialization consumes these same snapshot rows and coverage notes.

## Auditable identity and timestamp evidence

Manager snapshots capture SQLite `PRAGMA user_version` inside the authorized read transaction, report formula version, cutoff, selected Business Day IDs, filters and evidence notes. CSV, XLSX and PDF serialize this same immutable snapshot. The workspace displays schema, formula version and the cutoff in Asia/Karachi.

Known source timestamps display `+05:00 [Asia/Karachi]`; matching `_source` columns retain their original stored UTC/offset or naive value. A naive legacy timestamp is explicitly assumed to be Asia/Karachi. For example `2026-10-29T19:30:00Z` displays as `2026-10-30 00:30:00 +05:00`. A missing actual event time remains missing, even when a recording timestamp exists.

Schema 23 captures names atomically at source insertion in an append-only identity evidence table. It preserves Shift-owner Cashier separately from the recording and approval actors, supplier, employee and expense category identities. Current names are labeled separately; an unknown transaction-time name is marked unavailable. Migration does not backfill current names into old financial history or modify original sealed reports. Existing expense category snapshots remain authoritative. Stable source and identity IDs survive renames and staff/supplier archival.

Audit Timestamp means immutable recording evidence; Event Time means actual occurrence. New money events retain explicit UTC recording time and preserve actual event time independently. Reports convert either known instant for Asia/Karachi display while exporting the source string. Existing naive local fields are preserved, never rewritten as supposedly known UTC history.

COD receiving attribution and evidence limits: see [COD settlement evidence](cod-settlement-evidence.md).

## Busiest Order days and hours

Order operations now includes separate **Busiest by confirmed Orders** and **Highest recorded value** charts for days and hours. Every confirmed Order contributes once to workload, even after cancellation or a refund. Holds and append-only Order Revisions add no Orders. Select a bar to inspect its exact contributing Order rows. Daily and hourly tables describe the same cohort in different ways and must not be added together.

Business Day mode preserves each assigned Business Day ID, including separate days opened on the same date and opened days with no Orders. Calendar mode uses actual Order creation dates in Asia/Karachi; an overnight Order may move to the next calendar date without changing its assigned Business Day. Daily workload rankings remain daily when Sales uses weekly or monthly grouping. Hours always mean the actual Asia/Karachi creation clock hour across the selected Order cohort.

All 24 clock-hour rows remain visible. Zero means the observed selected cohort contains no Orders at that hour; it does not assert that the restaurant traded for an entire hour. Missing source coverage is unavailable. Missing creation times withhold hourly counts, values and ranks rather than assigning those Orders to an invented hour. Historical Business Days that were never opened are not fabricated.

Count and value have independent ranks. Every tied peak has rank 1; ties follow chronological order, with same-date Business Days ordered by ID. Current eligible value preserves the Sales definition: grand total including Collection Due, excluding CANCELLED, VOIDED and REFUNDED states. REFUND_PENDING remains eligible under the existing definition. Average ticket divides by the corresponding eligible Order count, never the workload count; an empty eligible population has no average. Cancellation/refund Order counts and explicit refund amounts remain separate from workload and value.

The source table and CSV/XLSX/PDF carry the same bucket values, eligible denominators, ranks, tied-peak flags, Order IDs, time basis, value basis and coverage explanation as the charts. Refund amounts describe the selected originating Order cohort, not actual receipt-event timing. Use the payment timeline for actual money movement.

# Selected Shift cash bridge

Cashier and Shift filters select the owning/receiving drawer in **Cash & shifts**.
The bridge covers each whole selected Shift, including receipts from Orders
originating in another Shift. Dining Type, payment method and actual-time windows
describe the separately labeled activity breakdown; they never trim a drawer's
opening-to-count accountability. Selecting a Shift explicitly loads its whole
history even when its Business Day opened outside a selected calendar window.

Opening Float plus customer cash accepted, rider handovers and other pay-ins,
less refunds, expenses, supplier payments, payroll/advances, cash drops and other
outflows gives expected cash. Finance reversals retain their signed effect.
Only **Physical cash effect** rows contribute to this bridge. Linked tender,
payment-event and Cash Movement details describe the same effect once.
COD settlement attribution is not another inflow. Bank/owner funding, unpaid
purchases and salary accruals do not change drawer cash.

Blind Count is displayed separately; Discrepancy is counted minus expected.
Uncounted Shifts have unavailable Discrepancy. Unlinked historical cash tenders
have unknown receiving attribution, remain visible as coverage gaps, and withhold
complete expected cash and Discrepancy. The partial balance from retained evidence
is labeled separately. Amount/time similarity never establishes a link.
Manual Cash Movements retain their physical effect but disclose unavailable
independent actual time. Actor, owner, source links, Karachi times and original
timestamp evidence travel with the snapshot into CSV, Excel and PDF exports.
Existing sealed X/Z reports remain unchanged.
