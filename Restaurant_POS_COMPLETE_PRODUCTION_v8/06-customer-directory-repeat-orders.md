**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 06 — Customers, phone lookup, delivery addresses and repeat sales

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Customer data [CUS-01…09]

Customer has stable ID, display name, one or more phone numbers, optional note and opt-out flags, active/archive state, date created and last order. Multiple normalized phone numbers can map to same customer only through an explicitly confirmed association. Maintain addresses as separate records: city/area, street/address line, landmark, delivery instructions, label (Home/Office), active/default status and geolocation only if intentionally entered (not required). Store phones in local searchable normalized form while applying field visibility policy.

- Cashier must find a customer by full or partial phone with high relevance but protect against accidental wrong-number match; selection is explicit.
- Duplicate normalized phone should propose existing customer instead of silently creating a second record.
- Editing a customer's address affects future orders only; committed order stores an address snapshot.
- Customer without phone can be permitted for walk-in/dine-in; delivery phone requirement is configurable and can be mandatory.
- Customer order history shows date, items, mode, amount, actual payment and fulfillment state, with privacy boundaries.
- Repeat-order action copies items/deal selections/notes to **new draft**, revalidates active items and current prices, default delivery details, and excludes old payment/discount by default unless currently eligible.
- Multiple persons using shared phone: require name/address confirmation before attributing old order or personal details.
- Merging duplicate customers is an audited supervisor operation in later phase; initial release can link/mark duplicate and avoid dangerous history rewrite.
- Customer record deletion for privacy must be a defined redaction policy that retains mandatory transaction records; never delete accounting orders.

## Typical delivery call flow

Cashier opens Delivery → types 0300… → search result with name, order count, latest address → confirm → select address and area → `Repeat last order` or build new. If existing order has an obsolete combo, show "This deal changed; choose a replacement" and editable line, not silently repeat it.

## Analytics

Repeat purchase rate is customers with ≥2 orders within selected range / customers with ≥1 order in range (define active customer cohort clearly); average order value and frequency by customer and area, customer phone search efficiency, address delivery outcomes. Don't export phone numbers in aggregate dashboards.

## Acceptance

0300 and +92300 resolve equivalently; optional second phone; persistent address revisions; checkout snapshot old address; duplicate detection; repeat sale re-prices; anonymous takeaway; customer-related reports do not confuse customer merges or refunded orders.


## v7 — Mandatory delivery-customer step after cart (flow clarification)

For **delivery** the cashier first builds the cart, then clicks `Continue — Customer Details`: name, phone, serviceable area, address/street/house, and optional landmark/instructions. Phone lookup offers existing customers and multiple saved addresses; link or amend details with explicit consent/selection. Use normalized Pakistani numbers for deduplication but preserve formatted display and allow landline/alternate numbers where needed. If the phone exists, prefill only after cashier picks record; never collapse two different customers based only on matching name. A customer may have multiple delivery addresses and default preferences. Empty non-delivery customer fields remain optional per order type. Final order commit links customer ID and immutable address/area/fee snapshot. Held carts may include unsaved customer step. Customer records remain manager-visible for reporting but Managers do not place cashier orders.
