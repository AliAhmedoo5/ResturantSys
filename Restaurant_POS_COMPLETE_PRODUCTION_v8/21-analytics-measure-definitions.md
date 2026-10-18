**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 21 — Owner report formulas and metric dictionary

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


Every metric shown in UI/Excel/PDF must disclose its calculation and reporting date basis. Queries aggregate **posted events** only (reversal offsets applied). `Business day` is default for operations; UTC timestamp is retained for audit.

| Metric | Exact definition / warning |
|---|---|
| Gross order value | Sum original committed item + modifier/deal prices before discounts and excluding canceled/unrecognized lines according to selectable view; always state inclusion policy. |
| Applied discount | Sum authorized discounts by scope/line and order, capped by rule; refunded discount allocations reversed accordingly. |
| Net order sales | Tax-base-adjusted recognized sales of committed fulfilled/valid orders net of discounts, cancellations and refunds according to selected recognition policy; delivery fee and tax shown separately. |
| Tax collected/payable | Sum posted transaction-time allocated tax with refund/adjustment reversals; configuration-specific inclusive/exclusive rules. |
| Cash collected | Net **actual customer cash tender** plus rider handovers accepted, separated into categories to avoid double counting. |
| Average order value | Net eligible order sales / count of included eligible orders; show denominator. COD/unfulfilled exclusion according to mode policy. |
| Orders per hour | Number of committed orders grouped by order creation hour in Asia/Karachi; separate business-day grouping when day crosses midnight. |
| Discount utilization | Eligible orders where preset used / eligible committed orders; report rate and absolute Rs. given. |
| Repeat customer rate | Number of distinct customers with >=2 orders in selected range / customers with >=1; guest/unknown excluded. |
| Delivery failure rate | Unique delivery orders with final failed outcome / dispatched delivery orders in selected period, with reattempts separately counted. |
| Prep time | `ready_at − confirmed_at` (or preparing_at→ready_at with stated definition); excludes missing timestamp orders from percentile, shows coverage. |
| Rider travel time | `delivered_at − dispatched_at` for valid timestamps; distinguish trip stop order from order delivery. |
| Rider outstanding | COD customer amounts confirmed collected but not physically handed to cashier, plus shortage allocations, less accepted settlements/authorized write-offs; keep uncollected customer debt separate. |
| Supplier payable | Opening payable + invoice totals + debit notes − payments − approved credit notes/returns/reversals. |
| Supplier status | No purchases / No payments / Partially paid / Paid / Credit, as specified in `09` using posted ledger state. |
| Supplier overdue | Unpaid invoice allocations where due date < business date as-of query; bucket age (0–7, 8–30, 31–60, 60+), current not overdue separately. |
| Inventory on hand | Sum signed movement qty for item at as-of timestamp; unit dimension normalized. |
| Physical stock variance | Counted normalized qty minus expected normalized ledger qty at count snapshot reference. |
| Waste cost | Wasted qty × item unit cost at event timestamp based on selected costing model; missing cost flagged. |
| Product ingredient COGS | Recipe consumption qty × cost-layer unit cost, expanded by actual sold deal/modifier selections, net of allowed reversals. |
| Packaging COGS | Qty packaging consumed per fulfillment/order × event-time cost; separately identifiable in per-order margin. |
| Gross margin | Recognized net sales excluding pass-through tax − realized food/packaging COGS; show missing-cost coverage and delivery fee treatment. |
| Operating expense | Posted relevant noninventory expense accruals or valid cash expenses, excluding supplier inventory purchase capitalization and avoiding payroll double counting. |
| Salary due | Accrued gross salary + approved additions − salary payments − advance settlements/deductions; advances are distinct recoverables. |
| Net operating result | Net sales + recognized other operating income − COGS − operating expenses − recognized staff costs − other allocated business costs, **only with adequate period allocation and data coverage**. Otherwise `Cannot calculate reliably`. |
| Expected drawer cash | Opening float + net customer cash − cash refunds + accepted rider cash + approved pay-ins − pay-outs/drops; reconciled per actual shift. |
| Drawer variance | Physical counted cash − expected closing cash. Display signed shortage/overage and review state. |
| Cash expense by category | Sum posted unreversed expense amount in category IDs, respecting category history/label snapshots and funding source. |
| Void/cancel rate | Count of committed orders canceled or voided / total committed orders for cohort and period; include or exclude drafts clearly. |
| Low stock | Item on-hand <= configured threshold in base unit; all negative stock as separate warning. |

## Metric quality badges (UI text, not ornamental badges)

- **Complete**: all input data present and reconciliation passed.
- **Estimated**: source cost method approximate or operational timestamps incomplete; tooltip explains.
- **Missing data**: exclude value from aggregate or flag as incomplete, never silently treat missing input as zero.
- **Not applicable**: denominator 0 or category not enabled.

## Drill-down contract

Clicking net sales opens order/line postings, discounts/refunds. Supplier payable opens invoices/payment allocations. Gross margin opens recipe versions and inventory cost layers. Cash variance opens shift/count and movements. Rider shortage opens trip/order/handovers. This must work even for archived products/staff/suppliers and after report export.

## Export metadata

All files carry report name, generated UTC/local time, business-day range, active filters, totals/row count, data-quality status, currency, time zone, schema/report formula version and generated-by staff. CSV newline and Excel injection prevention: prefix dangerous spreadsheet formula leading characters in text fields to keep exports safe; preserve numeric monetary columns as actual numbers formatted as currency in Excel.
