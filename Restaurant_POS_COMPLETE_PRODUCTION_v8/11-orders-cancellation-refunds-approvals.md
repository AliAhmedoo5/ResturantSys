**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 11 — Orders, cancellations, voids, returns and refunds

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Order records [ORD-01…12]

Committed order is immutable financial source document with order ID, business day, token, mode/table/address snapshot, customer ID and name snapshot, cashier ID, list of original item/deal selection snapshots, discounts/taxes/fees, total payable, configured tender allocations, fulfillment state and linked events. Updating status or correcting money posts events; don't overwrite original order amounts. Customer-facing order number remains stable through delivery attempts/refunds; optional new fulfillment attempt IDs.

`Order status` ≠ `Payment status` ≠ `Stock disposition` ≠ `Rider settlement`. Each has independently audited events and projections. Supervisor approvals attach to requested operation with subject ID, requested amount and reason; approval should expire after short window and cannot authorize a changed amount unnoticed.

## Before commit [ORD-13]

Cashier may delete/change cart lines or release a held order. No inventory movement or token should exist. Cashier can clear without permission after a confirmation prompt; held draft deletion should retain minimal audit if policy requires.

## Cancellation after commit [VOID-01…10]

Cashier cancels immediately using their authenticated cashier session, selects mandatory reason and context (prep started? rider dispatched? any money collected?). **No Manager/Supervisor PIN or approval is required.** Commit one immutable cancellation event and applicable correction postings according to context:

1. Financial: unpaid receivable closed/cancelled, or paid tender refunded through **separate refund command**; never assume cancellation already gave cash back.
2. Stock: if not prepared/consumed and ingredients actually can be returned to usable stock, post supervised reversal per item. If cooked/prepared, retain raw-material consumption and optionally post waste/loss classification; no automatic raw ingredient restock.
3. Delivery: remove from active rider manifest only through transfer/return status; adjust cash expected using explicit rider settlement allocation events.
4. Reporting: retain cancelled order line and gross amount, expose cancellations separately from net recognized sales and refunds; preserve actor/reason/timestamps.

No kitchen void slips or printer communication required. Cashier tells nearby kitchen verbally; UI can display a prominent verbal-notification reminder for in-progress food.

## Refunds [REF-01…12]

Partial/full refund supports selected order items/quantity or amount as configured, mandatory reason, original tender/reference, cashier authority within refundability safeguards, refund funding source and associated restock/wastage disposition. A refund is separate from delivery failure and from cancellation state; partial refunds may leave order delivered/partly paid with refund allocations. Cash refunds create one negative cash movement in actual shift; bank/card/digital refunds are recorded as `Pending External Confirmation` unless integrated/verified, **not automatically marked paid**. Reject refund > net paid refundable amount, repeated refund idempotency, inconsistent split allocation. Show remaining refundable amount.

A supervisor should review cash refund totals and refund rate by operator/period. Cashier must not be able to arbitrarily set a negative item price in lieu of a refund.

## Return of physical products [RET-01]

Customer-returned cooked meals do not automatically re-enter ingredient inventory. Sealed unused packaging/goods may be restocked under explicit stock-quality inspection. A returned delivery can spawn another trip/attempt with lineage, or be cancelled/refunded through approved workflow; payment ledger remains independent.

## Authorization and audit [APR-01…08]

Approval event captures requester, approver, reason, amount, order ID, action, expiration, prior state and final outcome. Supervisor enters PIN into overlay without logging out cashier, approval session scoped to one command; disable universal "approve everything" reuse. Manager may override according to security policy, with required note. History screens show rejected as well as approved requests. Feature flag can hide cashier void requests but never prevent supervisor fixing erroneous historic entries.

## Edge cases

Already refunded sale, two partial refunds racing, post-cooked cancellation, rider out with customer meal, order after Z-close, customer wants exchange, prepaid card transfer not confirmed, delivery failure with remake, reopened held cart originally under old price, same payment cash movement posted twice.

## Acceptance

Cashier cancels without supervisor PIN → one immutable cancellation, no duplicate stock reversal, no automatic money refund. Partial refund cannot exceed paid. Cash refund appears once in drawer. Returned food not magically restocked. Full audit and original order snapshot remain after archival of involved menu item.

## Confirmed order amendments (replaces legacy protected-void assumptions)
Cashier opens a confirmed order and edits quantity/items/modifiers/deals, or removes an item. A mandatory reason is captured for removal or price-reducing changes; all before/after snapshots are preserved. The cashier does NOT request manager PIN. Apply a single atomic order revision with item-level price/tax/discount/fee deltas, ingredient/packaging movement deltas and customer tender/receivable consequences. Existing payments are not overwritten: calculate any refund owed or additional amount due separately. If food has already been prepared, do not restock cooked consumption automatically; mark it as consumed/wastage or explicit non-restock disposition. Once an order is closed within a finalized Z day, corrections are dated follow-up adjustment documents, not rewriting prior finalized numbers. The Manager can investigate all revisions but cannot perform cashier editing.
