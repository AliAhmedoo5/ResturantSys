**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 00 — Product charter, boundaries and glossary

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Purpose

Provide a reliable offline Windows POS + lightweight ERP for a small fast-food restaurant in Pakistan, operating primarily on delivery orders while supporting takeaway and 3–5 dine-in tables. Staff must serve customers quickly while the owner can independently understand sales, cash position, inventory usage, supplier debt, payroll commitments and profitability drivers.

## Personas and priority outcomes

| Persona | Success condition |
|---|---|
| Cashier | Find customer/item, build bill, use deals/preset discounts, hold/recall, collect or mark COD, hand off to rider and settle cash in seconds. |
| Supervisor | Keep operations moving; configure menu/deals, discounts and expense categories; resolve errors; reconcile shifts, stock, supplier Khata, staff and delivery exceptions. |
| Supervisor/Owner (Manager) | Single management role: staff/PINs, catalog/deals, supplier/stock, all settings, financial reports and approvals; **never cashier billing or shifts**. |
| Kitchen helper | Receives verbal directions; no required kitchen app, tickets or PIN unless granted another actual POS role. |
| Rider | Assignment and cash handover recorded by authorized staff; no rider mobile app required. |

## Initial-release modules

Auth/PIN and departments; business-day/shift lifecycle; catalog, recipes/BOM, modifiers, configurable deals, discounts; lightning-fast POS; delivery/takeaway/dine-in; phone customer lookup, multiple delivery addresses and repeat orders; draft/hold/recall; order status/timers; payment/COD/split/refunds/void requests; rider trips and settlement; stock and packaging; wastage, physical counts, Mandi purchases and supplier allowed-product mappings; Khata; expense categories/petty cash; cash handover; staff/salary/advance ledgers; supervisor/Manager settings; reporting and Excel/CSV/PDF exports; backup/restore and audit.

## Explicit exclusions at launch

- Kitchen printing/tickets/displays/queues, thermal printer adapters, automatic drawer pulse.
- Customer-facing online ordering, e-commerce, public API, real-time cloud synchronization.
- Rider GPS, tracking app, OTP, customer delivery proof/photography.
- Customer points, membership levels or rewards redemption (**FUTURE**).
- Payroll taxation/compliance automation, accounting-bank direct posting, card gateway settlement confirmation.
- Complex multi-location franchise accounting or concurrent multi-register shared-file operation.

## Version roadmap principles

The initial deployment is **one locally owned SQLite database**, on one Windows POS machine. Future LAN terminals, cloud sync or backup uploads must not be simulated by sharing the SQLite db over network filesystems. Preserve domain service boundaries for later client/server move.

## Important terms

- **Business day:** supervisor-defined operating period, can span midnight.
- **Shift:** one cashier's drawer responsibility within a business day.
- **Khata:** supplier account payable; purchases increase payable, payments decrease it.
- **BOM / recipe:** defined ingredient/packaging quantity consumed by a menu item, deal and modifiers.
- **Hold:** editable unsent cart persisted for recall; not yet a committed sale.
- **Committed order:** immutable monetary snapshot with status history and ledger effects.
- **Delivery completion:** physical fulfillment, *not* proof of payment or rider handover.
- **Rider settlement:** cashier acknowledgment of actual rider cash received (manager review only), separate from delivery status.
- **Archive:** hide from new selection while retaining old references and ledger history.
- **Void/reverse:** an attributable compensating event instead of destroying a posted event.

## Localization

PKR and Rs., Asia/Karachi, standard phone normalization for Pakistan (+92 / 03), address fields tuned for areas and landmarks, optional configurable local inventory unit conversions (Mann, Bori, Pao etc.). Do not assume every packaging size has a universal quantity.

## Core nonfunctional goals

No data loss on a sudden process exit or power failure (within configured storage durability guarantees); predictable offline access; bounded transactions; accessible keyboard navigation; clear error recovery; business-friendly audit; migration tests; resilient automatic backup and restore drill; no frontend-only calculation used as financial source of truth.

## Updated end-of-day communication scope (12 Oct 2026)

- Business day finalization MUST create reliable local PDF and XLSX reports. Sending reports over a network is an independent asynchronous process.
- Manager-configured **automatic email delivery** to approved recipients with offline outbox, retries, failure history and manual manager resend is part of the production specification. **Manual WhatsApp sharing** can be included early; **automatic WhatsApp** is a separately configured official provider integration that cannot function without internet, authorized templates/recipient permissions and protected API credentials. See chapter `25`.
- Financial report correctness and visibility for owner is more important than generating superficial charts. Reports must distinguish gross sales, collected money, rider-held cash, supplier liabilities, wage accruals and profit data quality.
- The video comparison and final adopted/excluded features are captured in `23-video-reference-feature-decisions.md`. The exhaustive roles and forms are in `24` and `27`.
