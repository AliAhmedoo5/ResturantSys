**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 12 — Comprehensive reporting and owner analytics

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Goal

Give owner **accurate, actionable views of the business**, not only a daily revenue number. Reports offer summary dashboards, drill-down to source transactions, saved filters, export and metric explanations. Every financial metric has a named formula in `21-analytics-measure-definitions.md`. Show `Insufficient costing data` rather than fabricated profit when BOM/costs are missing.

## Report UX [RPT-01…13]

1. Owner landing: sales today vs comparable prior business day, net recognized sales, cash expected/shortage, deliveries late/failures, supplier overdue balance, top items, ingredient/packaging anomalies and estimated margin with coverage notice.
2. Report explorer with category sidebar, top KPI strip, trend visualization, sortable detail table and drill-down drawer.
3. Filters: business-date range (today/yesterday/7/30/custom), time of day, cashier, shift, order type, product, category, deal, discount, payment method, delivery area, rider, customer segment, supplier, stock category, expense category and department (only when meaningful to report).
4. Time grouping: business day, hour, week, month; compare prior period or same weekday, with clearly labeled denominators and incomplete current-day caveat.
5. Presets: End of day, Last 7 days, Month to date, Rider settlements, Supplier Khata aging, Food cost variance, Expenses and Salaries. Manager can save private filters; owner can share role-appropriate report presets.
6. `Export CSV`, `Export Excel` multi-sheet, `Save PDF`, print via standard Windows print dialog **for reports only**; filter metadata, generation timestamp and business date included. No forced hardware printing.
7. Access control: Cashier sees own shift operational summaries only; Manager sees all operations and full finance/profit reports.
8. Graphs must show axes, units, currency and date range; allow tabular alternative; indicate missing sample points vs 0 explicitly.
9. Deep-link from metric to contributing orders/stock/Khata/payroll/expense events, respecting access.
10. Saved report exports should not leak PIN, secret keys or raw customer personal data by default.
11. Long-running exports show progress, cancellation and durable output path; do not freeze cashier billing.
12. Export content reconciles to on-screen query and persisted ledger, no separate spreadsheet arithmetic that changes values.
13. Closed day reports immutable unless explicit correction event, with generated-again notice and version provenance.

## Report catalog (MUST for production feature set)

| Family | Detailed views and breakdowns |
|---|---|
| **Sales** | Gross sales, discounts by preset, net sales, tax, fees, sale volume, average ticket, hourly peak, daily/weekly/monthly trends, revenue by mode, category, item, variant, deal, cashier and shift. |
| **Order operations** | Counts by lifecycle state, held/draft aging, prep/ready turnaround, late order thresholds, void/cancel reasons, refunds, repeat checkout attempts. |
| **Delivery** | Delivery vs takeout, timing by area, rider assignment and trip load, failure/return rates by reason, redelivery, COD collection vs rider remittance, unsettled cash aging. |
| **Customers** | New vs returning, purchase frequency, top repeat customers, average basket, areas, customer-level history with permitted privacy masking. |
| **Menu/deals** | Item popularity, gross/net deal sales, discount redemption, upsells, average quantity per bill, slow/zero sellers, food-cost coverage and item margin if costing available. |
| **Inventory** | Beginning, purchases, sale BOM, packaging, wastage, manual adjustments, returns, ending qty; negative/low-stock timeline, physical count variance, stock valuation. |
| **Procurement** | Spend by supplier/item, unit-price trends, purchase frequencies, supplier delivery performance where recorded, inventory cost changes. |
| **Supplier Khata** | Opening payable, purchases, returns/credits, payments by source, closing payable, invoice status, aging/overdue, suppliers with **No payments**. |
| **Cash/shifts** | Cash sales, tendered/change, drawer pay-in/out, refund cash, rider cash accepted, expected vs counted, shortage/overage by operator/shift, X/Z reports. |
| **Expenses** | By custom category, payee, amount, source, date, recurring patterns, manager approvals, petty cash vs other expense classifications. |
| **Staff/payroll** | Salary accrued, paid, unpaid, advances, outstanding recoverables, expenses by department, variance over time. |
| **Profitability** | COGS and ingredient/packaging spend attributed to sales, estimated gross margin by item/deal, waste loss, operating expense, labor burden, net business result with accounting-policy caveats. |
| **Control/audit** | Manager edits, discount configuration history, PIN resets (metadata only), voids/refunds, posted reversals, inventory manual adjustments, backup health, failed logins and synchronization/migration errors. |

## Core day-close deliverables

Final Z-report contains gross/net/tax/discounts, tender breakdown, cash movement reconciliation, refund/void summary, COD receivables, rider balances, stock usage/waste, supplier payable changes and day-close approvals. Required Excel tabs (extensible): Executive Summary, Sales by Item/Deals, Stock & BOM, Wastage/Returns, Shifts & Cash, Suppliers/Khata, Delivery/Riders, Expenses, Staff/Salary, Profitability (with missing-data flags). Original 6-sheet outline is retained as a minimal compatibility preset, while owner can generate wider workbooks.

## Business intelligence principles

- Transaction time filter and business-day filter are not interchangeable; default financial report uses business day.
- Separate ordered/gross value, collected cash, delivered sales and recognized revenue; never call all of these simply "sales".
- Supplier credit purchases impact inventory/payables even when unpaid. Cash out only when physically paid.
- Salary accrual and salary payout are distinct; don't subtract both as separate costs.
- Wastage of already-expensed consumed ingredients is not automatically a second inventory consumption.
- Cost data coverage ratio, estimated vs actual, reporting methodology and rounding presented near profitability.
- For large datasets, indexes/materialized summaries can speed up UI, but underlying ledger remains truth and recomputation must be possible.

## Acceptance

Date range/owner filters exactly match detail rows and exports; partial refunds, split tenders, COD and rider settlement correctly allocated; supplier credit doesn't show cash payment; chart 0 vs missing distinguished; workbook all expected tabs; late-night business day attributed correctly; finance balances and reports reconcile to SQL ledger queries; role-restricted personally identifiable data remains hidden.

## Email/WhatsApp delivery and recipient management [RPT-SEND]

- A finalized Z-report PDF and detailed XLSX MUST be stored locally before external send; attachment hash and immutable report revision retained.
- Manager defines verified recipients, channels, auto-send, PDF/XLSX selection, sensitive redaction and sender identity and may send/retry; there is no separate Owner tier.
- Email auto-sends through a configured provider with durable offline outbox and retries. No sending while PC is off unless an independent worker or a previously connected cloud relay is active.
- WhatsApp manual share is a supervised user action; **auto WhatsApp** requires official Business Platform/provider setup, permitted business template, consent, internet and token-protection architecture. Do not imply that opening a chat silently sends PDF.
- Report Delivery History shows queued, submitted/accepted, confirmed delivered if evidenced, failed and retry states, attempts, recipients masked and safe error text.
- Report delivery is not part of gross/net sales calculations. Network failure must never roll back day close. Full specification: `25-business-day-report-email-whatsapp-delivery.md`.
