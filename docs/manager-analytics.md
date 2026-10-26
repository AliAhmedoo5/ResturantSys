# Manager analytics

The Manager Portal's **Dashboard** is a read-only view of the local restaurant database. It covers live activity and historical Business Days. It requires an active Manager session; it does not give a Manager access to cashier operations.

## Reading the dashboard

Use **Live** for the active Business Day, including a day opened before midnight. Automatic refresh runs while the dashboard is visible; **Refresh** requests a new snapshot. The last successful refresh time describes the data currently displayed. Closing or locking the session clears reporting data from the screen.

For history, select a preset or custom Business Day opening-date range. The upper boundary is exclusive internally. An overnight order stays with its assigned Business Day, rather than moving into the next day's totals. Time displays and grouping use Asia/Karachi.

Select **Overview** or one of the 13 report families:

| Report | What to inspect |
| --- | --- |
| Sales | Recorded value, order volume, discounts, tax, delivery fees, rounding, received tenders and trends |
| Order operations | Status counts, revisions, cancellations and refund exposure |
| Delivery | Area activity, trips, delivery/return evidence, Collection Due and settlement exposure |
| Customers | Known/guest coverage, repeat purchase rate and masked customer activity |
| Menu & deals | Recorded quantities and line values, popular and zero-selling catalog entries |
| Inventory | Current low/negative stock, recorded movement history and quantity evidence |
| Procurement | Recorded purchase spend, converted quantities and unit costs |
| Supplier Khata | Current payable, credit purchases and payments by funding source |
| Cash & shifts | Float, receipts, movements, expected/count cash and discrepancies |
| Expenses | Recorded outflows and categories, with financial classifications explained |
| Staff & payroll | Staff/department/job-role and cashier activity; missing payroll inputs |
| Profitability | Available revenue/cost components and missing costing/allocation inputs |
| Control & audit | Recorded revision/token/rounding/report evidence and export/delivery health |

Read each metric's explanation and quality state. **Missing data** is not zero. **Not applicable** indicates no applicable population or denominator. **Estimated** identifies incomplete evidence or approximate methodology. Coverage counts explain which records contribute to timing and rate statistics.

Cashier, shift, Dining Type and payment filters describe an order cohort. A split-payment order must be counted once even if it has several tender rows. The report states where a filter applies: current stock, staff and supplier balances must not appear filtered by an unrelated order selection. Current balances remain labeled current when browsing historical activity.

Trend tables and detail tables provide the values behind the visual display. Source details identify recorded evidence without exposing staff PIN hashes, report credentials or unmasked customer contact information.

## Interpreting the calculations

- **Recorded order value** includes valid committed orders, including Collection Due. It excludes canceled, voided and fully refunded orders. It is distinct from tax-exclusive recognized revenue.
- **Collected tender** is recorded tender minus change, with explicit refund rows applied. Legacy payments are grouped by their order's Business Day; their tables do not support a complete actual-receipt-time cash-flow statement.
- **Expected drawer** follows the cashier ledger. Cash refunds recorded as PAY_OUT reduce the drawer once, rather than being subtracted again through negative tender rows. A missing blind count leaves variance unknown.
- **Collection Due** remains separate from physical delivery. An unsettled trip's expected amount is cash exposure; it is not proof that the rider collected it.
- **Purchases**, **supplier credit**, **supplier payments** and **operating expenses** are different measures. Adding them together would double-count activity. Likewise, current purchase prices cannot establish historical sales COGS.
- **Period comparisons** disclose the baseline. A zero baseline has no percentage growth. A partially completed live day must not be compared with a complete earlier day as though coverage were equal.

Monetary aggregation uses integer paisa. Existing legacy rupee fields are converted per record before summing; this reporting behavior does not imply that every historical database field has been migrated to integer storage.

## History and missing evidence

The database does not yet contain complete salary/accrual/advance ledgers, invoice due-date allocations, event-time sale cost layers, preparation lifecycle timestamps or a comprehensive security/configuration audit. Corresponding reports explain what cannot be calculated reliably. Older inventory history also has a coverage boundary: movement recording began with schema v14.

Closed Z-reports are immutable saved snapshots with their own revision/hash. A historical dashboard query over current records is exploratory and can differ after a later correction; it must not overwrite or silently replace the sealed report. Open **Z-Reports & Backups** for the original saved day-close report and its delivery archive.

## Export and verification

Dashboard exports use the displayed immutable query snapshot, carrying the selected period, filters, time zone, units, quality and source metadata. CSV and Excel text is protected against spreadsheet formula interpretation; numeric money remains numeric. Exporting does not automatically email or otherwise transmit a report.

The implementation specification and confirmed test boundaries are in [0002-manager-analytics.md](specs/0002-manager-analytics.md). Framework analysis, tests, screenshots and builds run in GitHub Actions only.
