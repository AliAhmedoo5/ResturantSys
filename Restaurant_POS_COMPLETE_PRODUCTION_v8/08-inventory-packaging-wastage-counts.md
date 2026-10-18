**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 08 — Inventory, stock ledger, packaging, low stock, wastage and counts

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Stock master [STK-01…12]

Manager can create/read/edit/archive ingredients, prepared components, finished stocked goods, packaging and general supplies. Fields: item code, name, type, base unit/dimension, stock tracking toggle, storage area, reorder threshold, preferred supplier(s), optional expiry tracking and active state. New custom stock item can be created directly while registering supplier; must be immediately selectable for that supplier. Hard delete only if unreferenced.

Inventory quantities are derived from **append-only movement ledger**, not treated as manually editable truth. Each movement includes item, signed normalized qty, movement type, source transaction ID, business day, UTC time, actor, optional cost layer and reason. Display on-hand, reserved (if enabled), available, latest count, low-stock status and cost estimate.

## Unit conversion

Base conversions only within compatible dimensions: mass (g/kg), volume (ml/L) and count (pcs/dozen). Pakistani purchasing units can be configured per item: Mann default 40kg, Pao 250g, Dharri 5kg, Bori 50kg, Darjan 12, but **Peti/crate and other packs vary** and require supplier-item-specific multiplier. Persist factor snapshot per purchase; never silently change historic quantities after a factor edit.

## Stock movement types [STK-13…23]

Opening balance, supplier purchase receipt, sale/BOM usage, packaging usage, prep/manufacture, waste/spoilage, transfer (future multi-location), physical count correction, supplier return, authorized manual adjustment and reversal. Every movement has idempotent source; recipe consume on **committed order**, not hold/draft or status transition. Packaging is a configurable fulfillment-mode rule: delivery bags, boxes, wrappers, cups etc. Dine-in may use none. Count composed deal BOM and packaging once.

Manual adjustment requires supervisor reason and approval if risk threshold exceeded. Hard deletion of movements prohibited; correction posts reverse-linked ledger entry.

## Inventory receive flow

Inventory → Receive Stock, or Suppliers → Purchase → choose supplier → eligible item list → qty + unit → cost → review normalized quantity → post purchase. Inventory and payable update atomically; even if supplier cash payment fails the entire operation rolls back or is recorded as a separate explicitly recoverable payment command.

## Physical count [CNT-01…09]

- Supervisor starts count session with item selection, snapshot sequence/version, actual physical counted quantity, count taker and submit timestamp.
- System detects stock movements posted after snapshot; either calculate expected at count time using movement sequence or prevent stale postings and request recount. Never overwrite a live stock balance with an out-of-date count.
- Show variance qty and monetary value with costing rules, approval (potentially different actor by policy), and reason.
- Posting adds one adjustment event. Subsequent edits require new count/reversal.
- Count sessions may be by storage room/category; do not force restaurant to close for whole-store count.

## Waste and expiry [WST-01…07]

Record item, normalized qty, reason (burnt, dropped, expired, spoilage, prep mistake, promotion/sample, other), occurrence time, responsible staff, supervisor approval when needed and estimated cost. Decrease stock once. For cooked order cancellations, the exact ingredient adjustment depends on consumed/prepared stage—**do not automatically restock finished food**. Support expiry date, lot/batch tracking where required, low stock and negative balance alerts (unconditionally non-blocking for cashier checkout).

## Costing

Prefer weighted-average or FIFO purchase-cost layers as an explicitly configured owner policy; store movement cost snapshot for reproducible margin reporting. Account for paid vs unpaid purchases identically for COGS: purchasing on supplier credit still creates stock asset and payable. Missing costs show `Unknown cost`, not zero; margin reports flag coverage percentage.

## Edge cases and tests

Fractional kg purchases (e.g., 2.5kg), ml ↔ L, supplier-specific crates, returned supplier goods, expired unused packaging, closed-day correction, concurrently counted item receipt, negative stock warning, deleted recipe ingredient, zero-cost purchase, duplicate invoice, duplicate order posting. Assert stock ledger balances equal projected stock and no movement is posted twice.
\n## Required perpetual negative stock rule\nEvery committed order creates ingredient/packaging consumption exactly once even when available quantity is zero or negative. Stock projections can be negative. Receipt postings simply increase the projected balance from negative to positive; no future catch-up consumption is queued. Example: opening 2kg − sale usage 3kg = −1kg; receipt of 5kg = 4kg. Alerts remain reviewable. Physical stock counts must reconcile movement sequence safely and never hide shortage history.\n