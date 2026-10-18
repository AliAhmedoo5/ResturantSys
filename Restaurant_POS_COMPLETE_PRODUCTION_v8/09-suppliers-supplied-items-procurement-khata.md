**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 09 — Supplier CRUD, custom supplied products, purchases, payments and Khata

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Supplier directory [SUP-01…09]

Manager can create, list/search, edit, archive and (only if unreferenced) permanently delete suppliers. Store stable supplier ID, business/display name, contacts, address, supplier category, notes, status, preferred settlement method, opening payable (separate opening-balance event), outstanding payable and history. **During creation and editing, supervisor selects the stock items supplier can provide**, and can add an entirely new item not already in inventory, choosing name, type and unit. A supplier may sell arbitrary ingredients, packaging, cleaning consumables or general goods. Supplier-item relation may store supplier SKU, typical unit, pack multiplier, last price, tax inclusion and lead time; relation is editable without losing old purchases.

## Supplier status semantics [SUP-10]

| Purchase/payment state | Display |
|---|---|
| No posted purchase or opening balance | **No purchases** |
| Posted purchase/opening payable, paid amount exactly zero | **No payments** |
| Positive payment less than payable | **Partially paid** |
| No outstanding payable on posted purchases | **Paid** |
| Net supplier credit/advance, if allowed | **Credit balance** (separate) |

Compute status from ledger, not manually editable string. Opening balance must not be hidden by "No purchases" if payable exists: UI may label `Opening balance / No payments`. Explicit adjustments/reversals should not be counted as genuine supplier cash payments.

## Procurement [PUR-01…15]

Purchase form: supplier → automatically filtered allowed supplied items → quantity and chosen unit → unit price or total line price → tax/transport as separate configured cost allocation → payment now (possibly 0) → payment source (drawer/bank/owner) → invoice/slip reference/date/due date → review → post. Multi-line purchases are preferred; one supplier invoice can contain chicken + bags, each with its own unit conversion and cost. Block unrelated supplier items at both UI and domain layers; `Add new supplied product` creates/reuses inventory item and mapping through manager permission then returns to purchase form without losing draft.

Posting transaction:
1. Persist purchase header/lines and converted base quantities with immutable unit conversion snapshots.
2. Create inventory-receipt movements for stock-tracked lines, with purchase-cost layers.
3. Increase supplier account payable by full purchase value (including permitted allocated costs).
4. If immediate payment >0, create separate supplier payment allocation and reduce payable; if drawer-funded, add one cash pay-out. If outside drawer, no drawer movement.
5. Update supplier payment status, stock and reports through ledger projections; no double accounting.

A non-stock service (equipment repair, electricity, transport fee) may be a supplier-associated operating expense, not stock. Require explicit line classification so the owner isn't shown fake inventory or COGS. Supplier can supply custom product categories with dynamic item creation.

## Khata ledger [KHA-01…11]

Chronological events: opening payable, posted invoice, debit/credit note, payment, reversal, supplier advance if permitted. Each has reference, transaction time, actor, source, signed amount, outstanding after event and optional invoice allocation. Support partial payments, credit terms, overdue/aging bands (0–7, 8–30, 31–60, 60+ days configurable), export statement, supplier summary and invoice-level due.

Payment mode: cash from active drawer, outside drawer owner cash, bank transfer or other configured channels. Cash from drawer automatically appears once in shift cash-out. Supervisor approval and evidence may be configured above amount threshold. Block duplicate payment reference/idempotency and payment exceeding due unless explicit supplier advance policy is enabled.

## CRUD and safety

Editing supplier name/contact/supplied items is immediate and audited; previous invoices retain original name/units/price snapshots. Deleting supplier with purchase, payment or opening balance is prohibited; `Archive` prevents new invoices but allows settlement of old payable. Posted invoice must be reversed via credit note/return; changing associated stock receipt must be transactionally corrected as well. Removing item from supplier mapping blocks new purchase only, not reports.

## Practical flows

**Example:** Register `City Packaging`, phone, select `Pizza box`, create custom item `Sealing sticker` / pcs, select both. Purchase 200 boxes for Rs.8,000, paid Rs.0 → stock +200, payable +8,000, status `No payments`. Pay Rs.3,000 from drawer → payable 5,000, status `Partially paid`, drawer -3,000. Pay remaining Rs.5,000 by bank → status `Paid`, no cash drawer effect.

**Reversal:** Supplier delivered spoiled goods: supplier return references original invoice, reduces available unconsumed quantity and supplier payable/creates supplier credit correctly, never simply deletes supplier or goods receipt.

## Tests

Custom supplier item create/assign/filter; changed associations; no-payment status; partial/full payment; owner vs drawer funds; duplicate invoice references; wrong supplier item rejected service-side; units conversion; item already sold then supplier return; supplier archived with outstanding balance; aging; multi-line invoice reconciliation; accurate ledger equation.
