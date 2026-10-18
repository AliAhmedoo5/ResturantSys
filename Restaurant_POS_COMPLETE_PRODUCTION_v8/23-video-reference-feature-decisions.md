**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 23 — Original POS video: feature-by-feature decision register

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


**Source:** user-provided approximately 118-second Windows restaurant POS demonstration (`1000958782.mp4`), reviewed alongside the subsequent requirements conversations. **Purpose:** distinguish UI inspiration and adopted capabilities from elements explicitly removed. The original software is a reference, not a blueprint to clone. Observations describe what was visibly demonstrated, not assumptions about its internal database or business rules.

## 1. What appears in the reference video, and what the real product must do

| Video UI/behavior | Real-app treatment | Detailed implementation decision |
|---|---|---|
| Category tabs: beverages, broast, burgers, deals, promotions | **ADOPT + REDESIGN** | Custom supervisor-managed categories, ordered tabs, search, active/hidden items, compact tiles; no fixed category list. |
| Product tiles with pictures | **ADOPT + REDESIGN** | Optional images; strong readable text and price without images. One-click add for basic item, one concise choice dialog only if necessary. |
| Itemized current order with quantity, rate and totals | **ADOPT** | Sticky right-side cart on 1366×768; quantity ±, edit modifiers, remove before save, running tax/discount/fee and grand total, no routine scrolling for ordinary bills. |
| Quantity more than one, previous/next selection | **ADOPT CONCEPT** | Direct quantity change and fast keyboard navigation; no mandatory paginated catalog if search/filter better. |
| Dine-in, takeaway, delivery selection | **ADOPT** | Delivery-first with saved customer and address, takeaway, 3–5 dine-in tables; packaging BOM per mode. |
| 10% and 20% discount buttons | **ADOPT + EXTEND** | Supervisor CRUD active discount definitions; cashier always sees all active eligible presets. Percentage, flat amount, rules, validity, max cap, per-line/whole-order applicability, stacking and audit. Do not hardcode 10/20. |
| Payment numpad, amount received and change | **ADOPT + IMPROVE** | Keyboard-first tender, quick denomination presets, exact cash, large change, explicit underpayment prevention, card/bank/wallet/COD/split with configured verification. |
| History / recall controls | **ADOPT + EXTEND** | Search previous completed orders and create a new repeat-order cart; separate hold/resume draft flow with ownership, timestamps, conflict rules. Never overwrite a historic order. |
| Refund and void buttons | **ADOPT WITH APPROVAL** | Role/amount/state-authorized void and refund workflows; record reason, approval, tender, finance and stock disposition, with reversal events. |
| Select server/employee screen | **ADAPT** | Session tied to authenticated staff and shift; optional order attribution to employee/rider/table. Never use superficial server selection as authorization. |
| Store button | **NOT ASSUMED AS MULTI-OUTLET** | Single restaurant release. Interpret store-wide operational mode only after clarification; multi-branch architecture and cloud sync future. |
| Promotions | **ADAPT** | Supervisor-managed combo deals and eligible discount programs; loyalty/reward points explicitly future. |
| Kitchen docket and ticket/print dialog | **EXCLUDED** | Kitchen one meter from cashier: no kitchen ticket, KOT, printing, kitchen tablet or kitchen ticket queue in initial release. Keep order status milestones manually managed for timing analytics. |
| Receipt printing preview | **REPLACED IN INITIAL RELEASE** | Digital receipt or saved PDF/export. Physical receipt printer and drawer pulses future integrations only. |
| Bright multicolored buttons and dense tiny grids | **REJECT AS VISUAL STYLE** | Use v8 Street-Food / Mafia brand: obsidian `#050708`, navy `#101820`, yellow `#FFC400`, gold `#F5A623`, slate cards `#14242D`, legible off-white text `#F5F7FA`; simple readable operations remain the priority. |

## 2. Subsequent additions not merely copied from video

These are first-class production requirements because the user explicitly requested them in later discussion:

1. Phone-based customer search, multiple addresses and quick repeat order creation.
2. Hold and recall with ownership and stale-cart validation.
3. Manual delivery lifecycle and rider trip grouping with cash handovers and shortages.
4. Failed delivery, returned order, retry/redispatch and financial/stock dispositions.
5. Ingredient **and packaging** consumption linked to recipes, modes and deals.
6. Opening float, physical counted cash, blind shift handover, discrepancies, petty cash and custom expense categories.
7. Order-delay alerts and supervisor exception views without kitchen tickets.
8. Physical stock counts, manager approval and movement-safe adjustment posting.
9. Staff salary, advance, partial payments and balance/history; PIN-equipped POS roles separate from payroll.
10. Supervisor/owner CRUD for catalog, menu categories, modifiers, prices, deals, discounts, inventory master, supplied items, suppliers, expenses/categories and staff.
11. Supplier-specific catalog of items they provide, including custom inventory products created during supplier creation; purchase form auto-filters and validates relationship.
12. Vendor Khata with supplier invoices/credit deliveries, payment source distinctions and status **No purchases / No payments / Partially paid / Paid**.
13. Traditional local purchase units where configured, exact base-unit conversions and weighted/FIFO costing per approved policy.
14. Owner-configured global/role keyboard shortcuts and quick-action toolbar; no permission bypass.
15. Unique 4–8 digit PIN per active cashier/supervisor/Manager account; supervisor may create cashier/supervisor accounts; manager-only Manager privilege.
16. Rich owner reports with drill-downs, trends, exports and metrics backed by correct ledger definitions.
17. End-of-business-day Z-report + Excel/PDF and **email and/or WhatsApp** delivery, with local offline queue and authorized resends.
18. Explicit feature flags: disabling a feature never erases posted history.
19. Future loyalty/reward points, future physical printing, future kitchen infrastructure, future multi-terminal/cloud features.

## 3. Video-related end-to-end cashier scenario

1. PIN unlock → cashier opens/resumes approved shift → billing screen immediately ready.
2. Choose Delivery/Takeaway/Dine-in using one visible segmented control. For delivery, search phone and choose address; for dine-in, table.
3. Tap a category or type search text; product tiles show name, optional image, price and assigned hotkey. Add product with one tap; edit quantity instantly. A deal opens only the required selector.
4. Subtotal, discounts, delivery fee, applicable taxes and total update immediately. Active preapproved discounts stay visible.
5. Tap Pay (or owner-configured shortcut); select cash/card/bank/wallet/COD/split. Show received amount and exact change. No second confirm if it was already saved.
6. Atomically create unique order, tender/payment state, order status event, BOM and packaging inventory movement, token and audit record. Offline transaction completes without internet.
7. A separate status action handles preparation and delivery, since **no kitchen document is produced**. Receipt PDF optional, not necessary to finish billing.
8. Next bill starts with focus back to search/category. The entire cycle should require minimal clicks and no routine vertical page scroll at typical Windows workstation resolution.

## 4. Explicit nonrequirements and unresolved details

- Do not implement a KOT because one appears in the video. Do not promise an integrated live payment gateway just because the video contains a payment button.
- Do not assume the original program's printed tax percentage, currency configuration, hardcoded discount validity or order number structure is the desired production policy.
- No rider tracking GPS, proof-of-delivery uploads, loyalty accrual, automated restaurant marketing, enterprise branch management or cash drawer hardware in initial release.
- The video is not proof of correct accounting, privacy, backup, concurrency or fulfillment handling. The new application's domain workflows and automated tests take precedence.

## 5. Acceptance traceability

- **VID-01:** On 1366×768, create a basic takeaway bill without vertical page scrolling; search/add/change quantity and pay by keyboard.
- **VID-02:** Cashier cannot edit active preset values, only select eligible ones; supervisor changes flow to cashier at next render and across restart.
- **VID-03:** Hold/recall retrieves a separate unsaved draft; history/repeat clones a historic order into a **new** draft.
- **VID-04:** Confirming a delivery order produces zero KOT/printing jobs yet correct status and inventory ledger entries.
- **VID-05:** Refund/void attempts from cashier require supervisor approval and show exact source/stock effects before posting.
- **VID-06:** Cart, tender and receipt display distinct statuses; no misleading claim that card/QR is paid without confirmation.
