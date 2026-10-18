**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 28 — State machines, financial postings, invariants and failure recovery

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


**Aim:** turn user-visible flows into deterministic service commands that cannot create inconsistent financial, delivery, stock or payroll records. Use explicit enumerated states, audit events, transaction boundaries and unique command/idempotency keys. Posting rules here extend chapters `15–17`.

## 1. Business day and shift state machines

```text
BUSINESS DAY: NOT_OPEN -> OPEN -> CLOSING_REVIEW -> CLOSED
                    CLOSING_REVIEW -> OPEN (cancel review without posting)
                    CLOSED -> (no direct reopen) -> new day / adjustment workflow

SHIFT: NOT_STARTED -> OPEN -> COUNT_IN_PROGRESS -> COUNT_SUBMITTED -> CLOSED
                                                -> REVIEW_REQUIRED -> REVIEWED
```

- Business-day status and shift status are independent. Multiple sequential shifts can belong to one business day. Only active authorized staff may start a shift; posted sale links both IDs.
- Cash count is **blind** until submitted; expected amount is calculated after submission using posted drawer ledger and relevant cutoff.
- A discrepancy may remain Review Required while next shift opens if owner's nonblocking policy says so. Review does not overwrite original physical count; any recount is a separate event with actor.
- Business day closing creates one immutable `day_close` record and one Z-report `report_run`. Report artifacts/jobs can complete later. Restart does not rerun close.

## 2. Order, fulfillment and payment are separate axes

```text
ORDER INTENT: DRAFT <-> HELD -> CONFIRMED -> [CANCELLED or FINISHED]
                              |                  
                              +-> fulfillment events

DELIVERY FULFILLMENT: CONFIRMED -> PREPARING -> READY -> OUT_FOR_DELIVERY
                                                          |       |
                                                       DELIVERED FAILED_ATTEMPT
                                                                   |
                                                    RETURNED / REATTEMPT_AUTHORIZED
                                                                   |
                                                            OUT_FOR_DELIVERY
TAKEAWAY FULFILLMENT: CONFIRMED -> PREPARING -> READY -> COLLECTED
DINE-IN FULFILLMENT: CONFIRMED -> PREPARING -> READY -> SERVED -> COMPLETED

PAYMENT: UNPAID -> PARTIALLY_PAID -> PAID -> PARTIALLY_REFUNDED -> REFUNDED
                  \-> COD_EXPECTED -> RIDER_HOLDING_CASH -> DRAWER_RECEIVED
```

- `ORD_CONFIRMED` persists order, token, priced lines, taxes, discount snapshot, BOM/packaging usage and event exactly once; no kitchen ticket generated.
- COD order may be delivered while unpaid in accounting, or 'rider holding cash' before handover. The `Delivered` label is not a `Paid` label.
- Void reason/approval and refund accounting are independent. If payment already collected, canceling fulfillment alone must not magically refund it.
- Failed delivery attempt logs attempt number and reason; original order retains ID. Redispatch does not create another order or another automatic BOM consumption. If refired cooked product is made anew, supervisor records explicit additional prep/wastage movements.
- A `repeat order` is a **new draft** with new id and current prices, not a transition from old Delivered back to Draft.

## 3. Inventory postings and stock-count semantics

```text
RECEIPT_FROM_SUPPLIER -> +stock(quantity at base unit), +inventory value,
                         +supplier payable (if invoiced), optional supplier payment
SALE_COMMIT           -> -BOM ingredient quantities, -packaging by fulfillment mode
WASTAGE               -> -stock(quantity), +waste cost event
SUPPLIER_RETURN       -> -stock returnable goods, -supplier payable / +vendor credit
PHYSICAL_COUNT        -> adjustment = accepted_actual - computed_book_at_count_cutoff
VOID                  -> explicit decision:
                         unused material => +restock correction
                         prepared/consumed => no restock; reasoned wastage/recovery
```

- Every stock event includes `movement_id`, item, quantity base unit, type, linked source event, cost snapshot, actor, business day and idempotency key.
- Stock quantity should derive from posting ledger with cached balances under transaction. `current_stock = sum(movement.quantity_base)` (or opening+sum, if opening as a movement). Counts never replace history.
- Physical count opened with version/snapshot. Movements during count must be replayed/handled explicitly; do not apply stale delta by using original expected number blindly.
- Supplier associations: unique `(supplier_id, stock_item_id)` active relationship; purchase line may only use an item that supplier supplies (or manager explicitly creates association in same transaction before line). Historical mapping snapshots remain.
- Product and deal versioning: BOM from actual committed menu/deal configuration; archived products still appear in historic invoices and stock movements.

## 4. Supplier purchases, balances and display statuses

```text
Purchase draft -> validated receipt/invoice -> POSTED -> (optional CORRECTED_BY_REVERSAL)
Supplier payment draft -> POSTED -> (optionally REVERSED)
```

- With `P = posted supplier invoices + opening payable`, `C = posted credits/returns`, `M = allocated valid payments`, `Balance = P - C - M`. Supplier-level invoice allocations and unapplied advances require explicit handling.
- Derive display state for non-credit-edge-cases: `No purchases` if no posted purchases and zero opening payable; `No payments` if posted payable exists and posted payments zero; `Partially paid` if payable remains and some payment exists; `Paid` when valid payable settled. If credit balance < 0 show `Supplier credit/advance` rather than masking it as Paid. If invoices are overdue display separate overdue marker.
- **Purchase with paid-now = Rs.0:** increases inventory and payable; does not touch physical cash.
- **Purchase Rs.8,000, cash now Rs.3,000:** inventory receives full quantity, supplier charge Rs.8,000, supplier settlement Rs.3,000 and exactly one drawer pay-out Rs.3,000. Remaining payable Rs.5,000.
- **Later bank payment Rs.5,000:** payable becomes 0; bank/outside-drawer account event, zero new cash drawer movement.
- Edits to supplier display name or item association never change historic invoices. Supplier master cannot hard-delete with balances/history.

## 5. Cash payment and drawer ledger

Always separate **order net sales**, **collected tender**, **physically drawer cash** and **customer/rider receivable**.

| Event | Drawer cash effect | Other domain effect |
|---|---:|---|
| Opening shift float | + opening balance (not sales) | Shift float |
| Cash payment received at counter | + actually retained after change | Customer paid amount, order payment allocation |
| Card/wallet/transfer verified | 0 | Noncash settlement channel |
| Delivery COD expected | 0 | Customer/rider collection obligation |
| Rider hands cash to cashier | + actual handed cash | Reduce rider-held receivable; possible shortage outstanding |
| Petty cash from drawer | − expense paid | Expense category cost posting |
| Pay supplier from drawer | − paid amount | Supplier payable reduced; inventory not affected again |
| Pay supplier outside drawer | 0 | Supplier payable reduced; outside payment source |
| Salary/advance paid from drawer | − paid amount | Payroll/advance ledger event |
| Customer cash refund | − actual cash refunded | Refund allocation/amount |
| Manual safe drop | − removed physical amount | Cash transfer, not operating expense |

`Expected closing drawer = Opening float + drawer cash receipts + drawer pay-ins - drawer pay-outs - drawer cash refunds - safe drops` (all non-overlapping typed events). Do not use `tendered amount` without subtracting change; count retained amount. Grouping payment and physical deposit requires provenance linking but must not double-post.

## 6. Staff/payroll postings

```text
Period gross accrual       -> +salary payable, +labor expense for period
Salary paid from drawer    -> -salary payable, -drawer cash
Salary paid from bank      -> -salary payable, outside-drawer payment
Advance issued            -> +employee recoverable, -cash/bank source
Advance deducted from pay -> -employee recoverable, -salary payable (no new cash out)
```

All deductions/recoveries have approved classifications; salary edit after period close creates a correction event. Payroll obligations, cash payouts and cost recognition are separate and must reconcile.

## 7. Commands / transaction boundaries (pseudo contract)

```text
CreateOrder(commandId, actor, draft, tenderIntent):
  require active shift/day and POS permission
  BEGIN IMMEDIATE SQLite transaction
  assert commandId not processed; validate current prices/tax/discount/deal/options
  allocate next token per business_day_id with unique constraint
  INSERT immutable order, lines, line modifiers, price/tax/discount snapshots
  INSERT committed payment allocations or COD obligation as appropriate
  INSERT one fulfillment event (Confirmed)
  INSERT stock movements for recipe + packaging exactly once per line source
  INSERT audit actor/action and command result marker
  COMMIT
  render saved result; asynchronously prepare optional digital receipt

PostSupplierPurchase(commandId, actor, supplier, items, paidNow, paySource):
  require purchase permission; validate supplier-item relationships and units
  BEGIN transaction
  insert purchase invoice and receiving lines; insert stock receipts
  increase supplier payable by invoice; allocate valid paidNow amount
  if paidNow from drawer: insert one cash movement referenced to payment
  insert immutable posting and audit; COMMIT

CloseBusinessDay(commandId, actor, businessDay):
  require close permission; assert close conditions and current version
  BEGIN transaction
  insert close snapshot, immutable close event and report generation intent
  mark business day CLOSED; mark token next-day boundary
  COMMIT
  generate durable Z/PDF/XLSX; enqueue notification jobs separately
```

The exact separation of report artifacts from close transaction should ensure a crash after closing leaves a recoverable *generate report pending* intent; never leave a closed day without a possible report.

## 8. Idempotency and audit invariants

- A command with same idempotency key and same payload returns same original result; conflicting payload with reused key fails.
- Every posted ledger object has a unique source reference and can only be reversed once per eligible amount; partial refunds supported within original amount.
- Audit events store actor, approved_by, timestamp, business day, action, before/after sanitized snapshots, reason, source and correlation ID; cannot be modified by any role.
- Read models/reports rebuild from authoritative events, not from volatile frontend state.
- State transitions reject stale expected revision, order already delivered/voided, closed period mutation, inactive user or permission change.
- Do not allow negative physical count input, invalid cash denomination count, invalid monetary units, duplicate supplier invoice without review, or inconsistent tax/discount rounding.

## 9. Crash / offline recovery table

| Failure point | Recovery |
|---|---|
| App closes with unconfirmed cart | Restore durable draft or explicitly discard only with user choice; no order posted |
| Crash during SQL order transaction | SQLite rollback; retry by command ID; no half-order or half-stock event |
| Crash after order commit before screen refresh | Query command marker, show existing token; do not create second order |
| Crash during supplier purchase posting | Roll back or resume idempotently; stock/payable/cash must remain consistent |
| Offline during Z report email send | Report remains closed and locally saved; durable delivery outbox retries |
| PC shut down with queued WhatsApp/email | Local sender waits for next running session/service; cannot promise delivery while power off |
| Backup destination missing | Primary data remains operational, exception shown to owner, retry backup without re-closing |
| Report PDF generation failed after day close | Report intent pending and regenerable from immutable close/snapshot; send not scheduled until valid artifact exists |

## 10. Nonnegotiable invariants for QA

1. One checkout → at most one committed order/token and one set of stock postings.
2. One supplier purchase → one invoice, one inventory receipt posting set, one payable charge, optional single payment and single cash effect.
3. One rider cash handover → one drawer receipt linked to handover, never increase cash by 'Delivered' alone.
4. One employee advance → one recoverable and one paid-source effect, never duplicate expense recognition.
5. One closed business day → one close event, versioned reports and delivery jobs, no delivery failure rollback.
6. Role checks validated at command boundary, including dynamically configured shortcut controls.
7. No manager can erase audit or historic financial transactions, even when interface calls the action `Delete`.
8. Reports match business-day IDs and posted ledger; missing cost inputs visibly marked incomplete.
