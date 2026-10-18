**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 17 — Financial integrity, event accounting, audit and invariants

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Source-of-truth principle

A posted order/purchase/payment/refund/cash handover/salary payout is a durable source document. Users may correct erroneous postings through an authorized **reversal** linked to original and then post the replacement. Historical rows remain accessible. Dashboard totals are derived from ledgers, not directly edited "current balance" values.

## Money units and rounding

PKR stored integer paisa; quote display in Rs. with configured rounding policy. Percent discounts computed at defined line/order step with deterministic tax allocation. Round exactly once at specified boundary, not repeated across widgets. Never mix base decimal quantity with PKR amount as floating-point doubles. Sales totals formula: sum(line base + modifier/upgrade charges) − applied discounts + applied taxes (depending inclusive/exclusive configured policy) + order fee adjustments − other explicit credits = payable. Tax rules are business-configured; not hardcoded.

## Supplier account payable

`Supplier outstanding = opening payable + posted purchases + debit adjustments − posted payments − supplier returns/credit notes − authorized reversals (signed appropriately)`. Status from positive purchase/payment event totals, not a string. Supplier payment originating in drawer creates a single cash pay-out movement. Supplier purchase on credit affects stock and payable even if cash not spent yet.

## Cash drawer

`Expected cash = opening physical float + direct cash customer tender received − cash change returned + accepted rider cash handovers + approved pay-ins − authorized pay-outs − cash refunds − cash drops`.

Avoid duplicate representation: a cash tender may internally create a cash movement of net retained cash, or separate received/change entries, but the expected cash query must include **exactly one net contribution**. Both are legitimate implementations; choose one consistently, with test fixtures and explanation. Supplier cash settlement, salary payment and petty cash are cash pay-outs linked to their own business transaction—not a second unlinked expense. Actual = cashier counted notes/coins. Variance = actual − expected. Variance review never silently updates actual drawer movements.

## Rider receivable

`Trip/order COD receivable = expected customer cash collection − customer payments allocated − authorized allowances/reversals` depending event flow. Rider liability to restaurant tracks cash confirmed collected but not physically handed over. On rider cash handover: cash drawer ↑, rider liability ↓; no new sale. Shortage remains rider receivable/exception until resolved. When customer actually never paid, keep customer/order receivable rather than assigning fake rider theft.

## Stock

`On hand(q) = opening + receipts + approved returns + counted positive adjustments − order BOM consumption − packaging use − wastage − supplier returns − negative adjustments`. Every component movement source idempotent; a sale with deal choices decomposes exact ingredient quantities once. Prepared/cooked canceled product should **not** be automatically restocked; create waste reason/explicit disposition. Inventory valuation uses configured costing method and event-time cost snapshots. Missing costing data is `unknown`, never 0 by convenience.

## Salary and operating expenses

Accrual basis: salary earned is payroll expense/liability, payout reduces cash and liability. Salary advance pays cash and creates advance recoverable, not instantly another salary expense. Recovering an advance against salary reduces salary payable and advance receivable; this settlement has no second cash payout. Cash petty expenses are categorized operating costs; procurement for inventory produces inventory asset/cost layers and supplier payable; do not double-count purchased goods as immediate expense and COGS.

## Ledger posting abstraction

For each financial business command define: transaction id, source type, source id, actor/session, business day, value timestamp, ledger postings, cash movement (if applicable), stock movements (if applicable), approval evidence, idempotency key and reversal reference. When using a double-entry general ledger, every journal transaction must satisfy `sum(debits) == sum(credits)`. A practical initial system can use strongly reconciled separate subledgers, but every material report must have a cross-subledger reconciliation test and accounting method statement.

## Event-state invariants [INT-01…14]

1. No two committed orders share token number within a business day; daily sequence reset exactly once at day creation.
2. One confirmed order intent maps to one committed sale and one matching BOM posting set.
3. Held order never creates revenue, stock consumption or sale token.
4. Customer delivery completed does not automatically mean customer paid.
5. Cash from riders counts only after handover accepted by a shift/drawer.
6. Supplier credit increase never changes drawer expected cash without actual payment.
7. Every posted purchase receipt has linked supplier posting (or explicitly paid cash purchase with correct source).
8. Expense with drawer cash has exactly one cash pay-out, not two.
9. A consumed recipe cannot be reversed twice or restocked cooked food automatically.
10. A salary advance is not salary expense and later repayment is not negative expense without policy.
11. Every adjustment/refund/void/stock correction has actor, reason, original reference and applicable approver.
12. Unauthorized role cannot mutate via direct domain method even if UI hides action.
13. After migration, backup restore or power interruption, ledger and projections reconcile to same totals.
14. Account/report balances never result from editing a cached total directly.

## Audit event design

Audit metadata: event ID, UTC timestamp, business-day id, terminal/app version, acting staff/session, approving staff (where relevant), entity type/id, action, reason, sanitized before/after snapshots/hashes, transaction id and result. No raw PIN, connection secrets or full payment credentials. Tamper-evident hash chain over audit batches is recommended, but local single-machine physical admin control limits guarantees; export/signed archival adds deterrence. Reports can filter approvals, failed logins, category edits, shortcut changes, archived records, post-close adjustments and reversal chains.

## Close and reconciliation procedure

Before Z report: compare orders/allocations/refunds, cash movements/shift counts, rider receivables, supplier invoices/payments/returns, inventory movement summations, salary payments and source accounts. Display unresolved differences and severity, not silently force report to balance. Final close snapshots totals, stores version/hash, releases next business-day creation, then schedules backups/exports independent of close transaction.

## Separation of financial close from message delivery

A business-day close and its immutable financial snapshot MUST remain valid regardless of PDF generation, backup, email, or WhatsApp delivery outcome. Delivery notifications do not create cash, sales, inventory, supplier or payroll ledger entries. Duplicate jobs can generate duplicate messages but must NEVER generate duplicate financial postings. Report versions and source posting event cutoffs are recorded for reconciliation; audit every recipient/configuration change and manual resend. Differentiate message `accepted_by_provider` from verified `delivered` and log ambiguous result as such.
