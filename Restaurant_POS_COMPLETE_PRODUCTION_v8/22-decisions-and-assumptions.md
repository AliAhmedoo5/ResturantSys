**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 22 — Confirmed decisions, defaults and unresolved implementation choices

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


Do not confuse recommendations with manager-approved business rules. This file should be maintained during implementation; mark a choice `CONFIRMED` only after the owner decides.

## Confirmed by discussions

| Topic | Decision |
|---|---|
| Device/platform | Native Flutter Windows, offline-first local database direction. |
| Restaurant | Small fast food, delivery-first; takeaway and 3–5 dine-in tables. |
| Kitchen | Physically near cashier; no kitchen ticket, kitchen print, kitchen display/queue in initial release. Cashier records status milestones. |
| Discount | Supervisor-published active/eligible presets always visible to cashier. |
| POS speed | Fixed bill/total, minimal scrolling, hold/recall, phone lookup/repeat, shortcuts configured by owner. |
| Staff | Supervisor and Owner are the SAME Manager role; can create cashier or another Manager; unique 4–8 digit PIN. Managers do not perform cashier operations. |
| CRUD | Manager manages menu, deals, suppliers/custom supplied items, stock, staff/salary, expense categories. No destructive financial deletion. |
| Suppliers | Link products during creation and edits, create arbitrary new supplied item inline, filter purchase by supplier. `No payments` distinct. |
| Delivery | Trips, failed/returned orders, rider cash settlement, separate payment and order status. |
| Inventory | Ingredients + packaging, physical count, wastage, purchase units/Mandi and supplier Khata. |
| Cash | Opening/closing counts, petty cash, category management, shifts and owner reporting. |
| Reports | Wide owner-facing reporting, filters, date ranges, drill-down, exports; accurate gross/net/profit methodology. |
| Loyalty | Points/reward program postponed (FUTURE). |

## Recommended provisional defaults — manager approval required before live transactions

1. **Tender channels (CONFIRMED):** Cash, Card, Raast/Bank, Easypaisa, JazzCash, COD and Split; cashier checks evidence and manually confirms receipt. No gateway/API is required. COD is outstanding until recorded collection.
2. **Tax:** exact rate, tax inclusion, tax treatment of delivery fee, discount allocation and rounding; choose based on business registration and accountant advice. No preset legal rate supplied.
3. **Menu pricing:** effective date rules, manual overrides and price/discount stacking; prevent unauthorized arbitrary cashier price adjustment.
4. **Negative stock (CONFIRMED):** cashier checkout always continues regardless of stock quantity. Record negative stock + warnings; reconcile automatically with future purchases without posting consumption again. Do not implement hard-block toggle.
5. **BOM completeness:** block or warn when an item has no recipe; impacts true profitability and daily operations.
6. **Delivery fee:** flat vs area-based/custom, override authority and whether fee is taxed.
7. **Rider settlement:** whether cashier can hand over partial trips or close shift with rider cash pending, shortage approval thresholds and report ownership.
8. **Cash discrepancy:** blind shift close required; exact flag threshold and who can authorize recount/waive difference.
9. **Supplier advance:** reject overpayment by default or allow supplier credit account; invoice allocations and return credits need accountant agreement.
10. **Payroll:** monthly salary proration method, default pay schedule, wage vs salary, advance recovery timing and payslip requirements.
11. **Inventory costing:** FIFO vs weighted average, purchase overhead allocation, negative stock valuation and initial cost import process.
12. **Mandi units:** default multiplier for Mann/Bori/Dharri/Pao can be configured; Peti/crate MUST be supplier/item-specific. Verify actual regional units with store manager.
13. **Void/refund (PARTLY CONFIRMED):** cashier edits/cancels confirmed orders without manager PIN; all revisions audited. Refund is a separate real-money movement with available-paid-funds ceiling; return funding-source details and prepared-food loss handling require clear policy, not routine manager PIN.
14. **PIN recovery:** locked-out owner recovery method without an insecure master password; reinstall/restore key migration.
15. **Data privacy:** customer data retention, phone sharing/duplicate merging, backup encryption/password and support access controls.
16. **Backup policy:** hourly/daily schedule, local + USB destination, file retention, restore secret handling and whether day-close blocks for unavailable backup.
17. **Operating date:** day close across midnight, business date naming, next day token reset and shift transfer policy.
18. **Dine-in:** 3–5 tables baseline; whether partial payments/open tabs/tables merging are required in phase 1.
19. **Receipt:** digital/PDF initially; whether customer bill printing or drawer hardware gets future release priority.
20. **App branding and installer:** restaurant name/logo/contact, receipt format, deployment path and auto-update policy.

## Explicit future backlog, not part of first release

Kitchen KOT/printers/screens; reward points and membership tiers; rider app/GPS/POD; online ordering/web portal; payment gateway confirmations and bank statement reconciliation integrations; cloud/remote multi-terminal; offline multi-device merge; advanced employee attendance/time clock; supplier EDI; full general-ledger accounting integration and tax filing; hardware ESC/POS cash drawer. These may become scoped later, but must not appear as working first-release features.

## Contradictions resolved against older source docs

- Old `05-hardware-printing-and-drawer.md` and references to kitchen print in old `06-supervisor-order-void.md` are **superseded**. Do not build them now.
- Old `09-supervisor-portal-and-token-queue.md` includes a kitchen token queue. Retain supervisor operations visibility and order statuses but **remove kitchen station and token queue UI** as requirements.
- Old catalog foundation included fixed 4-digit PIN; **current rule is unique 4–8 digit PIN** (secure uniqueness/hash/lockouts).
- Old business day/X report text mentions "printable" reports; use **PDF/Excel/CSV generation** until physical printing is requested.
- Old 6-sheet Excel list remains a minimal compatible baseline; expanded owner reports include more categories and sheets.
- Legacy stock void said automatic BOM reversal; **new safety rule distinguishes unprepared from cooked/consumed food**, with explicit disposition/wastage.
- HTML frontend prototype simplified supplier, stock, financial, PIN and payroll flows. Production behavior is defined here, not inferred from its JavaScript state.

## Open decision workflow

For each unresolved topic, add: owner question, options with tradeoffs, selected option, date, approver, linked module/requirement IDs and tests. Until confirmed use explicit "provisional" defaults in test environment only and do not invent local compliance requirements or gross profit figures.

## New report-delivery decisions requiring manager approval

- **Email provider:** Choose supported SMTP relay or transactional email provider, sender domain, maintenance owner, credential storage/relay and cost limits; default recommended email enabled after configuration and verified recipients.
- **Recipient management:** Decide manager-only approved list (recommended), supervisor manual resend to approved contacts, whether finance/payroll details may be distributed and retention/access encryption policy.
- **WhatsApp:** Decide manual share initially vs automatic official WhatsApp Business Platform now; automatic needs business setup, approved templates as applicable, consent, provider, reliable token management and internet.
- **Offline/background delivery:** Decide local worker only (sends after POS/service runs again) versus cloud relay when always-on delivery even with store PC off is required.
- **Report content:** Approve executive summary template, recipients by role, attached PDFs/XLSX, personally identifiable data redaction and external access policy. These are user-requested features but provider-specific setup choices remain provisional.
- **Backup/report retention:** Decide number of days to retain generated reports and queued messages, storage location and encryption, especially because reports contain financial data.


## v6 decisions now fixed (do not keep unresolved)

1. **Cash rounding** nearest whole rupee, half-up on final cash portion, digital exact paisa and signed adjustment ledger, Chapter 32.
2. **Default tax configuration** TAX_INCLUSIVE + 0% until Manager configures legally applicable tax; actual rate remains deployment-specific.
3. **Tokens** strictly monotonic within day; canceled tokens never reused.
4. **Wizard** requires separate primary Cashier with unique 4-digit PIN after Manager; guided day/shift opening.
5. **Modifier exclusivity** enforced by SINGLE radio groups and conflict validation.
6. **Order edit lock** cashier can edit pre-settlement Preparing/Ready/Out for Delivery without PIN; rider Settled locks cart and only refund/adjustment documentation remains.
7. **Cash movements** `approved_by` nullable for routine cashier pay-in/out.
These decisions supersede earlier entries labeling these topics provisional. Actual taxes/registration remain a deployment requirement.


## Confirmed 18 October 2026 (v7)

- **Optional menu and deal pictures:** Manager may upload multiple pictures per menu/deal; encouraged, not mandatory. Publish still requires a complete valid recipe. Offline local media storage.
- **Cart-first customer details flow:** Cashier selects items, then customer details sheet, then payment and final transactional confirmation. Intermediary button is `Continue`, not irreversible order confirmation.
- **Manager-controlled serviceable areas:** Manager has CRUD/disable/fee configuration for delivery areas. Cashier can only select an available area. Delivery address and area fee snapshot persist on confirmed order.
- Earlier notes suggesting customer details are captured *after an already committed sale* are superseded. For an existing confirmed sale, customer corrections are audited order amendments and abide by rider-settlement lock.
