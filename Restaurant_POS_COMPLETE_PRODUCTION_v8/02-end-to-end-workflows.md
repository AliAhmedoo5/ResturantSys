**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 02 — Complete operating workflows and state machines

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


This is the operational sequence the real app must support. Every numbered flow must be executable while offline.

## A. First installation / daily start

1. Install app and initialize local encrypted secrets plus SQLite/Drift schema. Show database health and backup destination checks.
2. First-run wizard creates owner with unique PIN, restaurant details, timezone, basic tax/pricing defaults and optional opening supplier balances; explicit approval of configuration is required.
3. Manager creates supervisor and cashier staff PINs, departments, suppliers, supplied-item mappings, expense categories, menu, recipes, deal definitions, discount presets, shortcut/quick-action profile and cash policies.
4. Supervisor **opens business day** with an explicit named business date and operating state (no auto-opening on wall-clock midnight).
5. Cashier signs in, opens assigned shift, counts opening drawer cash; transaction screen becomes available.

## B. Delivery sale (primary workflow)

1. Cashier selects Delivery, enters normalized phone; matching customer/address appears with previous order summary. Can choose existing address, edit delivery address, or create customer without phone under explicit exception policy.
2. Add product by one click or search/shortcut. If deal, fill required choices and modifier changes. Update quantity in fixed cart; price and totals preview instantly.
3. Eligible discount presets are visibly listed without switching to Supervisor screen. Preset eligibility/validity/stacking/minimums checked by service. Delivery fee is explicit and snapshot-stored.
4. Optionally **Hold** cart; persisted draft contains product choices, customer/address and draft ownership. **Recall** restores safely; conflicts/repricing are displayed if catalog changed meanwhile.
5. Review total and payment method. COD remains unpaid; prepaid cash/card/digital method follows configured verification policy. Cash requires tendered amount and correct change. Split must sum precisely.
6. **Confirm** atomically creates order, order lines/options, immutable financial price snapshot, initial status event, recipe/packaging consumption events, receivable/payment entries, and assigned token. Persist before user success feedback.
7. Cashier verbally tells nearby kitchen and manually sets Preparing and Ready milestones as work proceeds. No kitchen ticket or separate kitchen UI.
8. Assign order to rider/trip; mark Out for Delivery. One trip may hold multiple orders, and rider can have multiple trips across shift/day subject to policy.
9. Customer receives delivery; mark Delivered separately from Paid. When rider returns, record collected amount by order/trip and physically received amount; show cash short/overage and reconcile.
10. Confirm completion only when delivery, payment and rider settlement each have their own correct status; reports distinguish them.

## C. Takeaway / dine-in sale

Cashier selects Takeaway or Dine-in table (3–5 tables, configurable). Same cart and discount flow. Optional open-tab behavior must be explicitly enabled; otherwise pay/confirm. Recipe and packaging rules differ by fulfillment mode. No delivery address/rider required. Order may still be preparing/ready and completed through cashier controls.

## D. Cashier shift / business-day close

1. Cashier records pay-ins/outs with category and source, makes/receives rider cash handovers, settles permitted refunds/expenses and ends shift.
2. **Blind count**: denominations and count entered without exposing expected cash; submit locks the count snapshot. After submission show variance and supervisor review status.
3. Discrepancy above threshold marks investigation, but may not block next shift (non-blocking policy). Recount requires supervised supplementary record, not overwriting first count.
4. Supervisor finalizes shifts, reviews unresolved exceptions and rider settlements, generates X (interim) and Z (final) reports.
5. Day-close locks transaction association, performs verified backup and exports independently. Backup/export failures get retry without reopening or double closing.

## E. Purchase, stock and Khata

1. Supervisor creates supplier with contact, opening balance (clearly tagged) and one-or-more supplied items; creates new custom inventory items on same form when necessary.
2. Choose supplier in purchase: only associated items are offered. Enter item, quantity, unit conversion, unit or total cost, invoice/slip, receiving date, immediate payment and payment source.
3. Validate allowed supplier-item relation; transactional receipt increases stock and inventory cost layer; payable increases by full purchase amount, then payment reduces payable only for money actually paid.
4. When payment = 0 and purchase exists, status **No payments**. Partial pay status **Partially paid**. Full settlement **Paid**. New suppliers without purchases show **No purchases**.
5. Record supplier payments later, from drawer (cash pay-out) or outside drawer (bank/owner cash), with correct ledger effect and evidence.
6. Stock count takes snapshot, records counted quantities and variance, then authorized approval posts a difference adjustment. Wastage uses reason and costing.

## F. Cash expense category and petty cash

Supervisor creates/edit/archives user-defined categories. Authorized user selects category, amount, payee, source (drawer/bank/owner), optional evidence and notes. For drawer cash, post **one** cash-out event; expense posting should not be a second deduction. Correction posts reversal with reason.

## G. Staff / salary / PIN

Supervisor creates staff, department, job role, salary effective period, optional POS role. If system login chosen, require unique PIN and role scope. Creation of another Manager requires Manager reauthentication, an explicit warning, and audit; there is no Owner tier. Salary advances, earned payable, cash/bank payments and reversals are separate entries; employee deletion becomes archival if any entry exists.

## H. Failure and exception flows

- **Interrupted checkout:** pending intent/idempotency key reconstructed; do not double-create order/stock usage.
- **Customer cancelled before prep:** authorization/reversal policy, no automatic refund assumption.
- **Cancelled after cooking:** ingredients remain consumed; record wastage or separate recovery policy, do not automatically restock cooked food.
- **Failed delivery:** reason, attempt time, rider and redelivery/refund/disposal decision. Do not auto-infer return to stock or payment reversal.
- **Wrong supplier item:** reject; allow authorized supplier-item mapping edit without losing unsaved purchase.
- **Supplier overpayment:** reject or explicitly route to supplier advance liability/credit as approved policy; never make silent negative payable.
- **Duplicate PIN:** reject even if different role; do not reveal whose PIN was matched.
- **Network down:** no service interruption; local features remain usable.
- **Reopen old day:** do not mutate posted day; adjustments enter current day referencing old transaction or a controlled correction mechanism.

## State machine snapshot

- Business day: `Draft → Open → Closing Review → Closed` (closed immutable; compensating records only).
- Shift: `Not started → Open → Count Submitted → Closed`; discrepancy `Clear / Needs Review / Resolved` runs separately.
- Order: `Draft/Held` (not committed) or `Confirmed → Preparing → Ready → Out for Delivery → Delivered`; Takeaway/Dine-in use `Confirmed → Preparing → Ready → Completed`; exception branches `Cancelled` / `Failed Delivery` with reattempt lineage.
- Payment: `Unpaid → Partially Paid → Paid` or `Refund Pending → Partially Refunded/Refunded`, independent of fulfillment.
- Rider trip: `Created → On Route → Returned → Settlement Pending → Settled/Short/Over`; trip cannot count expected money as drawer cash before handover.
- Supplier invoice: `Draft → Posted → Settled/Partly Paid` with reversal only after post.
- Physical count: `Draft → Submitted → Approved/Rejected → Posted`.

## Additional end-of-day send and retry flow

1. Authorized Manager reviews day-close reconciliation and signs the Z report.
2. Local `CloseBusinessDay` transaction locks the day and writes an immutable close snapshot/report intent once.
3. Report generator creates PDF and XLSX (plus optional CSV) and saves them locally; if generation fails, retry that operation without reopening the day.
4. Notification outbox inserts one automatic job per approved recipient/channel/revision with stable idempotency keys. No network dependency is added to local closing.
5. Background sender attempts queued email or official automated WhatsApp when configured and online; manual WhatsApp only opens a share workflow and requires human action.
6. Manager checks `Delivery History` for Queued/Sending/Accepted/Failed; may resend to approved recipient with audit. If PC off, local-only jobs wait for the next worker run.
7. Owner receives PDF/Excel and an optional privacy-safe summary. Sending outcome never mutates previously closed finances. See chapter `25`.


## v7 customer-first persistence boundary after cart

1. Cashier builds cart with two/three products/deals; save only in draft memory/local held-cart storage.
2. Click `Continue — Customer` and pick mode. For delivery, find returning customer by phone or enter new customer's name, phone, delivery area chosen from active serviceable Manager-configured zones, street/house, optional landmark. For dine-in/takeaway, allow relevant fields to be skipped.
3. Show fee from chosen delivery area and order review. Cashier selects method (Cash, JazzCash, Easypaisa, Bank/Raast, Card, COD, Split) without provider verification tags.
4. `Complete Order` saves customer link/address/area snapshot, order, token, stock consumption and tenders atomically. Failure must not lose cart; retry idempotently.
5. After confirmation, cashier edits/cancels under prior v6 rules with logs until relevant rider trip settled.
