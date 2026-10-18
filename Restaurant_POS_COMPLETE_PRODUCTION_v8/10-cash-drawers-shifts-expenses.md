**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 10 — Business days, shifts, drawers, expenses and reconciliation

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Business day [DAY-01…09]

Supervisor explicitly opens one active business day; window may cross midnight. Day has business_date (e.g., Oct 11 service day), opened_at UTC, closed_at UTC, open/close actors, state and immutable close report metadata. Multiple sequential cash shifts can belong to same day. Token sequence restarts exactly once **at next business-day initialization**, with persistent unique `(business_day, token_number)` constraint. Closing must not be possible if required shifts remain open; define treatment for rider unsettled trips and noncash liabilities in review.

## Shift [SHIFT-01…12]

Each shift: cashier, start/end time, opening float, drawer ID, state, submitted blind cash count, calculated expected cash, variance, discrepancy threshold, reviewed/resolved actor. Each movement references **the shift/drawer where cash physically moves**, even when related invoice belongs to a different business day. Cashier can hand over to next cashier without forcing day close.

`Expected closing cash = Opening cash + cash tender collected - cash change given + cash pay-ins - cash pay-outs - cash refunds - cash drops`, with all terms posted in reconciled nonduplicated cash movement ledger. Carefully avoid counting the same cash sale as both tender and manual pay-in. Rider money is included **only after confirmed handover**. Do not subtract external bank supplier payment from the drawer.

### Blind close

Cashier counts denominations without seeing system expected cash; cashier submits and signs off. Then show actual/expected variance and supervisor review. Large discrepancies flag review but next shift may open while previous discrepancy is unresolved. Supervisor recount/reconciliation is appended, never overwrites original count. Manager can see complete history.

## Expense categories [EXP-01…10]

Manager have complete CRUD over user-defined category names, descriptions, active flag, sort order, parent category (optional), expense approval threshold, and allowed source. Add new category during expense entry without abandoning draft. Prevent duplicate case-insensitive active names. Editing name preserves category ID and changes display for historical expenses **only according to reporting-label policy**, while retaining historical category snapshot for audit. Hard delete only unused. When used: archive/disable; existing records remain navigable and reportable. Restore archived category where permitted.

## Expense posting [EXP-11…20]

New expense: category, paid-for description, payee/vendor, amount, source (active drawer / bank / owner cash), business day, note, optional receipt attachment/path, approval rule. On submit show whether drawer cash changes. Cash-funded expense posts expense classification **and** one cash pay-out atomically with shared transaction/reference, not two separate deductions. Bank/owner funding does not alter drawer. Include petty cash/repairs/cleaning/transport/utility and arbitrary custom categories.

**Expense vs supplier purchase:** inventory purchases go through procurement and stock/Khata; don't record an inventory purchase again as generic petty cash expense. Supplier-associated non-stock operating services can classify as expense with invoice ledger. Salary advance/loan and supplier settlement are **not** operating expenses twice; label cash movements by purpose.

## Manual movements [CASH-01…08]

Pay-in (opening additions, rider cash accepted, approved deposit transfer), pay-out (approved petty cash, supplier cash payment, salary cash payment, refund, cash drop). Each movement has stable ID, idempotency key, kind, linked purpose, positive absolute PKR amount and signed direction, drawer/shift, actor, time, note and approval. Direct generic pay-ins/outs require reason to avoid misclassification. Payment tender and cash movements must be traceable in a joined audit view.

## Report outputs

X-report (live snapshot; does **not** close day), shift handover sheet, Z day close, expense by category/source/operator, petty cash detail, drawer discrepancy history, cash received from riders, cash vs noncash tender and change/refund reconciliations. Printed receipt is not required; PDF/Excel export is required.

## Critical edge cases

Shift covers midnight; rider returns during following shift; cash expense after checkout but before handover; partial COD collection; cash tender change; cash and noncash split; supervisor reverses posted expense; cash discrepancy greater than shift float; power outage during count submission; owner cash-funded supplier payment not from till; shift closed with unresolved rider settlements; duplicate close attempts.

## Acceptance tests

Open day → open shift → sale cash tender with change → rider handover → petty cash → supplier pay-out → blind count → variance → close → next shift → day Z report. All totals must reconcile and every cash event exist exactly once. Cashier does not see expected cash pre-count. Used category archives; unused category deletes; expense remains auditable after rename.

## Custom category management and day-close notification clarification

Manager (Supervisor/Owner) is the only management role, with identical permissions for both titles; Manager can administer and approve but cannot perform cashier tasks. See chapters 01 and 24.


## v6 cashier routine movements and physical rounding

Routine cashier `PAY_IN` and `PAY_OUT` are allowed without Manager PIN, with `cash_movements.approved_by=NULL`, mandatory actor, note, amount, source and immutable log. Cash received/change are always physical whole rupees after one deterministic final-cash-leg rounding adjustment. Cash rounding belongs to separate signed paisa gain/loss account, affects expected drawer/Z summaries but does not inflate item sales or change exact JazzCash/Easypaisa/Bank/Card tender amounts. See Chapter 32.
