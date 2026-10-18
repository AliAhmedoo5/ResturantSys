# Restaurant POS & ERP — Complete Production Specification v8

**Authoritative production specification · 18 October 2026**

The v8 visual theme is the Street-Food / Mafia brand in Chapter 34. Chapters 30–33 remain authoritative for role-independent order revisions, stock, payment simplification, mandatory recipes, final engineering decisions, customer/address/delivery area workflow, and optional menu/deal images. Read `README.md` and `AGENTS.md` for implementation order.

## Contents

- **00** — 00 — Product charter, boundaries and glossary
- **01** — 01 — Roles, capabilities, access rules, and cross-module policies (v4)
- **02** — 02 — Complete operating workflows and state machines
- **03** — 03 — Staff, departments, PIN authentication, salaries and advances
- **04** — 04 — High-speed cashier POS, billing, discounts, payments and shortcuts
- **05** — 05 — Menu, categories, deals, modifiers and recipe/BOM
- **06** — 06 — Customers, phone lookup, delivery addresses and repeat sales
- **07** — 07 — Delivery lifecycle, rider trips, failed/returned orders, cash settlement
- **08** — 08 — Inventory, stock ledger, packaging, low stock, wastage and counts
- **09** — 09 — Supplier CRUD, custom supplied products, purchases, payments and Khata
- **10** — 10 — Business days, shifts, drawers, expenses and reconciliation
- **11** — 11 — Orders, cancellations, voids, returns and refunds
- **12** — 12 — Comprehensive reporting and owner analytics
- **13** — 13 — Supervisor portal, Manager settings, feature flags and approvals
- **14** — 14 — Screen-by-screen UI/UX specification for the REAL Flutter Windows app
- **15** — 15 — Production architecture, offline operation and deployment
- **16** — 16 — Logical Drift/SQLite data model and constraints
- **17** — 17 — Financial integrity, event accounting, audit and invariants
- **18** — 18 — Security, privacy, backups, recovery and reliability
- **19** — 19 — Automated tests, user acceptance and release criteria
- **20** — 20 — Development milestones, dependencies and definition of done
- **21** — 21 — Owner report formulas and metric dictionary
- **22** — 22 — Confirmed decisions, defaults and unresolved implementation choices
- **23** — 23 — Original POS video: feature-by-feature decision register
- **24** — 24 — Exhaustive role permissions matrix (v4)
- **25** — 25 — Automatic and manual end-of-business-day report delivery (email / WhatsApp)
- **26** — 26 — Complete feature catalog, user handbook and cross-module behavior
- **27** — 27 — Screen-by-screen contract: fields, roles, actions and validation
- **28** — 28 — State machines, financial postings, invariants and failure recovery
- **29** — 29 — Comprehensive acceptance walkthrough, role-based scripts and release verification
- **30** — 30 — FINAL AUTHORITATIVE BUSINESS DECISIONS: cashier amendments, perpetual stock, and manual tenders (v4)
- **31** — 31 — Final mandatory recipe and simplified payments policy (v5)
- **32** — 32 — FINAL ENGINEERING DECISIONS: post-confirmation lock, cash rounding, tax defaults, tokens, onboarding, modifiers (v6)
- **33** — 33 — Confirmed final workflow, delivery zones, and optional menu/deal images (v7)
- **34** — 34 — Final visual theme: Street-Food / Mafia Branding (v8)

---


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


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 01 — Roles, capabilities, access rules, and cross-module policies (v4)

## Definitive model

Exactly **two POS login roles**: **Cashier** and **Supervisor/Owner (Manager)**. Supervisor and Owner are **the same single authorization role**; they must have precisely the same access. Kitchen employees and riders may exist in the staff directory without an application login. Departments/job titles never grant capabilities.

**Hard separation of duties:** Manager is administration/oversight/approval, **not a cashier**. Manager cannot create or edit a customer's live cart, take/confirm a checkout payment, apply a discount to a checkout, hold/recall cashier drafts, begin a cashier shift, submit a cashier's blind count, or update preparation/delivery progress as cashier. Manager can view records, configure rules, approve controlled exceptions, and correct via audited management workflows. Manager can open/close business days and manage financial accounts, expenses, Khata, supplier payments, payroll, reports and report delivery; these administrative financial operations are not cashier checkout.

## Permissions

| Action | Cashier | Supervisor/Owner (Manager) |
|---|:---:|:---:|
| Login with own unique PIN, lock own session | Yes | Yes |
| Create/hold/recall/edit a live customer order and cart | Yes | **No** |
| Select payment methods, take tenders, finalize bills | Yes | **No** |
| Search phone/customer for **live billing** | Yes | **No** |
| Apply a published eligible discount to a bill | Yes | **No** |
| Create/edit/disable published discount definitions | No | Yes |
| Update preparing/ready/dispatch/delivered/failed state | Yes | **No** (view only; exception approval allowed) |
| Assign rider trips and record rider handover from counter | Yes when configured | **No** (oversight/approval only) |
| Open own cashier shift, count/submit blind shift close | Yes | **No** |
| View all shifts, review/approve discrepancies | No | Yes |
| Open or close business day and generate Z-report | No | Yes |
| Manage menu categories/items/modifiers/recipes/deals | No | Yes |
| Manage inventory, packaging, counts, wastage | No | Yes |
| Manage suppliers, supplied-item catalog, purchases, Khata | No | Yes |
| Manage staff, salary, advances and active account status | No | Yes |
| Create/reset/deactivate cashier or manager PIN | No | Yes (manager action requires reauthentication + audit) |
| Manage expense categories CRUD | No | Yes |
| Post administrative petty cash, management adjustments | No, unless expressly cashier expense entry permitted | Yes |
| Manage global keyboard shortcuts / quick-action toolbar | No | Yes |
| Manage feature flags, security, backups, report destinations | No | Yes |
| View broad finances/profit, full management reports | No | Yes |
| Email/WhatsApp report configuration and sending | No | Yes |
| Edit or cancel already-confirmed order (reason + audit) | Yes, no Manager PIN | No (read-only oversight) |
| Record supported collected-funds refund with strict ledger checks | Yes, no routine Manager PIN | No (read-only oversight) |
| Review cashier amendments, cancellations and refunds | No | Yes |
| Delete audit history or silently edit posted ledger | Never | Never |

## PIN policy and account security

- 4–8 digit unique PINs for all PIN-enabled accounts; check uniqueness atomically against an installation-keyed fingerprint, verify with a slow PIN hash; never store plaintext.
- First Manager credential created through guarded onboarding; no universal default PIN. An authenticated Manager can create another Manager (same role, same rights), but requires reauthentication, explicit high-risk confirmation and an audit event.
- Managers create and revoke Cashier/Manager accounts; PIN reset requires a new PIN, never reveals an old one. Failed-attempt throttles, session locking and credential revocation persist.
- Supervisor approval overlay authenticates manager PIN temporarily **without converting the cashier session into a manager cashier session**. Denied approval changes nothing.

## CRUD and accounting semantics

- Managers have full master-data CRUD for catalog, deals, discounts, inventory items, supplied-item mappings, supplier profiles, expense categories, staff profiles and configuration.
- Delete master records only when unused and unrelated to any historical ledger; otherwise archive and keep references intact.
- Financial/stock postings (cash movement, purchase, payment, salary, refunds, adjustments, stock consumption) are immutable. Correct via linked adjustment, reversal or documented refund with reason, actor, timestamp and optionally approval; never erase posted entries.
- Immutable order-line snapshots ensure catalog price edits cannot alter historical bills.
- Expense categories used by an expense cannot hard-delete, but can archive and be hidden from future selections.
- Setting changes persist and are audited. Shortcut dispatch and background execution re-check role permissions in the domain layer.
- No Manager shortcut can open POS/checkout screens. No cashier shortcut can execute privileged management actions.

## Business-day distribution

- Manager owns approved email/WhatsApp recipients, provider credentials, report formats/filters, auto-send policy and manual send/resend to approved destinations.
- Cashier cannot generate/distribute the full confidential Z-report. Closing business day succeeds offline; reports are saved locally, and delivery jobs remain pending until internet/provider available.
- Sending status and retry history are auditable; duplicates prevented by stable business-day/recipient/document/version/channel keys.

## Acceptance

1. Manager PIN login displays **management navigation only** and rejects POS create/checkout via direct commands and hotkeys.
2. Cashier PIN login displays **cashier operations only** and rejects stock, catalog, supplier, payroll or shortcut settings via direct commands and hotkeys.
3. Manager creates another Manager; both have identical permissions. There is no Owner permission tier or elevation pathway.
4. Cashier revises or cancels confirmed order without Manager PIN; immutable audit and correct stock/payment delta are mandatory. Manager may review exceptions afterward.
5. Cashier closes their shift blindly; Manager reviews discrepancy, then closes business day and distributes report.
6. Manager can CRUD expense categories and menu/deals, and manage supplier-specific custom stock, without being able to ring up a sale.


---


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


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 03 — Staff, departments, PIN authentication, salaries and advances

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Staff master [STA-01…08]

- [STA-01] Manager can create a person with name, staff code, phone (optional), department, employment date, active flag, salary scheme and optional POS role; validate unique staff code and mandatory name.
- [STA-02] Editable fields: name/contact/department, pay rate, start/end date, status; all changes versioned with actor/time. Salary effective dates prevent retroactive edits to closed payroll periods.
- [STA-03] Archive/deactivate instead of hard deleting any staff referenced in sales, approvals, cash, inventory or payroll. Only truly unused staff can be hard deleted with confirmation and log.
- [STA-04] A person can belong to any custom department but only their assigned authorization role controls app privileges. Kitchen/rider employment without PIN is allowed.
- [STA-05] Staff detail tabs: Profile, POS Access, Salary & Advances, Payments, History. Search by name, role and department; filter active/archived.
- [STA-06] Deactivation immediately invalidates local active sessions and prevents future privileged approvals.
- [STA-07] Changing an employee's system role is independently audited from changing department or salary.
- [STA-08] Include date/actor in all salary, advance and staff credential changes; show no sensitive PIN value in UI.

## Credentials [PIN-01…08]

Create Cashier or Manager POS credentials at staff creation or later. PIN is 4–8 numeric digits, entered twice, unique across all active login credentials. Duplicate attempt shows generic "Choose another PIN"; it must not expose the matching staff member. Manager may create/edit Cashier and Manager PINs; Manager account creation requires reauthentication and audit. No Owner tier exists. Manager reauthentication required for high-risk Manager credential changes. Credential rotation invalidates target sessions. Wrong attempts throttle per staff candidate/device; lockout and recovery follow Manager-managed security policy. Never put raw PIN in memory beyond the shortest practical verification scope. Password/PIN KDF and fingerprint policy in Security document.

Do **not** simply put UNIQUE on a plaintext PIN column. Use a keyed equality fingerprint for collision detection and a separate rate-limited salted verifier. The installation key belongs in Windows DPAPI, not SQLite or export.

## Payroll configuration

Support salaried employee baseline and optionally daily wage/shift wage as configurable schemes (the latter may be phase 2 if not needed at launch). Employee pay terms have effective-from date, PKR rate and manager who approved. Payroll period has start/end business date, employee snapshot, gross earning, adjustments/advance deductions, total payments and remaining liability.

### Ledger model [PAY-01…10]

- **Salary earned** creates liability for employee; **advance paid** creates employee recoverable; **salary payment** consumes available salary liability; **advance deduction** reduces recovery balance and salary liability but does not spend cash again.
- A cash-funded salary payment or advance posts one drawer pay-out and one employee-ledger event in the same transaction. Bank/owner funded payment never modifies register cash.
- Manual recurring salary accrual must be idempotent by `(employee, period, component)`. Support partial payments and multiple advances in the same period.
- An advance should not simply be subtracted from "gross salary" historically; present it separately as an already-paid recoverable balance and explicit settlement allocation.
- If employment terminates mid-period, prorate based on configured rule; no hardcoded 30-day monthly divisor without manager approval.
- Manager can record pay/advance under policy and view all payroll and history. Any post/void/reversal requires reason and audit.
- Disallow negative salary/advance amounts and overpayment without explicit staff-credit/loan policy.
- Advance write-off, benefits, deductions and legal payroll compliance are explicit later policies, not magic numbers.
- Financial reports separate gross pay expense, outstanding payables, cash paid and advances; do not count payroll paid as another expense if already accrued.

## UI flows

**Add staff:** Staff → Add → name, department, pay → optional POS login toggle → role → PIN and confirm → validate uniqueness/role → save → profile appears with `Login active` status and no PIN exposure.

**Edit staff:** Staff → search → detail → edit authorized fields; salary changes ask effective date. Role change triggers explicit privilege confirmation. Reset PIN with mandatory reason and authorization.

**Pay salary:** Staff → salary ledger → select period → show earned, paid, advances, recoveries, due → enter amount, funding source and note → confirm → cash/payroll entries atomically saved; receipt reference shown.

**Advance:** employee → New advance → amount/source/reason/date → post → shows outstanding employee advance and corresponding funding outflow.

## Edge cases

Duplicate PINs including deactivated? Default: disallow reuse among active credentials; retention policy should block recently retired PIN reuse as extra protection. Supervisor tries to create owner → denied. Cashier attempts role-switch via UI/backend command → denied. Deleting a staff member with cash movement → offer archive. Salary change during approved period → new effective period or correction record. One cash payment accidentally re-submitted → idempotency prevents duplicate.

## Acceptance tests

- Create cashier and supervisor with different PINs; both login and land on appropriate permitted workspace.
- Duplicate PIN across roles rejected; stored raw PIN absent from SQLite export/logs.
Manager (Supervisor/Owner) is the only management role, with identical permissions for both titles; Manager can administer and approve but cannot perform cashier tasks. See chapters 01 and 24.
- Staff with history cannot hard delete; archived remains visible in ledger and reports.
- Salary accrual, advance, salary payment and deduction each appear once and reconcile to cash source.
- Rotate PIN then old session and PIN fail appropriately.


## v6 compulsory cashier setup

First-run wizard MUST create initial Manager, then require a separate enabled Cashier with unique **4-digit PIN** (later staff PINs can follow 4–8 policy) before completing initial setup. After Manager opens business day, switch to Cashier session, record opening shift float and then enable sales. Do not give Manager cashier access even during wizard.


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 04 — High-speed cashier POS, billing, discounts, payments and shortcuts

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Absolute interaction priority

A trained cashier should complete a standard order on a 1366×768 Windows workstation **without vertical page scrolling or switching to a management page**. Normal workflow: select dining type/customer, tap/search item, optional discount, payment/confirm. Fixed cart, total and primary action remain visible. Use keyboard/numpad and mouse. Keep the default workspace distraction-free: no charts, owner metrics or irrelevant notifications.

## Layout [POS-01…08]

- Header ≤64px: operator, shift, business date, local/offline status, lock; not a scrolling navigation region.
- Product space ~62–65%, cart ~35–38% (minimum ~340px). Category chips, large product tiles, compact search + barcode-like quick code support if configured.
- Product click increments quantity immediately for straightforward items. Deals and required modifiers open a compact keyboard-accessible choice sheet only when necessary.
- Fixed cart: rows, `+/-`, edit options, remove, subtotal, discount, tax display, delivery fee, **large total**, **Checkout** and **Hold**. Long carts scroll within cart only, total and charge button remain pinned.
- Use `F2` new cart, `F3` hold, `F4` recall, `F5` customer lookup, `F6` discount, `F7` confirm, `Ctrl+K` search as suggested defaults, **not mandatory hardcoded bindings**.
- Avoid nested modal chains; keep overlay count to one. Return keyboard focus after closing.
- Touch targets ≥44–48px; searchable tabs; keyboard focus ring; screen usable at 100%/125% Windows scaling.
- Cashier view must be role- and feature-aware, with no supervisor settings or PIN values.

## Cart model [POS-09…17]

Each cart line holds product/variant/deal selection, modifiers, qty, human-readable instructions, unit price snapshot preview and applicable recipe components. A deal is one sale line composed of its chosen items and upgrades; never multiply both parent deal and child prices incorrectly. Store individual item pricing and composition snapshots at commit. Changing product availability while cart open triggers validation at checkout; show clear choices, never silently alter price.

Order modes: Delivery (address, area, phone, delivery fee and COD), Takeaway, Dine-in (table number, 3–5 tables configurable). Separate discount from delivery fee unless preset explicitly allows it. Supervisor can make a percentage or flat PKR preset with active dates, allowed modes, minimum spend, product/deal restrictions and stacking policy. Active eligible discounts **always appear to the cashier** and remain after restart. If discount becomes invalid before checkout, explain the reason and ask cashier to pick another, not silently discount wrong amount.

## Customer lookup and repeat [POS-18]

Phone input normalizes +92/03; exact lookup is immediate with suggestions for repeated customers. Selecting result populates name, address options, area, landmarks and order history. Repeat order copies prior choices to editable draft but **re-evaluates current catalog availability, current prices and applicable discounts**; never assert the old price remains valid. No exposure of customer phone/address in unrelated reports or external exports by default.

## Hold and recall [POS-19]

Hold stores draft and cart lines transactionally with owner/session, source workstation, creation time, optional expiry, customer context and retained deal choices. Recall has searchable list; locked editing prevents two active users editing same draft concurrently. Held carts are not paid orders, do not consume stock, do not allocate sale token and do not enter revenue. Abandoned holds can expire/require supervisor clean-up without losing audit metadata.

## Payments [POS-20…30]

Configurable Cash, Card, Bank/Raast, Easypaisa, JazzCash, COD and Split. Store payment channel, optional reference, cashier-confirmed status and evidence notes. All tenders are manual: the cashier selects the actual payment method and records the received amount (checking customer payment outside the application as ordinary cashier practice); the POS does not initiate or verify external transactions. **No payment provider API, gateway, webhook or bank integration is a prerequisite.** The system records the cashier action and method; it must not show API-style verification/processing states. Cash tendered must cover cash component; calculate change exactly, display in prominent type, never allow negative change. Split tender amount summed exactly to payable with safe paisa rounding; remaining amount must be zero before paid confirmation. Cash drawer movement only for actual cash collected/returned. COD is a receivable; dispatched/delivered order may still be unpaid.

Commit transaction contains order, lines, taxes/discounts, ordered time, actor, business day, payment allocation, inventory events, packaging events, order number/token and idempotency key. Repeat taps, app crash or navigation retry cannot duplicate order. Persist first and show success after commit. Disconnected devices cannot block SQLite-local billing. No receipt printer requirement; optional digital receipt generation can fail/retry independently after save.

## Shortcut manager [POS-31…36]

Manager can create global/role shortcut profiles and ordered quick-action toolbar. Actions from registry (`new_order`, `hold`, `recall`, `customer_lookup`, `product_search`, `apply_discount`, `checkout`, `cash_tender`, `orders`, `rider_dispatch`, `expense`, etc.). Validate duplicate bindings within a context, reserved OS combinations, unsupported contexts and modifiers; show conflicts before save; ability reset to defaults and test bindings. Never trigger while typing in input or PIN field. Disabled/unauthorized actions remain blocked from keyboard invocation. Labels or tooltips display active shortcut values. Map changes applied to new sessions/current appropriate context safely and audited.

## Validation / errors

- Active shift and open business day required to post cashier sale; drafts can be retained if shift ends, with ownership policy.
- Empty cart, nonpositive item qty, duplicate unsettled confirm, unavailable product, missing required deal choice, invalid discount, split under/overpayment and delivery address validation show local inline messages.
- If stock is zero/negative/insufficient, **always allow checkout** and post complete stock consumption exactly once. Record negative balances and alerts; later receiving stock adds to the negative balance, never deducts the same deficit again. No blocking low-stock feature flag.
- Never erase cart on failed payment/DB commit. User sees retry and same idempotency context.
- Menu price edits mid-order: before commit show price changes; after commit old order never changes.

## Acceptance

Create basic bill with ≤3 deliberate item/tender interactions after entry; scroll test at 1366×768; hold/recall after app restart; repeat customer with newly inactive item warns; cashier always sees active eligible supervisor discount; expired/noneligible discount hidden or disabled with reason; payment split validation and change math exact; duplicate submit creates one order and one stock posting; changed shortcuts work and respect PIN/modal input focus; COD delivered without being considered paid.

## v5 payment-screen simplification

No `unverified`, `processing`, `awaiting provider`, `manually confirmed` badge or API-status tag in cashier UI. After selecting Cash/JazzCash/Easypaisa/Bank-Raast/Card and confirming, show a normal paid sale. Optional transaction reference is informational. COD remains unpaid/collection-due, and split indicates remaining balance. Backend still writes cashier, timestamp, method and ledger entry; these are audit facts, not additional cashier verification steps.


## v6 Cashier payment and order locking

Complete cash tender rounds final cash-due remainder **once** to nearest whole rupee; digital stays exact integer paisa; signed cash rounding delta posted separately, see Chapter 32. Tax-inclusive pricing defaults to 0%; never add tax on top of configured shelf prices by default. Confirmed cashier revisions permitted Preparing/Ready/Out for Delivery until rider trip Settled; after settlement direct cart changes locked (refund/adjustment or new order instead), without routine Manager PIN.


## v7 — Cart → Customer → Payment → Commit (authoritative order-entry flow)

The cashier must first select menu items/deals, quantities and modifiers into an **uncommitted cart**. The primary action is **Continue — Customer**, NOT `Confirm Order` or an irreversible confirmation. Display a customer-details sheet/step next with order type. For delivery, require customer name, normalized phone, delivery area chosen from Manager-configured currently serviceable areas, address details and optionally landmark/instructions. On entering phone, match existing customer(s); cashier can select stored address or create another. Customer identity and selected address are linked to the order at the final save. For takeaway/dine-in, only relevant fields may be optional or skipped. If delivery area unavailable, prevent final delivery confirmation with visible guidance to change area or order mode; do not lose cart.

Next show simple manual payment methods/COD, full amount including area fee, and **Complete Order**. The *database order, business-day token, full recipe+packaging ledger debit, payment record and customer link* all commit in one atomic transaction at this final step. Before this stage, cart/customer details are mutable draft state and can be held/recalled; no daily token or inventory deduction is allocated. Once confirmed, v6 cashier amendment/no-PIN and rider-settlement-lock policies apply. Use a compact dedicated customer drawer or modal, not a long scrolling POS form. Returning customer saved details are suggested, never silently overwrite current order fields.


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 05 — Menu, categories, deals, modifiers and recipe/BOM

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Supervisor/owner CRUD [MENU-01…12]

**Menu categories:** name, display order, color accent (optional), active status; supervisor can create/read/edit/archive/delete unused. If category contains historical items, archive/reassign rather than hard delete.

**Menu items:** unique item code/SKU, display name, description, parent category, price PKR, optional tax-inclusive configuration, availability, menu display order, unit, optional icon/photo, variant group, recipe version, tags and source. Price cannot be negative. Keep time-stamped effective price history and commit-line snapshots; edits do not rewrite historical sales.

**Deals:** deal code/title, active/effective-from/to, fixed/base price, required and optional selection groups, min/max selections, included quantities, upgrade delta prices, products allowed in group, mode restrictions, customer-facing description and recipe expansion. Deal components must map to ingredients/packaging reliably, preventing duplicated deductions. Updating a deal creates a revision; old orders retain exact chosen selections and applied discounts. Supervisor can create/read/edit/activate/archive; unused draft may hard delete.

**Modifiers:** `Add cheese`, `Extra sauce`, `No mayo`, size upgrades; price delta, recipe delta (including explicitly zeroing a component), allowed item/categories, min/max and required state. Validate contradictory options (e.g., No Mayo + Extra Mayo handling rule), option multiplicity and decimal quantities.

**Recipes:** BOM for product and modifier, ingredient quantity in normalized base units, yield/portion assumptions, waste allowance only if explicitly configured, version number, effective date and estimated cost derived from chosen costing strategy. Recipes may use raw ingredient, intermediate prepared item and optional packaging. Detect recursive composition cycles.

## Catalog data flow

1. Manager creates Category → Menu Item → optional variants → **mandatory complete recipe/BOM** → modifiers → activation. The item can be saved as an inactive draft without a complete recipe but **cannot be activated, published to the cashier or sold** until recipe validation succeeds.
2. Deal builder selects existing sale items or choice groups and quantities, optional upgrades; preview customer price and exact expanded raw ingredient totals.
3. Validate all recipes, every variant/size, selected deal component and applicable packaging rule. Missing purchase-cost history may show estimated COGS unavailable but does not excuse a missing recipe.
4. Activate; cashier tile/category listing updates from local persisted store. Inactive item disappears from **new sale selection**, but appears in old orders and reports.
5. Price edit or bundle revision is audited with actor, before/after and effective timestamp; in-flight drafts validated at checkout.

## Deal rules [DEAL-01…08]

- A deal may include nested menu choices but **deal nesting or cycles prohibited by default** for initial implementation.
- Required choice groups must be fully selected; optional groups may be empty. Use exact bounded quantities.
- Selling price is deal base + valid option upgrade deltas - eligible discount. Included choices must not be charged twice.
- COGS/stock consumption decomposes deal into actual selected item/variant recipes once.
- Mixed product availability: active deal becomes unavailable if mandatory item group has no valid selection; explain to supervisor and cashier.
- If a component is edited/archived, flag affected active deals for review; do not silently replace a required component.
- Deal discount stacking controlled by explicit rules, not free arithmetic.
- Owner reports must aggregate deal as a sale line **and** decompose ingredients for stock/cost, without double-counting revenue.

## Inventory integration [BOM-01…07]

On committed order, create one inventory event per raw ingredient/packaging consumption (or batched deterministic ledger lines with order/line reference). Hold/draft does not deduct stock. **A sellable menu item or deal MUST have a complete, validated BOM: there is no supervisor override, temporary-sale exemption or incomplete-recipe publication.** If a component is intentionally non-stock-bearing, record an explicit `non_inventory_component` declaration and manager reason, not an empty/missing recipe. Inventory QUANTITY can nevertheless be zero/negative without blocking checkout; complete consumption is posted exactly once. Wastage and post-cooking cancellations are separate consumption decisions. Unit conversions dimensionally safe: grams↔kilograms, ml↔litres, count↔dozen; arbitrary crates require per-item conversion.

## Examples / edge cases

- **Family deal:** two burgers, one large fries, 1 drink chosen from Cola/Water; Cola upgrades Rs.20. Store selected drink, burger variant and price composition. Deduct buns/patties/sauce, fries potatoes, drink inventory and delivery packaging where configured.
- **Extra cheese:** adds price and cheese stock exactly once; **No mayo:** removes configured recipe usage without negative sales line.
- Historical order contains item now archived: still display item snapshot and can be refunded according to original tender.
- Supervisor changes price after cashier placed it in held cart: preview discrepancy and prompt explicit confirmation before billing.
- Manager deletes an active ingredient referenced by recipes: deny permanent deletion; allow archive only after replacements/recipe validation.

## Acceptance tests

CRUD category/menu/deal/variants, dynamic cashier visibility, deal required-choice validation, mandatory BOM on every activated item and deal (including all selections), upgrade pricing, deal recipe decomposition, historic price immutability, archived references, negative-stock warn-and-allow and no double consumption.

## Mandatory recipe gate and deal expansion — confirmed v5

The Manager cannot make an item or deal **sellable** without a saved, versioned and complete recipe. A draft can be saved for later completion; `Activate`, `Publish`, `Make available` and corresponding server-side commands fail until validation succeeds. Do not confuse **missing recipe** (invalid catalog configuration; cannot publish) with **missing stock** (runtime stockout; cashier may sell). Recipe quantities may be fractional but must have compatible units and defined base-unit conversion. An explicit saleable non-stock item (for example a service fee, if separately approved) needs a classified `non_inventory_component` declaration rather than an accidental blank BOM.

**Deal recipe requirements:** A deal's exact ingredient/packaging consumption is the expansion of every included product and every allowed selected variant/modifier multiplied by the chosen quantity. Each constituent product must itself have a valid active recipe. The deal builder must preview this expanded BOM, validate every required choice group and prohibit activating any bundle path that leads to a recipe-less component. Do not separately deduct both a deal-header recipe and its included products; any deal-level extra item (such as gift packaging) must be represented as a distinct added BOM line. Snapshot selected choices and BOM versions on checkout.

Manager action: Save draft → add ingredients, units and quantities → validate variants/choice groups/packaging → preview expected deductions and cost → activate. Editing an active menu item or deal creates a **new version** that must pass the recipe gate before publication; old version remains available until new version goes live, and past orders retain their original BOM snapshots.


## v6 modifier selection model

Every modifier group has `SINGLE` or `MULTI` selection mode, min/max and explicit conflict validation. `No Mayo` and `Extra Mayo` belong to the same SINGLE group and cannot both be active; selection auto-replaces previous option. Base recipe 20g mayo; No Mayo target 0g; Extra Mayo target 50g if +30g, with price addition as configured. Validate in UI AND checkout domain logic, including deal choices and imports.


## v7 — Optional but encouraged multi-image uploads for menu items and deals

Manager can upload **zero, one or multiple pictures** for every menu item and deal. Images are OPTIONAL: absence must not block saving, publishing, price edits, recipe validation or checkout. Strongly encourage pictures with a `Add photos (recommended)` helper, preview and a subtle missing-image prompt in the Manager editor. The recipe remains COMPULSORY before activation and is independent of media availability. Product cards remain legible without pictures and fall back to typographic/category icons.

Manager can choose cover/primary photo, reorder gallery, preview, replace, delete, and add captions/alt descriptions (optional). Accept JPEG, PNG and WebP (final allowlist configurable), validate actual MIME/magic bytes, decode safely, block oversized files, resize/compress and create local thumbnail variants. EXIF GPS and unnecessary metadata must be stripped. Never accept arbitrary executable/SVG uploads as executable assets. Store file bytes under application-managed offline media directory, with SQLite records containing stable IDs, relative paths, checksum, entity type/ID, original and display dimensions, sort_order, primary flag, created_by/at, status. Use atomic file staging and DB transaction/safe cleanup; no absolute PC path in database. Keep historical order receipts independent of image changes.

Cashier tiles use a thumbnail if present, else a compact text fallback; image loading must be async/cached and never delay add-to-cart. Replacements or deletions cannot invalidate order line IDs or BOM. Manager alone has image CRUD; cashier only sees published imagery.


---


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


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 07 — Delivery lifecycle, rider trips, failed/returned orders, cash settlement

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Order fulfillment [DEL-01…10]

Delivery statuses use explicit timestamps and actor IDs: Confirmed → Preparing → Ready → Out for Delivery → Delivered. Exception branches: Failed Attempt, Returned, Redelivery Requested, Cancelled. Status changes must be valid for prior status and not silently alter payment. Cashier updates kitchen/prep milestones manually; kitchen is close and there is **no KOT or kitchen queue**.

Order detail: token, customer phone masked by role where appropriate, delivery area/address/landmark, items/notes, amount, discount, fees, paid/unpaid, rider assignment, timestamps, reason history and status-changing actions. Pending ready orders may be dispatched by cashier/supervisor. Assigning rider and dispatch is an explicit recorded event.

## Rider master and trips [RIDE-01…12]

Rider can be a staff record with delivery role, active/inactive state and optional contact. Trip record has ID, rider, start/return times, business day, assigned orders (possibly multiple), cash expected by actual tender/payment channel, total COD amount, cash received, settlement state, creator/receiver actors and notes. Prevent same active order being assigned to overlapping active trips without recorded transfer. Support reassign with reason.

**Cash expected ≠ gross trip sales.** Already-prepaid card/bank orders do not add cash expected. COD amount may be adjusted by refund/partial-collection events; compute from order receivables, not a fixed copied total without reconciliation.

### Trip settlement

1. Display trip manifest with per-order payment status and expected cash to collect.
2. Mark trip Returned; enter actual collected by order where possible (supports customer partial payment), then enter **physical cash handed over**.
3. Compare **expected rider remittance** vs received cash; show shortage/overage and mandatory explanation. Do not treat rider cash as drawer cash until accepted handover transaction.
4. Source drawer/shift specified for handover; post one cash pay-in and rider settlement allocation atomically.
5. Partial settlements allowed with remaining rider receivable. Supervisor can resolve variance with approved adjustment; never mark shortage "paid" merely because order delivered.
6. Cashier may start next trip while prior shortage remains if configured; unresolved liabilities remain reported.

## Failed/returned delivery [FAIL-01…09]

Capture failure reason list (customer unavailable, invalid address, refused, rider issue, other), optional detailed note, attempt timestamp and rider ID. Distinguish:

- **Redeliver same prepared food:** policy must validate safe/time limit; record new attempt and rider/trip; do not deduct recipe again.
- **Remake replacement:** creates new consumption/wastage trail for previous batch and production of replacement; cost separately.
- **Return usable sealed inventory:** selective supervised stock return of unopened products only; never auto-return cooked ingredients.
- **Customer refund/partial refund:** separate payment reversal with tender/source, approval and cash effect.
- **Mark loss/wastage:** inventory cost loss is recognized without fake receipt.

No GPS, photo, OTP, automated courier integrations or rider app required at launch.

## Exceptions

COD order Delivered but rider unpaid; rider collected less than order amount; rider's trip has card-paid order; two trip handovers in separate cashier shifts; over-collection/change owed; duplicate delivery status clicks; returned order after day close; redelivery on next business day; customer refuses meal already cooked. Explicit lineage prevents double sales and ingredient deduction.

## Reporting and acceptance

Track fulfillment duration from timestamps, not UI clocks; median/p90 preparation and delivery time, area efficiency, rider trip counts, failed delivery rates and reasons, aging COD/rider receivables, settlement discrepancies. Tests: delivery/paid independent; multiple trips; cash expected excludes prepaid; physically handed cash posts once; partial settlement; failure reattempt no automatic restock or refund; cross-day settlement linked to original order and receiving shift.


## v7 — Manager-managed delivery service areas

Manager (Supervisor/Owner same role) has full CRUD for **delivery areas/zones**, including display name, optional code, description/coverage notes, active/serviceable flag, delivery fee in integer paisa, optional minimum basket, target ETA, priority/sort and optional availability schedule. Zones can be temporarily unavailable without deletion; historical orders keep immutable area name, fee and ETA snapshot. Used zones must be archived/deactivated rather than hard-deleted. Area eligibility is validated at final order save as well as UI selection (protect against a Manager disabling zone while Cashier is entering order). Only serviceable currently-enabled zones are selectable for *new* deliveries, with a clear unavailable response and alternative takeaway option. Managers may add/edit zones; cashiers only select them and read eligibility. Do not infer availability from maps/geocoding; serviceability comes from Manager setup. No external map API required.

Delivery fee comes from the **selected zone's configured fee**, captured on the order and included in total before payment. If order area is changed after confirmation but before trip settlement, recompute fee with audited revision and any payment difference under v6 amendment rules. After rider trip settlement, keep cart locked and use documented adjustment/refund mechanism.


---


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

## Required perpetual negative stock rule
Every committed order creates ingredient/packaging consumption exactly once even when available quantity is zero or negative. Stock projections can be negative. Receipt postings simply increase the projected balance from negative to positive; no future catch-up consumption is queued. Example: opening 2kg − sale usage 3kg = −1kg; receipt of 5kg = 4kg. Alerts remain reviewable. Physical stock counts must reconcile movement sequence safely and never hide shortage history.


---


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


---


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


---


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


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 12 — Comprehensive reporting and owner analytics

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Goal

Give owner **accurate, actionable views of the business**, not only a daily revenue number. Reports offer summary dashboards, drill-down to source transactions, saved filters, export and metric explanations. Every financial metric has a named formula in `21-analytics-measure-definitions.md`. Show `Insufficient costing data` rather than fabricated profit when BOM/costs are missing.

## Report UX [RPT-01…13]

1. Owner landing: sales today vs comparable prior business day, net recognized sales, cash expected/shortage, deliveries late/failures, supplier overdue balance, top items, ingredient/packaging anomalies and estimated margin with coverage notice.
2. Report explorer with category sidebar, top KPI strip, trend visualization, sortable detail table and drill-down drawer.
3. Filters: business-date range (today/yesterday/7/30/custom), time of day, cashier, shift, order type, product, category, deal, discount, payment method, delivery area, rider, customer segment, supplier, stock category, expense category and department (only when meaningful to report).
4. Time grouping: business day, hour, week, month; compare prior period or same weekday, with clearly labeled denominators and incomplete current-day caveat.
5. Presets: End of day, Last 7 days, Month to date, Rider settlements, Supplier Khata aging, Food cost variance, Expenses and Salaries. Manager can save private filters; owner can share role-appropriate report presets.
6. `Export CSV`, `Export Excel` multi-sheet, `Save PDF`, print via standard Windows print dialog **for reports only**; filter metadata, generation timestamp and business date included. No forced hardware printing.
7. Access control: Cashier sees own shift operational summaries only; Manager sees all operations and full finance/profit reports.
8. Graphs must show axes, units, currency and date range; allow tabular alternative; indicate missing sample points vs 0 explicitly.
9. Deep-link from metric to contributing orders/stock/Khata/payroll/expense events, respecting access.
10. Saved report exports should not leak PIN, secret keys or raw customer personal data by default.
11. Long-running exports show progress, cancellation and durable output path; do not freeze cashier billing.
12. Export content reconciles to on-screen query and persisted ledger, no separate spreadsheet arithmetic that changes values.
13. Closed day reports immutable unless explicit correction event, with generated-again notice and version provenance.

## Report catalog (MUST for production feature set)

| Family | Detailed views and breakdowns |
|---|---|
| **Sales** | Gross sales, discounts by preset, net sales, tax, fees, sale volume, average ticket, hourly peak, daily/weekly/monthly trends, revenue by mode, category, item, variant, deal, cashier and shift. |
| **Order operations** | Counts by lifecycle state, held/draft aging, prep/ready turnaround, late order thresholds, void/cancel reasons, refunds, repeat checkout attempts. |
| **Delivery** | Delivery vs takeout, timing by area, rider assignment and trip load, failure/return rates by reason, redelivery, COD collection vs rider remittance, unsettled cash aging. |
| **Customers** | New vs returning, purchase frequency, top repeat customers, average basket, areas, customer-level history with permitted privacy masking. |
| **Menu/deals** | Item popularity, gross/net deal sales, discount redemption, upsells, average quantity per bill, slow/zero sellers, food-cost coverage and item margin if costing available. |
| **Inventory** | Beginning, purchases, sale BOM, packaging, wastage, manual adjustments, returns, ending qty; negative/low-stock timeline, physical count variance, stock valuation. |
| **Procurement** | Spend by supplier/item, unit-price trends, purchase frequencies, supplier delivery performance where recorded, inventory cost changes. |
| **Supplier Khata** | Opening payable, purchases, returns/credits, payments by source, closing payable, invoice status, aging/overdue, suppliers with **No payments**. |
| **Cash/shifts** | Cash sales, tendered/change, drawer pay-in/out, refund cash, rider cash accepted, expected vs counted, shortage/overage by operator/shift, X/Z reports. |
| **Expenses** | By custom category, payee, amount, source, date, recurring patterns, manager approvals, petty cash vs other expense classifications. |
| **Staff/payroll** | Salary accrued, paid, unpaid, advances, outstanding recoverables, expenses by department, variance over time. |
| **Profitability** | COGS and ingredient/packaging spend attributed to sales, estimated gross margin by item/deal, waste loss, operating expense, labor burden, net business result with accounting-policy caveats. |
| **Control/audit** | Manager edits, discount configuration history, PIN resets (metadata only), voids/refunds, posted reversals, inventory manual adjustments, backup health, failed logins and synchronization/migration errors. |

## Core day-close deliverables

Final Z-report contains gross/net/tax/discounts, tender breakdown, cash movement reconciliation, refund/void summary, COD receivables, rider balances, stock usage/waste, supplier payable changes and day-close approvals. Required Excel tabs (extensible): Executive Summary, Sales by Item/Deals, Stock & BOM, Wastage/Returns, Shifts & Cash, Suppliers/Khata, Delivery/Riders, Expenses, Staff/Salary, Profitability (with missing-data flags). Original 6-sheet outline is retained as a minimal compatibility preset, while owner can generate wider workbooks.

## Business intelligence principles

- Transaction time filter and business-day filter are not interchangeable; default financial report uses business day.
- Separate ordered/gross value, collected cash, delivered sales and recognized revenue; never call all of these simply "sales".
- Supplier credit purchases impact inventory/payables even when unpaid. Cash out only when physically paid.
- Salary accrual and salary payout are distinct; don't subtract both as separate costs.
- Wastage of already-expensed consumed ingredients is not automatically a second inventory consumption.
- Cost data coverage ratio, estimated vs actual, reporting methodology and rounding presented near profitability.
- For large datasets, indexes/materialized summaries can speed up UI, but underlying ledger remains truth and recomputation must be possible.

## Acceptance

Date range/owner filters exactly match detail rows and exports; partial refunds, split tenders, COD and rider settlement correctly allocated; supplier credit doesn't show cash payment; chart 0 vs missing distinguished; workbook all expected tabs; late-night business day attributed correctly; finance balances and reports reconcile to SQL ledger queries; role-restricted personally identifiable data remains hidden.

## Email/WhatsApp delivery and recipient management [RPT-SEND]

- A finalized Z-report PDF and detailed XLSX MUST be stored locally before external send; attachment hash and immutable report revision retained.
- Manager defines verified recipients, channels, auto-send, PDF/XLSX selection, sensitive redaction and sender identity and may send/retry; there is no separate Owner tier.
- Email auto-sends through a configured provider with durable offline outbox and retries. No sending while PC is off unless an independent worker or a previously connected cloud relay is active.
- WhatsApp manual share is a supervised user action; **auto WhatsApp** requires official Business Platform/provider setup, permitted business template, consent, internet and token-protection architecture. Do not imply that opening a chat silently sends PDF.
- Report Delivery History shows queued, submitted/accepted, confirmed delivered if evidenced, failed and retry states, attempts, recipients masked and safe error text.
- Report delivery is not part of gross/net sales calculations. Network failure must never roll back day close. Full specification: `25-business-day-report-email-whatsapp-delivery.md`.


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 13 — Supervisor portal, Manager settings, feature flags and approvals

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Supervisor workspace

Dashboard prioritizes live exceptions: ready/delayed orders, unassigned riders, failed deliveries, unsettled cash, low stock, stale stock counts, unapproved adjustments, supplier payments due and drawer discrepancies. Provide one-click jump to underlying record. Avoid distracting charts on this action dashboard; owner analytics lives in Reports.

Supervisor authorized CRUD: menu/category/item/deal/modifier/recipe and discount definitions; stock/packaging and supplier item mappings; supplier contacts and purchases/payments; staff (except manager escalation), departments, salary/advance management; expense category creation/edit/archive/delete-unused; cash expense/void/adjustment; delivery settings, rider assignment and operational thresholds; customer data corrections. Approval flows for cashier refunds/voids and stock adjustments. Manager can configure security with reauthentication but cannot disable or erase audit.

## Owner governance [SET-01…12]

Owner additionally edits global shortcut profiles, permissions, security policy, privileged account changes, backup/restore/retention, money rounding/tax policy, export/sensitive data settings, financial thresholds, critical feature flags and unlock recovery. Manager may delegate explicitly scoped approvals without delegating ownership or system-key access.

## Settings data model

Definitions specify stable setting key, type, scope (`installation`, `role`, `staff`, `shift`, `device`), default, min/max/enum rules, required capability, audit sensitivity, revision. Values reference definition and scope with actor/change time, validation and effective date. Update is transactional and optimistic revision checked. No uncontrolled freeform JSON overrides of permission logic. High-risk changes may require manager PIN reconfirmation.

## Feature flags

Possible operational toggles: dine-in, customer phone required for delivery, allow negative stock, discounts enabled, cashier petty cash allowed, cashier void-request visible, delayed alerts enabled, rider trip mandatory, salary ledger enabled and physical counts mandatory above threshold. Disabling a module blocks new records where safe; **never conceals existing liabilities or events from owners and never disables reconciliation**. Loyalty/rewards appears as **Future / Not installed**, not an enabled but nonfunctional toggle.

## Discount administration

Supervisor designs flat-amount or percentage preset; code/name, allowed modes, allowed product categories/deals, minimum spend, per-order max, effective dates/times, stacking order, cashier eligibility, approval requirement if special, optional capacity/per-day limit. Published discount **must show in cashier's eligible options**; editing/deactivation propagates via persisted state and invalidates stale draft pricing safely. Price changes audit previous/new terms. Rules are checked in domain service at commit.

## Keyboard shortcuts and quick actions [SHORT-01…11]

Manager maps action to key combination by role/context; conflicts, OS reserved keys, text input focus and operating-system accessibility combinations validated. Bindings persist offline and survive restart. Provide preview of each key, duplicate detection, `Reset default`, `Restore prior version`, `Test mapping` with no transactional execution and a draggable quick-action row. Show shortcut hint in cashier controls. A configured shortcut may invoke only authorized active actions, never bypass supervisor approval. A mapping conflict in two mutually exclusive contexts may be allowed but must be explicitly visible to Manager.

## Approval UI

Requested action → reason → amount/order/stock impact summary → manager PIN overlay (credential verification, no cashier logout) → authorized decision → append approval record → perform requested transaction atomically. Approval identity is distinct from requester's identity; optionally enforce two-person rule for high-value operations. A rejected approval changes no financial ledger and is still logged.

## Operational exception review

Lists of unresolved late orders, delivery failures, short rider settlement, abnormal discount activity, unused item, recurring wastage, supplier overdue invoices, cash shortfall and salary debt. Each exception: severity, entity, detected at, business day, assignee, resolution/notes, closure actor/time. Do not delete open exception on related feature toggle off.

## Acceptance

Supervisor can CRUD catalog/deals/expense categories and see results in cashier/expense UI. Manager can create another manager account. Manager shortcut remap survives restart, cannot trigger in PIN entry. Permission logic blocks direct unauthorized service calls. Feature toggle preserves history and in-flight settlement. Approval logs correct requester and approver.

## Report delivery settings and permission [SET-SEND]

**Manager settings**: channel choice, automated email, optional WhatsApp mode, approved recipient list, sender identity, recipient verification/consent, report format, privacy scope, schedule trigger after close, retry caps, encrypted credentials and health/test-send. **Manager report delivery**: can inspect status, configure authorized recipients, and send/resend with audit. Changes persist, are audited and don't change posted financial history.


## v7 — Serviceable area and product-media management

Manager-only navigation adds `Delivery Areas` and image controls inside `Menu` / `Deals`. Delivery Areas list/edit/create/disable and fee changes require Manager session and audit old/new values. Cashier cannot create zones, override an unavailable zone, change zone fees or upload pictures. Manager may add/reorder/replace/delete optional menu/deal images, with secure local storage and no impact on mandatory BOM gating. Customer detail entry and final order confirmation remain **Cashier-only** operations.


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 14 — Screen-by-screen UI/UX specification for the REAL Flutter Windows app

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Visual direction: Street-Food / Mafia Branding — DEFAULT v8 theme

The production Windows interface adopts an assertive **street-food / cartel-inspired** aesthetic: obsidian-black workspaces, dark navy surfaces, bold energetic sans-serif typography, yellow primary actions, restrained gold highlights and high-quality realistic food images. Use crown iconography and small brush-stroke accents for restaurant identity, **not** for operational buttons, price values or ledger data. The restaurant brand name/logo is configurable; these colors are **suggested implementation colors, not official Crunch Cartel brand codes**. Branding inspiration must not require copying any third-party trademark, menu photography or promotional assets.

| Semantic design token | Color | Application |
|---|---|---|
| Obsidian / main background | `#050708` | Application workspace, outer canvas |
| Dark Navy | `#101820` | Fixed compact sidebar, deep panels |
| Cartel Yellow | `#FFC400` | Main cashier action, selected category, active focus/accent |
| Burnt Gold | `#F5A623` | Secondary emphasis, restrained operational highlights |
| Off White | `#F5F7FA` | Primary text on dark surfaces, icon labels |
| Card Surface | `#14242D` | Cards, editors, operational tables |

Yellow primary buttons use **dark text** for legibility and disabled states use distinct neutral treatment. Subdued secondary text, borders and semantic green/amber/blue/red status colors are derived as accessible supplemental tokens; they are **not official brand codes**. Dark is the default design; optional alternate modes require their own tested semantic tokens. Do not revive warm ivory / green / terracotta as default screens.

Typography: bold, modern sans-serif headline family and readable system/Inter/Segoe UI supporting text. Energetic branding applies to headings and marketing/banner zones; data entry, totals, addresses, receipts, audit logs and dense tables must use stable, highly legible styles with tabular numerals. Small typographic accents never obscure PKR, totals or modifier instructions. Spacing in 4px increments, mostly 8–12px corners; avoid excessive pills, glowing neon or playful elements near payment and destructive actions.

### Design constraints

- Optimize for **1366×768** Windows desktop; test at 100%, 125%, 150% DPI. Minimum target sizes: 44–48px; PIN keypad ≥64px. Keep cashier's cart/total/confirm pinned. No full-page cashier scrolling for regular workflow.
- Page shell: thin top utility bar (business date, active shift, staff, lock/offline), compact rail/navigation. Owner back-office can use longer tables/forms with pagination/virtualization; cashier cannot.
- Do not use destructive red for ordinary cancel-dialog close or navigation. Confirm irreversible posted actions with impact, reason and explicit button.
- Keyboard-first: focus order, F keys, Enter/Escape behavior, searchable list navigation, manual numeric entry and help overlay with active mappings.
- Status includes text + icon/color. Loading indicators don't block unrelated order entry or freeze UI. Errors retain entered data.

## Screens and required content

| Screen | Role | Primary controls | Empty/error/busy states |
|---|---|---|---|
| PIN lock | credentialed staff | Masked numeric PIN, keypad, Enter, Backspace, lock notice | Wrong PIN, cooldown, inactive user, recovery contact |
| Day open | Manager | Business date, open day, opening checklist | Already open, previous day unclosed, backup warning |
| Shift open/close | Cashier/Supervisor | Float, denomination count, submit, review after count | Missing float, counted variance, disconnected cash peripheral (future) |
| **Cashier POS** | Cashier only | Mode, phone, category search, menu grid, persistent cart/discount/total/charge, hold/recall | Empty cart, catalog missing, invalid coupon, no matching item, long cart |
| Deal choice sheet | Cashier only | Required groups, options, add-ons, confirm | Missing choice, unavailable variation, preview mismatch |
| Payment/checkout | Cashier only | Tender method, received, change, split, COD, confirm | Underpay, manually selected tender, saving/retry idempotency; no gateway or verification-state UI |
| Held orders | Cashier only | Draft search, owner, created time, recall, discard | Lock conflict, repricing warning, expired hold |
| Customer lookup | Cashier only | Phone, addresses, history, repeat order | Duplicate phone, guest, obsolete previous deal |
| Orders/status | Cashier only | Search, filter, Ready/Dispatch/Delivered, history | No kitchen ticket; illegal transition disabled |
| Rider trips | Cashier only, manager read-only | Assign, trip list, return, per-order cash, handover | Short/over, unpaid COD, reopened attempt |
| Supervisor home | Supervisor+ | Exceptions, delayed orders, stock, settlements, reviews | No alerts, multiple open approvals |
| Menu editor | Supervisor+ | Categories, products, variants, recipes, price/availability | Ingredient missing, price conflict, archived component |
| Deal editor | Manager only | Builder with selection groups, required counts, upgrade price, **required complete expanded BOM preview** | Empty required group, missing/invalid BOM, cyclic dependency, invalid total; cannot activate until complete |
| Discount presets | Supervisor+ | Preset CRUD, validity, eligibility, publish/disable | Expired, stacking conflict, draft superseded |
| Stock manager | Supervisor+ | Item CRUD, type, unit, low stock, history, movement | Negative stock, unit mismatch, referenced item delete denied |
| Physical counts | Supervisor+ | Count session, expected vs actual, variance, approve | Concurrent receipt, stale snapshot |
| Supplier directory | Supervisor+ | Supplier CRUD, supplied items, create new item inline, balance, archive | No supplier products, unpaid archived supplier |
| Purchase entry | Supervisor+ | Supplier → filtered products, qty/unit/cost, payment source, invoice ref | Wrong mapping, invalid unit, duplicate invoice |
| Supplier Khata | Supervisor+ | Invoices, payments, opening balance, aging, ledger, source | No payments, credit/overpayment, stale balance |
| Expenses/categories | Authorized | Expense payee/category/source/amount; category management for managers | Category used archive not delete, missing note |
| Staff/payroll/PINs | Supervisor+ | Staff CRUD, roles, unique PIN, salaries/advances/payments | PIN collision, manager escalation denied, posted salary history |
| Reports | Supervisor+/Owner | report explorer, period and dimensions, graph/table, export | Missing costs, large range, incomplete current day |
| Shortcut/quick action editor | Owner | Action registry, bindings/role context, conflict validation | Reserved key, duplicate assignment |
| Backup/restore | Owner | Last verified backup, create, verify, restore preview | Disk full, corrupt archive, restore rollback |

## Detailed cashier interaction contract

Persistent primary composition:

```
┌ Header: Business Day | Shift | Cashier | Lock ──────────────────────────────┐
│ Delivery  Takeaway  Dine-in | Customer phone/address (contextual)        │
├──────────────────────────────────────────────┬───────────────────────────┤
│ Search | Categories                           │ CURRENT BILL              │
│ Product/deal tile grid (virtualized)          │ Rows + qty / modifiers    │
│                                              │ Discount presets         │
│                                              │ Subtotal / fees / taxes   │
│                                              │ TOTAL (large)             │
│                                              │ [Hold] [Charge / Confirm] │
└──────────────────────────────────────────────┴───────────────────────────┘
```

One click on basic product adds qty, with no modal; use two-stage or explicit modifier sheet only if configured options required. Clicking current cart row edits only that row. Category chip and search field stay visible even with many products. Status messages stay out of the action path. Shortcut help accessible by user-controlled button. Hold and Recall are easy to reach. Payment sheet handles cash tender/currency entry and takes focus; after save focus returns to product search/new-order context.

## Manager interaction patterns

Data tables have `+ New`, local search, filters, status, pagination, view/edit/archive, clear role visibility. Editing opens a dedicated sheet with unsaved-change warning. Reusing a record name retains ID. Financial corrections use `Reverse`, not `Delete`. Supplier form includes a custom supplied-product editor and fast creation of inventory items; menu deal builder visually explains what is included; employee form makes PIN required only if POS access is on.

## Accessibility and operational reliability

WCAG AA contrast targets where feasible; high-contrast focus rings, semantic labels, input masks without losing keyboard paste, reduced motion, SR announcements of important save/error, non-color statuses. All essential cashier actions usable using keyboard only. UI must not confuse negative stock warnings with inability to bill under soft-stock configuration. Desktop system-level dialogs must not accidentally block PIN or shift reopening.

## Usability tests before signoff

Film/measure ten complete orders of varying complexity with target cashier; note click count, scroll count, time to total, search and discount discoverability, error rate; rerun at 1366×768 and 125% scaling. Verify persistent cart under 12+ lines with internal scrolling. Test supervisor adding a deal then cashier selecting it. Test used expense category archive, supplier item creation within purchase, cashier PIN lock/login and owner shortcut rebind.

## Notification and delivery-history screens

**Settings > Report delivery** (Owner): channel toggles, validated recipient editor, test-send, report PDF/XLSX options, privacy section toggles, send-after-close and API-ready indicators; clear distinction between manual and official automatic WhatsApp.

**Close-day status** (Manager): independent rows `Business day closed`, `Report saved`, `Local backup`, `Email queued/sent/failed`, `WhatsApp queued/sent/failed`. Never roll back day close if a send fails.

**Delivery history**: business day, report revision, channel, masked contact, latest attempt, status, details, retry/resend and last safe error. Persistent queued states survive app restart. Cashier workspace must never display transient network-send progress as a modal distraction.

Detailed screen field matrix: `27-screen-by-screen-forms-fields-and-actions.md`. Video mapping: `23-video-reference-feature-decisions.md`.

## v5 payment screen — selection only, no API-style tags

Cashier payment interface contains straightforward method choices: **Cash, JazzCash, Easypaisa, Bank/Raast, Card, COD, Split**. For collected payment, cashier selects method, optionally adds a reference, and taps **Complete payment**. Do **not** show `Unverified`, `Processing`, `Waiting for provider`, `Manual confirmation required`, API health, a settlement spinner or separate external verification badge. Cash shows amount received and change; digital methods need no integration and no additional verification workflow. The method choice and cashier save action are the operational record. COD appears as **Not collected / Collection due** until paid; split payments may display **Remaining Rs. X**. Only legitimate business accounting statuses (Paid, Partially paid, Unpaid/COD, Refunded) may appear as appropriate. If a database stores an internal source/attestation field, it is not a customer/cashier badge.

## v5 manager menu/deal editors — compulsory recipe step

Create/edit screen has **Details → Recipe → Review/Publish**. A draft may be saved but the publish switch and active state are blocked until the item recipe covers all required ingredient units, modifier variants and applicable packaging. Deal builder lists included items, validates their recipes and computes an expanded BOM preview for all allowed choices. Show a clear inline `Complete recipe before activation` error instead of blocking ordinary cashier sales when **stock quantity** is low or negative.


## v6 cashier and onboarding interfaces

Checkout sheet displays tax-inclusive item prices, cashier method buttons, cash payable rounded to whole rupees, exact digital payable, and separately labeled `Cash rounding: -Rs.0.25` only where a rounded cash leg actually exists; cash change is whole rupees. No payment API status badges. Confirmed-order editor enabled Preparing/Ready/Out for Delivery; show a clear lock notice once rider trip Settled, linking to refund/adjustment and new-order workflow. Manager menu modifier editor uses radio options for mutually exclusive sauces. Initial wizard MUST require Manager then Cashier PIN and show step-by-step day/shift readiness.


## v7 — Cashier step sequence, area selection and optional images

The cashier workstation stays fixed-height on baseline 1366×768: menu grid and cart remain visible without page-level vertical scrolling. Cashier selects products/deals → **Continue — Customer** opens compact right drawer/sheet → enters or searches name/phone and for delivery selects a serviceable area, address and notes → Continue to Payment → method/amount/COD → **Complete Order**. Before final save, show order total inclusive of zone delivery fee. Switching delivery/takeaway changes required fields dynamically while preserving entered data. A returning caller's addresses appear in one-tap suggestions. `Back` preserves cart and details; Escape closes top layer with confirmation only when losing data. If an area is disabled mid-flow, inline error invites new selection; never silently choose another area. No token or BOM posting at intermediate steps.

Manager `Delivery Areas` screen: searchable list (name, coverage, enabled/serviceable, fee, ETA), Add/Edit/Deactivate, audit history and safe-delete checks. Manager menu/deal editor: `Details → Mandatory Recipe → Optional Pictures → Review/Publish`; upload/gallery is optional and encourages primary image selection. Cashier tiles display optimized picture thumbnails if available with fast fallbacks and no oversized photo layout. Do not create a mandatory image-upload wizard. Loading or missing images cannot block billing.

## v8 exact styling contract — street-food / mafia brand without POS friction

**Sidebar and shell:** fixed compact dark navy `#101820` sidebar, obsidian `#050708` content background, card surface `#14242D`, 1px restrained separators. Selected nav element uses a narrow yellow indicator plus clear text; labels remain visible, not icon-only by default. Header shows cashier identity/shift/business day distinctly. Avoid full-canvas photos or textured wallpaper behind input controls.

**Buttons:** primary `#FFC400` with deep black text (`#050708`), meaningful hover/focus outline; secondary dark navy with off-white text, destructive red reserved for true destructive actions, burnt gold `#F5A623` for tasteful secondary emphasis. Buttons maintain 44–48px touch targets in operations. Display shortcut hints subtly beside relevant cashier controls.

**Cards and tables:** deep navy/slate panels; dense but clear ledger grids, fixed headers where needed, alternating low-contrast row treatment without zebra overload, right-aligned PKR numbers, visible row actions. Manage readable 13–16px type sizes; do not let decorative crowns or brush strokes contaminate data tables.

**Status palette:** green for Ready/Delivered/Successful, amber for Preparing/Attention, blue for Out for Delivery/In transit, red for Cancelled/Failed/Error. Status MUST contain a readable word/icon and meet WCAG AA contrast; use accessible tone-on-dark combinations (sample token directions: green `#58C78A`, amber `#F5A623`, blue `#6BAEFF`, red `#F47F7F`). Colors are semantic, not a substitute for text.

**Product/deal imagery:** realistic high-resolution food photographs, cropped consistently at a defined aspect ratio; use primary image from the manager's optional photo gallery when available. Render thumbnails from local offline cache asynchronously; no picture means a designed category-icon/text fallback, never a broken tile. No stock imagery is mandatory and no images are auto-generated in production. Menu and deal gallery uploads remain optional; recipe BOM remains mandatory before activation.

**Brand motifs:** crown emblems can appear in brand mark, splash/login and restrained header identity. Brush-stroke yellow/gold accents may appear in splash, onboarding, empty-state illustrations or section separators, never over form fields, money, labels, stock warnings or the checkout confirmation button. No unauthorized replication of Crunch Cartel's actual mark/photos.

**Cashier layout:** preserve fixed-height, non-scrolling 1366×768 cashier workflow with item grid left, persistent cart right, search/categories pinned and rapid transitions `Cart → Customer Details → Payment → Final Commit`. Maintain bright yellow single clear action per step, keyboard-first operation, and never let visual animations delay a bill. Photo-heavy tiles must not reduce product density enough to require repeated scrolling.

**Manager screens:** same dark tokens but prioritize data density and filtering; charts and reports use reserved semantic series colors and readable ticks/grids. Yellow accent belongs to meaningful primary action or active filters, not every chart bar. Financial status and negative-stock warnings are more important than brand decoration.

**Accessibility and QA:** check WCAG AA body text (4.5:1), large text and essential boundaries (3:1); meaningful focus rings, legible yellow/dark pair, disabled distinction, 100–150% Windows DPI, color-blind distinctions, offline thumbnail failure, touch and keyboard speed tests. Theme values centralized as Flutter `ThemeData`/`ColorScheme` semantic tokens, not hardcoded per widget. Verify screens with and without menu photographs.


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 15 — Production architecture, offline operation and deployment

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Technology baseline

- Flutter stable (Windows), Dart, Material 3 themed with fully custom operational components.
- Riverpod for state orchestration and local reactive queries; GoRouter for role-aware navigation; Drift + SQLite for persistent data and migrations.
- `sqlite3` native bundled appropriately; WAL mode and transactional persistence. Determine file paths using platform storage APIs instead of hardcoding administrative protected paths. Use secure Windows installer/AppData location appropriate to service account, backup and multi-user access; apply ACLs.
- Use pure Dart value/domain services for monetary calculations, inventory conversions, order state machines and permission guards; Flutter widgets never issue raw SQL.
- decimal/integer arithmetic: store amounts as `INTEGER` **paisa**, rates/quantities with specified scale or decimal string conversion library, converting only at audited DB boundary. Never use `double` for financial balance.

## Layers and folders

```
lib/
  bootstrap/            # first run, database check, logger, clocks
  app/                  # router, theme, shell, role-based navigation
  core/{money,units,time,errors,permissions,ids,domain_events}/
  data/{database,migrations,dao,transactions,backup}/
  features/
    authentication/ business_days/ shifts/ staff/ payroll/
    pos/ catalog/ deals/ discounts/ customers/ orders/ refunds/
    delivery/ riders/ stock/ wastage/ procurement/ suppliers/
    cash/ expenses/ reports/ settings/ shortcuts/
  shared/widgets/
```

Domain interfaces isolate persistence and UI. A single **transaction coordinator** orchestrates side effects for posted actions. Report repository reads ledger projections, not UI state. Maintain testable adapters for time/IDs and future print/payment integrations.

## Order checkout atomicity

`confirmCheckout(intentKey, draftRevision, actor)`:

1. Permission and active business day/shift validation.
2. Re-read current catalog, effective price, deal, discount and availability; compare draft revision and show conflicts before final confirm.
3. Compute money, tax allocation/rounding, package and BOM requirements in deterministic pure function.
4. In one DB transaction enforce unique idempotency key, reserve/allocate business day token, insert order/lines/snapshots, initial status, receivable/payment allocations, consumption ledger, audit event and committed intent result.
5. Commit. Return persisted order ID and total. Outside transaction, optionally generate digital receipt, nonblocking report-cache invalidation and UI success.
6. Crash/retry on same intent key returns original order, not second order.

## Offline persistence and concurrency

- SQLite WAL for readers and single writer serialized transactions, explicit busy timeout, foreign keys ON, indexes and checkpoint policy.
- Use one repository writer command queue for conflicting ledger mutations; provide progress and limited retry for `BUSY`, preserving idempotency key.
- No network dependency for billing, supplier postings, PIN unlock, reports on local data or backups.
- Do **not** put one writable SQLite file on LAN share/SMB for multiple tills. Future multi-terminal model: one local on-premises transaction service with authenticated clients, explicit sync and central locking; redesign sync conflicts before enabling it.
- Business day/shift locks transaction-time checked even if UI is stale; prevent late order into closed day.
- Cross-process multi-instance guard for same DB file; second app instance may open read-only tools or focus existing app, not create independent writers with competing shift context.

## Data snapshots and projections

Price, tax, discount, modifier, address, deal choices and unit conversion factor snapshot on finalized source transaction. Ledger is immutable; projection tables/current balances may be rebuilt from events. For reporting speed maintain versioned summary cache invalidation on new events with verified reconciliation queries. Migrations must preserve all old snapshots.

## Backup, restore and encryption boundaries

See security file. Auto-backup after business day close and timed backups while operating (policy), WAL-consistent SQLite backup API/checkpoint method, write to temp file then atomic rename, checksum, optional secondary drive; verify opening and sample integrity. Restore only while writer stopped after safeguarded pre-restore backup; test full reopen/migration and report. Distinguish operational SQLite integrity from secret-key recovery (DPAPI machine context).

## Windows operations

Create signed MSI/MSIX or trusted installer appropriate to deployment, install app binary separate from writable data. Full-screen kiosk-like option but accessible OS controls. Startup preflight shows database/backup health, current business day and shift; no arbitrary demo seed in production. Automatic logging with secret/phone redaction, exportable diagnostic report without money manipulation. Provide safe app upgrade/migration and rollback copy.

## Performance targets and monitoring

Design targets (not user-approved SLAs): POS keyboard input responsive <100ms typical; product tile action visible <150ms; database local checkout typical <500ms for ordinary basket on target hardware; customer search <300ms with normalized phone index; report of one-month data completes without blocking cashier input. Performance measurement with realistic 50k+ orders and 100k+ ledger events, long catalogs and Excel exports. Domain work on appropriate isolate when needed; no UI-thread heavy aggregation.

## Versioning and migration

Drift schemaVersion integer; forward-only tested migrations in upgrade path with pre-migrate backup; no wipe-and-recreate on production user data. Version settings and report formulas, inventory costing and payment status changes. SQLite PRAGMA `foreign_key_check` and `integrity_check` as maintenance operations. CI tests migrate old fixtures into current schema and compare key ledger totals before/after.

## Dependencies and interfaces

Interface seams: `Clock`, `UniqueIdGenerator`, `PinCredentialService`, `OrderCommandService`, `LedgerTransactionCoordinator`, `CatalogRepository`, `InventoryPostingService`, `ReportQueryService`, `BackupService`, `DigitalReceiptService`, and optionally future `PaymentVerificationAdapter`, `PrinterAdapter`, `MultiTerminalSyncAdapter`. No direct or automatic banking/card settlement is assumed.

## Durable report delivery outbox [ARCH-SEND]

`ReportGenerator` produces immutable artifacts from committed `DayCloseSnapshot`, stores content digests and report metadata. `ReportOutbox` transactionally queues immutable jobs keyed by `(business_day_id,revision,channel,recipient,purpose)`. `DeliveryWorker` claims leases, retries with backoff and idempotent provider client; state and error history survive restart. Provider interface `sendEmail(artifactRefs,recipient,template)` / `sendWhatsAppDocument(...)` is separate from domain order and close service. API keys/WhatsApp credentials MUST NOT be embedded as readable source or plain bundled app secrets; use OS secret protection for device-scoped secrets and preferably a backend relay for shared remote credentials. Manual WhatsApp is a distinct local UI share action. The local worker needs Windows process/service running; no false offline delivery guarantees.


## v7 offline catalog media architecture

Store originals and compressed thumbnails in protected app data path (`media/catalog/...`), referenced using normalized relative paths and content hashes in SQLite. Import pipeline: validate magic bytes and supported raster formats → decode with pixel/dimension bounds → strip metadata → resize/compress thumbnails → stage temp file → write metadata transaction → atomic rename/finalize with recoverable cleanup job. On app launch, reconcile incomplete staged images; verify missing thumbnails and rebuild from original where safe. All gallery changes operate on media IDs, not file names. Image cache must be bounded and asynchronous; no HTTP/image CDN needed. SQLite backups must include corresponding catalog media (or a manifest + deterministic media archive); restore validates file hashes and rebuilds thumbnails as needed.


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 16 — Logical Drift/SQLite data model and constraints

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


This document defines domain schema boundaries, not a pasted finished SQL migration. Every table requires appropriate `created_at_utc`, `updated_at_utc` (mutable masters only), `created_by`, immutable primary ID, and migration/version handling as relevant. Use foreign keys, unique indexes and CHECK constraints. **All posted events must be append-only.** Actual SQL types should be finalized with a testable migration plan.

## Identity, security and system

| Entity / table | Important fields / constraints |
|---|---|
| `departments` | id, name unique among active, active, sort_order |
| `staff` | id, code UNIQUE, name, contact, department_id FK, pay_scheme, active, archived_at |
| `credentials` | id, staff_id FK UNIQUE, role enum, PIN_verifier_hash, PIN_salt, PIN_fingerprint UNIQUE active, enabled, last_rotated, failed_count, blocked_until; **no raw PIN** |
| `session_events` | id, staff_id, opened/locked/expired, terminal_id, time, reason |
| `permission_grants` | role/capability/scope, granted_by, effective timestamps; reserved manager policies enforced in code |
| `setting_definitions`, `setting_values`, `setting_change_events` | stable key/type/scope, revision, actor, old/new sanitized value, timestamp |
| `shortcut_profiles`, `shortcut_bindings`, `quick_action_layouts` | profile, role/context/action/key, revision, conflict index, active |
| `audit_events` | id, entity, entity_id, event_type, actor, approver, reason, immutable before/after hash/approved safe metadata, UTC, business_day_id |
| `idempotency_commands` | intent_key UNIQUE, kind, request_hash, result_entity_id, result_status, created_at |
| `backup_history` | id, file path, checksum, db_version, verified_at, result, error metadata |

## Day, shift and drawer

| Entity | Fields / constraints |
|---|---|
| `business_days` | id, business_date UNIQUE for restaurant, status, token_seq, open/close actors/times, close_version |
| `cash_drawers` | id, label, active, location |
| `shifts` | id, business_day_id, cashier_id, drawer_id, open/close time, opening_float_paisa, count_state, expected, submitted_total, review_state; one active shift per drawer |
| `cash_counts`, `cash_count_denominations` | shift_id, attempt number, actor, currency denomination, count, submitted_at, original immutable count |
| `cash_movements` | id, shift_id, direction, amount_paisa (>0), source_type, source_id UNIQUE scoped, actor, approved_by, reason, idempotency_key UNIQUE |
| `shift_discrepancy_reviews` | shift/count, calculated variance, threshold, reviewer/status/action, append-only |

## Catalog and configuration

| Entity | Fields / constraints |
|---|---|
| `menu_categories` | id, code/name, parent? sort, active |
| `menu_items`, `menu_item_revisions` | code, category_id, name, price_paisa, tax_code, active, revision/effective period; historical snapshot preserved |
| `variants`, `modifier_groups`, `modifier_options` | required/min/max, price delta, usage/selection constraints, active |
| `deals`, `deal_revisions`, `deal_groups`, `deal_choice_items` | code/price/eligibility, group min/max, included item/quantity/upgrade price; no cycles |
| `recipe_versions`, `recipe_ingredients`, `modifier_recipe_deltas` | menu/deal recipe revision, ingredient ID, decimal amount and base unit, effective period |
| `packaging_rules`, `packaging_rule_items` | mode/item/category/deal applicability, packaging stock item, qty, active/effective revision |
| `discount_presets`, `discount_rules`, `discount_changes` | %/flat value, dates, mode/category/deal, min/max, stacking, role, approval and audit |

## Customers, orders, tender and refunds

| Entity | Fields / constraints |
|---|---|
| `customers`, `customer_phone_numbers`, `customer_addresses` | customer, normalized_phone indexed, address version/default; avoid global UNIQUE if shared number policy allows and handle conflict explicitly |
| `order_drafts`, `draft_lines` | staff/session, draft_revision, hold_status, customer/address context, options, created/updated/expiry; no token |
| `orders` | id, `(business_day_id, token_number)` UNIQUE, staff, customer snapshot/mode, address snapshot, status projection, money snapshot total, idempotency key UNIQUE |
| `order_lines`, `order_line_components`, `order_line_modifiers` | immutable item/deal/product/qty/price/tax/discount selection snapshots and recipe references |
| `order_status_events` | order_id, from, to, actor, UTC, reason, attempt_id; immutable |
| `delivery_attempts` | order, attempt number, rider/trip/time, failure_reason, result, next_attempt linkage |
| `payment_allocations` | order, method, due/received/verified amount, reference, verification state and balance snapshots; append-only events preferred |
| `refund_requests`, `refund_events`, `approval_events` | original payment/order, amount, method/status, supervisor authorization, reason, inventory disposition |
| `financial_entries` | event ID, account/category, debit_paisa, credit_paisa, source document; balanced per transaction if full double-entry module enabled |

## Delivery

| Entity | Fields / constraints |
|---|---|
| `rider_trips` | id, rider_staff_id, business_day, departed/returned times, status, receiving shift |
| `rider_trip_orders` | trip/order association, assignment/return/transfer reason, UNIQUE active assignment per order |
| `rider_cash_handovers` | trip, cashier/shift, physically received cash, time, idempotency, actor |
| `rider_settlement_allocations` | handover/event, order payment allocation, amount, shortage/overage disposition |

## Inventory and purchasing

| Entity | Fields / constraints |
|---|---|
| `stock_items` | id, code UNIQUE, name, type, base_unit, dimension, track_stock, reorder level, active |
| `unit_conversions` | id, name, dimension, factor numerator/denominator, optionally stock_item/supplier_item scope, effective revision |
| `inventory_movements` | id, stock_item, qty_decimal, type, source_type/source_id, business day, actor, unit_cost_snapshot, reversal_of, idempotency UNIQUE |
| `inventory_cost_layers` | stock item, received qty, remaining qty, cost amount, source receipt, valuation_method |
| `stock_counts`, `stock_count_lines`, `stock_count_approvals` | count reference, snapshot event sequence, counted qty, variance, approver and posted movement |
| `wastage_events` | item, quantity, cost snapshot, reason, staff, event/approval reference |
| `suppliers`, `supplier_item_links` | supplier name/contact, inventory item, supplier SKU/unit factor/last_price, link active, UNIQUE supplier+stock_item active link |
| `purchase_invoices`, `purchase_lines` | supplier, invoice ref, date/due, posted status, line unit/qty/factor/cost and receiving item snapshots; unique supplier+external reference policy |
| `supplier_ledger_entries` | supplier, opening/invoice/payment/credit/reversal, signed payable_paisa, source, UTC, actor, reversal reference |
| `supplier_payments`, `supplier_payment_allocations` | amount/source/drawer-or-bank, invoice allocation, status, source event and idempotency |

## Expenses and payroll

| Entity | Fields / constraints |
|---|---|
| `expense_categories` | id, name casefold active UNIQUE, parent, active, archived_at, label revision |
| `expenses`, `expense_postings` | category id + label snapshot, amount, payee, source account, authorizer, reason, optional receipt, reversal reference |
| `staff_pay_terms`, `salary_periods` | employee/effective date/rate, payroll period/start/end, locked state |
| `staff_ledger_entries`, `staff_advances`, `salary_payments` | employee, type (accrual/advance/repayment/payment/adjustment), signed amount, funding source, source link, reversal_of |

## Mandatory constraints and indexes

- `NOT NULL` all essential actor/entity/time/amount fields; `CHECK(amount_paisa > 0)` for absolute posted payment, amount sign explicit through type/direction.
- Unique `(business_day_id, token_number)`, `idempotency_key`, `staff.code`, `stock_item.code`; use partial indexes for active mapping names/keys where SQLite supports them.
- Foreign key on every stock/order/supplier/staff reference; do not `ON DELETE CASCADE` financial history.
- Index `orders(business_day_id,status)`, `orders(customer_id,created_at_utc)`, `phone(normalized)`, `supplier_ledger(supplier_id,time)`, `inventory_movements(stock_item_id,time)`, `cash_movements(shift_id,time)`, `staff_ledger(staff_id,period_id)`.
- Order line/deal snapshots are immutable; historical names, prices and discounts must remain meaningful if masters renamed.
- Store `reversed_entry_id` with a one-to-one constraint to prevent double reversal; corrected invoice may have explicit successor link.
- Expense categories with history are archived only. Supplier with payable/history cannot be deleted. Stock item with any movement/BOM linkage cannot be deleted.

## Migration and seeds

Seed required system enum tables and suggested starter expense categories/menu examples **only in optional onboarding templates**, never as real sales. Seed one owner during guided onboarding only. Migrations tested with existing ledger fixtures; no automatic data reset on schema update.

## Reporting artifacts, outbound delivery and recipient policy (extension)

```text
report_runs(id PK, business_day_id FK, revision, report_kind, status,
  snapshot_cutoff_utc, report_hash, generated_by_staff_id, generated_at_utc,
  UNIQUE(business_day_id, revision, report_kind))
report_artifacts(id PK, report_run_id FK, format ENUM(PDF,XLSX,CSV),
  protected_path, file_sha256, bytes, created_at_utc)
report_recipients(id PK, channel ENUM(EMAIL,WHATSAPP), address_ciphertext,
  display_mask, verified_at_utc, consent_record, active, created_by_staff_id)
report_delivery_policies(id PK, channel, auto_after_close, attach_pdf,
  attach_xlsx, attach_csv, allowed_report_scope, delegated_roles,
  max_retry_attempts, backoff_profile, updated_by_staff_id)
report_delivery_jobs(id PK, report_run_id FK, recipient_id FK,
  channel, purpose, idempotency_key UNIQUE, state, requested_by_staff_id,
  queued_at_utc, next_attempt_utc, attempts_count, lease_owner, lease_until_utc)
report_delivery_attempts(id PK, job_id FK, attempted_at_utc,
  provider_request_id, provider_message_id, status, sanitized_error)
report_delivery_events(id PK, job_id FK, provider_event_id UNIQUE NULLABLE,
  state, received_at_utc, happened_at_utc)
```

Encrypt addresses/credentials and generated sensitive artifacts according to approved protection design. Do not store raw email API keys or WhatsApp tokens in tables by default. Keep recipient references stable for queued jobs; approve changed destination as a new job rather than mutating previously queued history. See `25`.


## v6 REQUIRED migration additions

Implement physical `order_revisions` and `order_revision_lines` tables, including FK to original order, monotonic revision/version, actor, reason, snapshots, amount deltas, stock disposition, and unique idempotency; see full SQL draft in Chapter 32. Set **`cash_movements.approved_by` NULLABLE** in SQLite and Drift schema. Routine cashier pay-in/out never requests manager PIN and uses NULL approver; event actor/reason remain mandatory. Add `cash_rounding_paisa INTEGER NOT NULL DEFAULT 0` to posted settlement documents or order tender finalization and `tax_pricing`, `tax_rate_bps`, `tax_code` configuration. Add persisted `orders.current_revision`, reader-lock linked to rider `Settled` event, modifier selection mode/conflict rules, and serial daily token sequence. Apply as tested migrations from existing v5 schemas.


## v7 — schema extensions (migration required)

- `delivery_areas(id PRIMARY KEY, name NOT NULL, code UNIQUE NULL, description NULL, active NOT NULL DEFAULT 1, serviceable NOT NULL DEFAULT 1, delivery_fee_paisa INTEGER NOT NULL CHECK(delivery_fee_paisa>=0), min_order_paisa INTEGER NULL CHECK(min_order_paisa>=0), target_eta_minutes INTEGER NULL, sort_order INTEGER NOT NULL DEFAULT 0, deleted_at NULL, created_at, updated_at, created_by, updated_by)`. Use stable primary key; validate uniqueness of normalized active area names.
- `delivery_area_availability_rules(id, area_id REFERENCES delivery_areas(id), weekday INTEGER, open_minute INTEGER, close_minute INTEGER, enabled INTEGER)` optional configured scheduling; no schedule means active all day.
- `customer_addresses(id, customer_id, area_id NULL REFERENCES delivery_areas(id), street_address, house_building, landmark, instructions, is_default, created_at, updated_at)` if not present in v6. Validate nullable historical area relationships.
- `orders` includes `customer_id NULL`, `delivery_area_id NULL`, `delivery_area_name_snapshot`, `delivery_address_snapshot`, `delivery_fee_paisa INTEGER NOT NULL DEFAULT 0`, and immutable order/revision address snapshots. Final commit validates area availability in the same serialized write transaction and captures effective fee. Never trust UI amounts.
- `catalog_images(id PRIMARY KEY, entity_type NOT NULL CHECK(entity_type IN ('menu_item','deal')), entity_id NOT NULL, relative_original_path NOT NULL, relative_thumbnail_path, content_type, byte_count, sha256_checksum, width_px, height_px, sort_order, is_primary, alt_text, created_at, created_by, deleted_at NULL)`. Enforce at most one active primary image per entity via partial unique index; validate references in service layer or separate join tables if strict foreign keys are preferred.
- `media_cleanup_jobs(id, catalog_image_id, relative_path, action, state, attempts, created_at)` for cleanup/retry after DB commit; media files are application-managed local resources.
- Add indexes on active delivery_areas, normalized customer phone lookup, customer_addresses.customer_id and catalog_images(entity_type, entity_id, deleted_at, sort_order).
- Migrations must preserve old orders even when an area or photo is archived; null-snapshot migrations must use safe defaults and must never reprice old orders. Follow exact units (paisa, not rupees), UTC timestamps, and existing drift migration/version controls.


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 17 — Financial integrity, event accounting, audit and invariants

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Source-of-truth principle

A posted order/purchase/payment/refund/cash handover/salary payout is a durable source document. Users may correct erroneous postings through an authorized **reversal** linked to original and then post the replacement. Historical rows remain accessible. Dashboard totals are derived from ledgers, not directly edited "current balance" values.

## Money units and rounding

PKR stored integer paisa; quote display in Rs. with configured rounding policy. Percent discounts computed at defined line/order step with deterministic tax allocation. Round exactly once at specified boundary, not repeated across widgets. Never mix base decimal quantity with PKR amount as floating-point doubles. Sales totals formula: sum(line base + modifier/upgrade charges) − applied discounts + applied taxes (depending inclusive/exclusive configured policy) + order fee adjustments − other explicit credits = payable. Tax rules are business-configured; not hardcoded.

## Supplier account payable

`Supplier outstanding = opening payable + posted purchases + debit adjustments − posted payments − supplier returns/credit notes − authorized reversals (signed appropriately)`. Status from positive purchase/payment event totals, not a string. Supplier payment originating in drawer creates a single cash pay-out movement. Supplier purchase on credit affects stock and payable even if cash not spent yet.

## Cash drawer

`Expected cash = opening physical float + direct cash customer tender received − cash change returned + accepted rider cash handovers + approved pay-ins − authorized pay-outs − cash refunds − cash drops`.

Avoid duplicate representation: a cash tender may internally create a cash movement of net retained cash, or separate received/change entries, but the expected cash query must include **exactly one net contribution**. Both are legitimate implementations; choose one consistently, with test fixtures and explanation. Supplier cash settlement, salary payment and petty cash are cash pay-outs linked to their own business transaction—not a second unlinked expense. Actual = cashier counted notes/coins. Variance = actual − expected. Variance review never silently updates actual drawer movements.

## Rider receivable

`Trip/order COD receivable = expected customer cash collection − customer payments allocated − authorized allowances/reversals` depending event flow. Rider liability to restaurant tracks cash confirmed collected but not physically handed over. On rider cash handover: cash drawer ↑, rider liability ↓; no new sale. Shortage remains rider receivable/exception until resolved. When customer actually never paid, keep customer/order receivable rather than assigning fake rider theft.

## Stock

`On hand(q) = opening + receipts + approved returns + counted positive adjustments − order BOM consumption − packaging use − wastage − supplier returns − negative adjustments`. Every component movement source idempotent; a sale with deal choices decomposes exact ingredient quantities once. Prepared/cooked canceled product should **not** be automatically restocked; create waste reason/explicit disposition. Inventory valuation uses configured costing method and event-time cost snapshots. Missing costing data is `unknown`, never 0 by convenience.

## Salary and operating expenses

Accrual basis: salary earned is payroll expense/liability, payout reduces cash and liability. Salary advance pays cash and creates advance recoverable, not instantly another salary expense. Recovering an advance against salary reduces salary payable and advance receivable; this settlement has no second cash payout. Cash petty expenses are categorized operating costs; procurement for inventory produces inventory asset/cost layers and supplier payable; do not double-count purchased goods as immediate expense and COGS.

## Ledger posting abstraction

For each financial business command define: transaction id, source type, source id, actor/session, business day, value timestamp, ledger postings, cash movement (if applicable), stock movements (if applicable), approval evidence, idempotency key and reversal reference. When using a double-entry general ledger, every journal transaction must satisfy `sum(debits) == sum(credits)`. A practical initial system can use strongly reconciled separate subledgers, but every material report must have a cross-subledger reconciliation test and accounting method statement.

## Event-state invariants [INT-01…14]

1. No two committed orders share token number within a business day; daily sequence reset exactly once at day creation.
2. One confirmed order intent maps to one committed sale and one matching BOM posting set.
3. Held order never creates revenue, stock consumption or sale token.
4. Customer delivery completed does not automatically mean customer paid.
5. Cash from riders counts only after handover accepted by a shift/drawer.
6. Supplier credit increase never changes drawer expected cash without actual payment.
7. Every posted purchase receipt has linked supplier posting (or explicitly paid cash purchase with correct source).
8. Expense with drawer cash has exactly one cash pay-out, not two.
9. A consumed recipe cannot be reversed twice or restocked cooked food automatically.
10. A salary advance is not salary expense and later repayment is not negative expense without policy.
11. Every adjustment/refund/void/stock correction has actor, reason, original reference and applicable approver.
12. Unauthorized role cannot mutate via direct domain method even if UI hides action.
13. After migration, backup restore or power interruption, ledger and projections reconcile to same totals.
14. Account/report balances never result from editing a cached total directly.

## Audit event design

Audit metadata: event ID, UTC timestamp, business-day id, terminal/app version, acting staff/session, approving staff (where relevant), entity type/id, action, reason, sanitized before/after snapshots/hashes, transaction id and result. No raw PIN, connection secrets or full payment credentials. Tamper-evident hash chain over audit batches is recommended, but local single-machine physical admin control limits guarantees; export/signed archival adds deterrence. Reports can filter approvals, failed logins, category edits, shortcut changes, archived records, post-close adjustments and reversal chains.

## Close and reconciliation procedure

Before Z report: compare orders/allocations/refunds, cash movements/shift counts, rider receivables, supplier invoices/payments/returns, inventory movement summations, salary payments and source accounts. Display unresolved differences and severity, not silently force report to balance. Final close snapshots totals, stores version/hash, releases next business-day creation, then schedules backups/exports independent of close transaction.

## Separation of financial close from message delivery

A business-day close and its immutable financial snapshot MUST remain valid regardless of PDF generation, backup, email, or WhatsApp delivery outcome. Delivery notifications do not create cash, sales, inventory, supplier or payroll ledger entries. Duplicate jobs can generate duplicate messages but must NEVER generate duplicate financial postings. Report versions and source posting event cutoffs are recorded for reconciliation; audit every recipient/configuration change and manual resend. Differentiate message `accepted_by_provider` from verified `delivered` and log ambiguous result as such.


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 18 — Security, privacy, backups, recovery and reliability

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Security threat model

Assume machine accessible to staff, local offline operation, possible shared Windows login and occasional physical access by an attacker. A short PIN is convenience authentication **not a substitute for OS disk encryption or Windows account security**. Protect the database directory by Windows ACLs, strongly recommend BitLocker for machine volume, avoid storing secrets in SQLite, protect backups and staff/customer data from casual copying.

## Authentication implementation

- Each credentialed user has random per-credential salt and a slow password-based verifier (Argon2id via vetted library preferred; PBKDF2-HMAC-SHA256 with calibrated work factor acceptable for deployment constraints). 4–8 digit PINs are inherently low entropy; **per-user/drawer/device lockouts and rate limits are mandatory**.
- For uniqueness checks without plaintext, compute a keyed deterministic HMAC fingerprint of normalized PIN with a key stored via Windows DPAPI; unique equality lookup on active fingerprints. A pepper key must not be stored in SQLite or unencrypted config.
- Owner initial setup: no predefined 0000/1234 account. Validate user-confirmed PIN with anti-trivial-PIN policy (e.g., reject repeated digits/obvious sequential patterns if approved), securely initialize recovery method, record onboarding event.
- Offline brute force resistance: persisted failed counts and per-device delay, not in-memory-only counters. Account recovery requires owner-protected mechanism, with first Manager last-resort recovery procedure documented before deployment.
- Supervisor approval PIN not persisted in UI form; clear bytes on dismissal; audit approved action, never PIN content. Auth sessions auto-lock and invalidate on staff removal/role downgrade.
- Scope manager-only changes: Manager accounts, master security settings, backup restore, system encryption keys and shortcut control.

## Windows data protection

Pick app data location via platform APIs. SQLite database and attachments under restricted directory, enforce file ownership/ACLs for intended operators. DPAPI binds encryption key to install/service identity; recovery backups must include separately secured key restoration process or deliberately encrypt DB independent of DPAPI—document and test on replacement hardware. Windows OS security and backup drive physical protection are part of deployment checklist.

## Backup [BKP-01…12]

Backup is not simply `copy pos.db` while live WAL is active. Use SQLite online backup API or properly checkpointed snapshot; include all necessary WAL/page data in consistent archive. Write temp → checksum → integrity test → atomic archive rename; retain metadata schema version, business day, UTC time, app version, file size/hash, validation state and encryption envelope. Backup after day-close and configured periodic backups, plus before app migration/restore. Retention policy: daily/weekly/monthly copies, capacity check, optional removable drive and encrypted secondary off-machine destination. Drive disconnected → report pending/failed backup but do not falsely claim success. Optionally require successful backup to close day only if owner explicitly configures and runtime permits safe fallback.

## Restore [RST-01…12]

manager-only restore wizard: choose validated backup → show backup date/schema/day/time and affected data → warn that current transactions will be replaced → create pre-restore snapshot → gracefully stop writer / close SQLite → verify archive checksum/integrity and compatibility → restore atomically → migrate if necessary → run `integrity_check`, `foreign_key_check`, ledger reconciliations and authentication key check → resume. On failure automatically restore pre-restore snapshot and present explicit fault. Verify restore on replacement hardware in release readiness drills.

## Data lifecycle / privacy

Access customer phone/address only when necessary; mask in reports by default. Limit log file retention, redact secrets and personal payment data; don't put full addresses/phones into diagnostics or telemetry by default. Export owner reports may contain personally identifiable customer data only if explicitly requested and permitted. GDPR/local legal compliance decisions should be reviewed for jurisdiction; this is a software requirement specification, not legal advice.

## Failure-mode behavior

- **Power outage at checkout:** SQLite commit all or nothing; re-open returns completed idempotent result or original editable cart if not posted.
- **Disk full:** block new posting safely, preserve existing DB, surface urgent message and backup space check; do not pretend an order saved.
- **Partial file corruption:** restore wizard and read-only diagnostics; do not reset DB automatically.
- **Missing backup destination:** local secondary retries and visible owner alert, not blocking cashier unless policy dictates.
- **Unexpected close during pay-out:** one idempotent cash event or none.
- **Time skew:** persist UTC, business day chosen explicitly; warn on implausible clock drift and prohibit double day IDs.
- **Database migration failure:** pre-migration rollback snapshot, safe launch read-only/repair path and logs.

## Security/recovery acceptance

Raw PIN absent from DB/backup/logs; duplicate PIN rejected securely; wrong attempts throttle after restart; manager-only privileges enforced; cash/stock ledger unchanged by unauthorized direct command; restore from last verified archive on separate test machine with secret recovery; order totals and report Z reconcile after restore; simulated disk full and abrupt process kill do not double-post.

## External report transmission security

- Owner-approved recipient allowlist, destination verification/consent (especially WhatsApp), access audits, data minimization and retention limits for financial attachments.
- Delivery-provider credentials protected using OS or server secrets storage; never include PINs, API secrets, raw database path, raw customer addresses or unnecessary individual payroll details in default external summary.
- Sensitive report artifacts protected at rest; consider signed temporary secure download link or encrypted PDF/XLSX transport policy as approved, in addition to normal TLS sending.
- Provider failures are sanitized in UI/logs; include message ID and status only when non-sensitive. Report resend privilege and cancellation audited.
- Offline queue and report artifacts included in disaster-recovery planning. Restoring a backup must not replay all already accepted external sends without idempotency reconciliation.


## v7 image security and backup integrity

Accept only supported raster image types via magic-byte/decode validation, enforce max upload count/file bytes and decoded pixel limit, sanitize all image output with re-encode and strip EXIF (especially GPS), block path traversal, never open raw uploads as executable content. Media directory access is limited to application service; original photos and thumbnails should be included in backup/restore consistency verification. Maintain stable image IDs and database-relative paths. Deleted images should be tombstoned while dependent backup/retry jobs settle; keep media cleanup recoverable.


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 19 — Automated tests, user acceptance and release criteria

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Test pyramid

- **Unit:** money/tax/rounding, catalog/deal expansion, recipe/packaging, unit conversion, supplier status, cash expected/variance, salary/advance math, report formula, role permission, shortcut context.
- **Repository/transaction:** real in-memory or temporary SQLite + Drift migration; foreign keys, order atomicity/idempotency, cross-ledger postings, concurrent stale versions and recovery.
- **Widget:** cashier at 1366×768; PIN entry; deals/modal focus; customer lookup; supplier item creation; expense category CRUD; staff PIN unique validation; report filter; error states.
- **Integration/E2E:** start from fresh onboarding through opening shifts, sales, dispatch, supplier purchase, stock count, expenses, cash close, Z-report, backup/restore and app restart.
- **Mutation/property tests:** retry every posted command twice; `sum(posted ledger)` invariants after randomized sequences; partial payments and reversals; valuation and unit conversion precision.

## Test data fixture

Create realistic PKR test dataset: 5 categories, 35 products, 6 deals, 30 stock SKUs (ingredients and packaging), 4 supplier mappings (including custom supply item), 10 staff across roles, 100 customers with area/address, 500 orders across multiple business days, 20 rider trips, 20 expense categories, 40 purchases, partial Khata payments, salary advances, 3 stock count sessions and deliberate bad-event attempts. In production install, never seed sample sales.

## Critical acceptance scenario catalog

| ID | Given / action | Expected result |
|---|---|---|
| AUTH-001 | Owner onboarding from fresh DB | Manager PIN and secure key created; no vendor default PIN, no duplicate owner wizard |
| AUTH-002 | Supervisor creates cashier then same PIN for another supervisor | Unique collision blocked; no identity leaked; old user unaffected |
| AUTH-003 | Supervisor tries to promote a cashier to Owner | Denied in UI and service layer; auditable attempt |
| AUTH-004 | Five incorrect login attempts, app restarted | Persisted rate limit/throttle remains enforced |
| POS-001 | Add ordinary burger item by tile click | Cart updates immediately, no modal or page scroll |
| POS-002 | Open delivery and search phone in +92 form | Existing 03… customer recognized; select address |
| POS-003 | Hold with configured deal choices then restart | Held draft persists and recalls, no paid order/stock deduction/token |
| POS-004 | Copy repeat customer's old order whose deal is archived | Warning and replacement choice; never silently charges old amount |
| POS-005 | Supervisor enables new active 10% preset | Visible in cashier without relogin; rule and min spend enforced |
| POS-006 | Invalid discount, split payment or under-tender | Service rejects; cart stays intact; actionable message |
| POS-007 | Rapidly click Confirm 3 times or restart mid-commit | Exactly one order, token and inventory posting set |
| POS-008 | Remap F3 to new action; type in search field | Shortcut works only outside input; no action while typing |
| POS-009 | Checkout under configured soft-stock mode at zero | Order posted, negative stock warning/event retained |
| DEAL-001 | Create build-your-own deal with required drink selection | Missing drink blocks add; valid choice uses one parent price plus upgrades |
| DEAL-002 | Deactivate deal used in historic sale | Hidden in new POS; historic sale and reports unchanged |
| STK-001 | New supplier defines `Charcoal` custom stock item | Item created with type/unit; linked to supplier and selectable for purchase |
| STK-002 | Purchase item not supplied by selected supplier | Rejected in UI and service, with mapping-edit path |
| STK-003 | Purchase 2.5kg, recipe uses 150g | Stock movement/base units correct with decimal precision |
| STK-004 | Count opened; purchase posted; count submitted | No stale balance overwrite; snapshot recalculation or recount |
| STK-005 | Failed cooked delivery cancelled | No automatic ingredient restock; waste/refund decision recorded |
| SUP-001 | Supplier purchases exist, zero paid | Status `No payments`; credit ledger still shows amount owed |
| SUP-002 | Supplier invoice Rs.8,000, pays Rs.3,000 cash | Payable Rs.5,000; one drawer cash out; `Partially paid` |
| SUP-003 | Pay remaining Rs.5,000 from bank | `Paid`; no additional drawer movement |
| SUP-004 | Supplier with payable is deleted | Hard-delete rejected; archive allowed and payable reportable |
| EXP-001 | Supervisor creates, renames unused expense category | New name available for new expenses; audited |
| EXP-002 | Category referenced by posted expense is deleted | Hard-delete denied; archive supported, history intact |
| EXP-003 | Create Rs.500 cash expense then retry same request | One expense and one Rs.500 cash-out only |
| CASH-001 | Shift starts float Rs.5,000 and cash sale Rs.1,000 with Rs.200 change | Closing expected Rs.5,800 prior other movements |
| CASH-002 | Cashier blind closes shift | Expected cash not visible before submit; variance afterward |
| CASH-003 | Short shift Rs.300, next staff arrives | Review flag persists; authorized next shift can open |
| DEL-001 | Mark COD order Delivered with no payment | Order Delivered but Unpaid; no rider cash received yet |
| DEL-002 | Rider trip has 1 prepaid and 1 COD order | Expected handover includes COD only |
| DEL-003 | Rider pays part of expected handover | Remaining shortage/liability tracked; drawer receives only actual |
| DEL-004 | Failed delivery reattempt next business day | One original sale, attempt lineage, no duplicate sale ingredients |
| PAY-001 | Salary accrual + cash advance + bank salary payout | Liability/recoverable correct, drawer only decreases for cash advance |
| PAY-002 | Salaried employee with ledger history deleted | Hard delete rejected; archived and still traceable |
| ORD-001 | Void order after cooking | Refund and waste handled explicitly, stock not blindly restored |
| ORD-002 | Attempt repeat refund against already refunded amount | Rejected; no duplicate cash refund |
| REP-001 | Sales report custom business date across midnight | Attribution by business day, not calendar date |
| REP-002 | Supplier credit inventory purchase in profit view | Recognizes inventory/payable, not cash expense or automatic COGS |
| REP-003 | Recipe cost unknown | Profit report displays missing coverage, not invented profit |
| REP-004 | Export report with selected filters | Row/detail totals match on-screen results, no PIN/secret leakage |
| BKP-001 | Backup during active WAL write | Verified consistent restoration, no broken DB |
| BKP-002 | Simulate corrupted backup | Restore blocked, original live DB untouched |
| BKP-003 | App upgrade with old data | Forward migration and totals retain original balances |
| SEC-001 | Cashier invokes supervisor command through shortcut/repository | Permission denied, audit metadata captured |

## Performance and cashier usability

On target Windows PC: ten test orders (basic, repeat, deal, dine-in, delivery COD, discount, split, held, rider assignment, canceled), no full-page vertical scrolling during typical cashier billing at 1366×768 and 125% scaling; essential actions reachable by keyboard; demonstrate basic order within 15–30 seconds after cashier familiarization (provisional target, validate with staff). Confirm accessible focus for category/menu grid and modal. Test 100 products and 12 cart lines.

## Release signoff checklist

- [ ] Every domain requirement has at least one automated acceptance test; tests run in CI on Windows runner.
- [ ] No plaintext PIN or unredacted secrets in DB/logs; role escalation blocked and unique PIN guaranteed.
- [ ] Decimal money and unit math independently checked with fixtures.
- [ ] All posted operations have idempotency / reversal behavior and crash simulation.
- [ ] Closing cash, supplier credit, rider remittance, payroll and stock totals reconcile to ledger.
- [ ] No kitchen tickets, kitchen print or kitchen dashboard accidentally enabled.
- [ ] Customer loyalty/rewards absent from initial active flows.
- [ ] Stock/purchase/expense/staff/menu/deal CRUD and archival work across app restart.
- [ ] Export CSV/Excel/PDF opened in Windows applications; totals correct.
- [ ] Encrypted/verifiable backup created and successfully restored on test hardware.
- [ ] Production install includes secure first-run onboarding, privacy/error notices, backup destination and operational user guide.

## Report delivery and expanded role QA references

See `29-comprehensive-qa-and-real-restaurant-walkthrough.md` and `25-business-day-report-email-whatsapp-delivery.md`. Release-blocking tests: offline day close with PDF/XLSX and queued email; restart then single delivery; wrong recipient denial; source file missing and retry; duplicate close click; ambiguous provider accepted state; no PIN/API key leak; message failure doesn't reopen day; supervisor can edit/delete unused expense categories but not Manager account; supervisor can CRUD menu/deals; cashier can't alter global shortcuts; supplier custom supplied-item auto-filter persisted.

## v5 regression acceptance

- Manager creates an inventory-using menu item without a recipe: can save inactive draft but activation and cashier visibility are blocked, with an explanatory error.
- Manager completes ingredient, base-unit and quantity rows then activates item: cashier can sell it and all ingredient quantities are deducted exactly once even if stock is negative.
- Manager builds combo with a missing-recipe component/selection: cannot activate. Once every choice path is recipe-complete, preview expands components and final sale deducts each included ingredient exactly once.
- Cashier chooses JazzCash, Easypaisa, Bank/Raast or Card: only method selection, optional reference and Complete payment; no Unverified, Processing, gateway verification UI or official API dependency; paid entry and audit saved.
- Cashier chooses COD: unpaid/collection due is preserved; this is a receivable status, not gateway verification.


## v7 acceptance tests — customer workflow, areas, pictures

1. Cashier adds three items and clicks Continue — Customer; no order/token/stock movement exists yet. Enter delivery name/phone/area/address; payment and final commit atomically link customer and immutable address and delivery-fee snapshot.
2. Existing caller number lookup lists saved addresses; choosing address fills known area and house; no accidental duplicate person is created.
3. Delivery requires enabled serviceable zone; Manager deactivates zone mid-flow; Cashier final save fails with recoverable area-selection message without losing cart.
4. Manager creates new serviceable area with fee 250 PKR, cashier selects it, checkout total adds 25,000 paisa; past orders remain at their former fee if Manager later edits zone.
5. Manager archives historical service area; it disappears from new orders but previous orders, reports and references survive.
6. Manager creates recipe-complete menu item with no image; publication and sale succeed, cart is fast and fallback works.
7. Manager uploads 3 valid product images and chooses primary; thumbnails persist after restart and appear on cashier tile. Replace/delete operations preserve order/BOM data.
8. Deal can have multiple optional images; missing pictures never prevent deal activation if each recipe is valid.
9. Oversized/invalid image rejected before database write; EXIF sensitive location stripped; disabled filenames/paths cannot escape app media directory.
10. Offline POS boots and loads cached menu pictures without external API; image failures do not block order entry.
11. Security: Cashier cannot manage delivery zones/photos, Manager cannot enter or finalize a sale.
12. No double token/stock posting on pressing Continue multiple times or retrying final save.


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 20 — Development milestones, dependencies and definition of done

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Guiding release strategy

Build fully working vertical slices, not isolated UI screens. Each slice includes schema + transaction service + Riverpod state + Flutter UI + tests + recovery/audit. Do not wire the HTML demo directly into production.

## Milestone 0 — Product decisions and scaffolding

- Confirm policy choices in `22-decisions-and-assumptions.md`: tax, rounding, refund authorizations, negative stock, register ownership, employee pay terms, supplier units and backup key recovery.
- Flutter Windows repo, lint rules, CI, theming, Drift migrations, telemetry/log redaction, development fixtures and UAT plan.
- Deliver a signed-off data model for posted events **before** making any monetary transaction persistent.
- Gate: base repo builds/runs on target Windows hardware; migrations and backup architecture smoke-tested.

## Milestone 1 — Auth, settings, staff, catalog

- Guided owner creation; PIN secure verify, uniqueness, rate limits; staff/department CRUD and roles; business day creation/shift opening.
- Menu categories/products/modifiers/deals and recipes/BOM; supervisor discount presets; owner shortcut registry + quick action config.
- Gate: cashier can log in; supervisor adds a burger/deal/discount that becomes visible in cashier; staff PIN/role tests pass.

## Milestone 2 — Fast counter orders and customer flows

- 1366×768 POS optimized interaction; customer phone/address and repeat order; hold/recall persistence; delivery/takeaway/dine-in; split/COD/methods; immutable order commit with discount/recipe/packaging snapshots.
- Manual prep/ready/fulfillment milestones; digital receipt optional. No kitchen print.
- Gate: ten sample orders, crash/retry single commit, no full-page scroll, accurate tender/change and recipe deduction.

## Milestone 3 — Delivery / rider / cash

- Rider staff, trip assignments, failure/return/reattempts, cash handover/shortage, delivery & payment state separation.
- Shift cashier cash pay-in/out, blind counts, X report, non-blocking discrepancies; expense categories and petty cash CRUD.
- Gate: one COD rider trip and shift handover reconcile, category CRUD and correction audit pass.

## Milestone 4 — Inventory / purchasing / supplier Khata

- Inventory item CRUD and base unit conversion, packaging, movement ledger, wastage, low stock, physical counting and adjustments.
- Supplier CRUD with custom supplied-item creation, supplier-item mapping, filtered multi-line purchase, cost capture, payment sources and Khata aging.
- Gate: new custom supply item → purchase → stock + supplier payable → drawer/bank partial payments → paid status; no duplication; return/reversal tests pass.

## Milestone 5 — Payroll / exceptions / comprehensive reports

- Staff salary terms, accrual, advances/payment and edits/archive; request/approve voids/refunds and discrepancies; owner exception dashboard.
- Report explorer with comprehensive family reports, saved filters, trend charts, financial formula definitions, provenance and Excel/CSV/PDF export.
- Gate: owner answers "what sold, what was spent, what is owed, what is missing, where margin exists" with drill-down to underlying transactions; no invented profit.

## Milestone 6 — Hardening and Windows rollout

- Backup scheduler, restore wizard, install/update migration, disk-full failure, power-loss simulation, long-shift/late-night cases, security review, performance, accessibility and crash tests.
- Train owner, supervisor and cashier on local instance; test repeated end-of-day close and restore from offline backup.
- Gate: final checklist in `19-testing-and-acceptance.md`, verified installer, release notes, rollback method, privacy/retention settings, at least one complete production-like shadow run.

## Suggested development tickets per module

For each file `03`–`13`: (1) migrations, (2) pure domain calculations/guards, (3) service posting and rollback, (4) list/search, (5) create/edit/archive/detail UI, (6) audit trail, (7) happy-path integration test, (8) edge/retry/security test, (9) owner UAT. Ticket must cite requirement IDs and test IDs; indicate dependency/migration version.

## Nonblocking scope decisions

Optional future integrations can be left behind feature/service adapters: kitchen/receipt hardware, card gateway, cloud multi-terminal, customer rewards, rider app, accountant integration. Do not delay first operational release just to add these. Do not implement nonfunctional buttons masquerading as supported features.

## Launch operations checklist

Create owner and supervisor accounts, test unique PIN, verify full menu/prices/BOM and packaging, import opening stock with explicit costing, register supplier Khata opening balances, configure payment methods and expense categories, train staff, set keyboard shortcuts, select backup location, verify restore in test DB, agree day/shift closing procedure, run sample sale/refund/rider handover and compare all ledgers before real transactions.

## Report-delivery implementation task extension

Before production release implement local Z-report snapshot + PDF/XLSX artifacts and persistent delivery outbox; add owner recipient configuration, approved supervisor manual send, email transport with safe retries, test delivery, delivery history and crash/restart tests. Manual WhatsApp share is optional first-release UX. Official automated WhatsApp integration is a provider-dependent milestone requiring business account, template, recipient permission, secure relay and budget signoff. Add `SEND-*` integration tests into final release gate. Deliver owner documentation explaining difference between local queued messages and messages actually sent while PC is powered down.


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 21 — Owner report formulas and metric dictionary

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


Every metric shown in UI/Excel/PDF must disclose its calculation and reporting date basis. Queries aggregate **posted events** only (reversal offsets applied). `Business day` is default for operations; UTC timestamp is retained for audit.

| Metric | Exact definition / warning |
|---|---|
| Gross order value | Sum original committed item + modifier/deal prices before discounts and excluding canceled/unrecognized lines according to selectable view; always state inclusion policy. |
| Applied discount | Sum authorized discounts by scope/line and order, capped by rule; refunded discount allocations reversed accordingly. |
| Net order sales | Tax-base-adjusted recognized sales of committed fulfilled/valid orders net of discounts, cancellations and refunds according to selected recognition policy; delivery fee and tax shown separately. |
| Tax collected/payable | Sum posted transaction-time allocated tax with refund/adjustment reversals; configuration-specific inclusive/exclusive rules. |
| Cash collected | Net **actual customer cash tender** plus rider handovers accepted, separated into categories to avoid double counting. |
| Average order value | Net eligible order sales / count of included eligible orders; show denominator. COD/unfulfilled exclusion according to mode policy. |
| Orders per hour | Number of committed orders grouped by order creation hour in Asia/Karachi; separate business-day grouping when day crosses midnight. |
| Discount utilization | Eligible orders where preset used / eligible committed orders; report rate and absolute Rs. given. |
| Repeat customer rate | Number of distinct customers with >=2 orders in selected range / customers with >=1; guest/unknown excluded. |
| Delivery failure rate | Unique delivery orders with final failed outcome / dispatched delivery orders in selected period, with reattempts separately counted. |
| Prep time | `ready_at − confirmed_at` (or preparing_at→ready_at with stated definition); excludes missing timestamp orders from percentile, shows coverage. |
| Rider travel time | `delivered_at − dispatched_at` for valid timestamps; distinguish trip stop order from order delivery. |
| Rider outstanding | COD customer amounts confirmed collected but not physically handed to cashier, plus shortage allocations, less accepted settlements/authorized write-offs; keep uncollected customer debt separate. |
| Supplier payable | Opening payable + invoice totals + debit notes − payments − approved credit notes/returns/reversals. |
| Supplier status | No purchases / No payments / Partially paid / Paid / Credit, as specified in `09` using posted ledger state. |
| Supplier overdue | Unpaid invoice allocations where due date < business date as-of query; bucket age (0–7, 8–30, 31–60, 60+), current not overdue separately. |
| Inventory on hand | Sum signed movement qty for item at as-of timestamp; unit dimension normalized. |
| Physical stock variance | Counted normalized qty minus expected normalized ledger qty at count snapshot reference. |
| Waste cost | Wasted qty × item unit cost at event timestamp based on selected costing model; missing cost flagged. |
| Product ingredient COGS | Recipe consumption qty × cost-layer unit cost, expanded by actual sold deal/modifier selections, net of allowed reversals. |
| Packaging COGS | Qty packaging consumed per fulfillment/order × event-time cost; separately identifiable in per-order margin. |
| Gross margin | Recognized net sales excluding pass-through tax − realized food/packaging COGS; show missing-cost coverage and delivery fee treatment. |
| Operating expense | Posted relevant noninventory expense accruals or valid cash expenses, excluding supplier inventory purchase capitalization and avoiding payroll double counting. |
| Salary due | Accrued gross salary + approved additions − salary payments − advance settlements/deductions; advances are distinct recoverables. |
| Net operating result | Net sales + recognized other operating income − COGS − operating expenses − recognized staff costs − other allocated business costs, **only with adequate period allocation and data coverage**. Otherwise `Cannot calculate reliably`. |
| Expected drawer cash | Opening float + net customer cash − cash refunds + accepted rider cash + approved pay-ins − pay-outs/drops; reconciled per actual shift. |
| Drawer variance | Physical counted cash − expected closing cash. Display signed shortage/overage and review state. |
| Cash expense by category | Sum posted unreversed expense amount in category IDs, respecting category history/label snapshots and funding source. |
| Void/cancel rate | Count of committed orders canceled or voided / total committed orders for cohort and period; include or exclude drafts clearly. |
| Low stock | Item on-hand <= configured threshold in base unit; all negative stock as separate warning. |

## Metric quality badges (UI text, not ornamental badges)

- **Complete**: all input data present and reconciliation passed.
- **Estimated**: source cost method approximate or operational timestamps incomplete; tooltip explains.
- **Missing data**: exclude value from aggregate or flag as incomplete, never silently treat missing input as zero.
- **Not applicable**: denominator 0 or category not enabled.

## Drill-down contract

Clicking net sales opens order/line postings, discounts/refunds. Supplier payable opens invoices/payment allocations. Gross margin opens recipe versions and inventory cost layers. Cash variance opens shift/count and movements. Rider shortage opens trip/order/handovers. This must work even for archived products/staff/suppliers and after report export.

## Export metadata

All files carry report name, generated UTC/local time, business-day range, active filters, totals/row count, data-quality status, currency, time zone, schema/report formula version and generated-by staff. CSV newline and Excel injection prevention: prefix dangerous spreadsheet formula leading characters in text fields to keep exports safe; preserve numeric monetary columns as actual numbers formatted as currency in Excel.


---


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


---


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


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 24 — Exhaustive role permissions matrix (v4)

**Authoritative:** exactly two application roles, **Cashier (C)** and **Supervisor/Owner = Manager (M)**. No separate Owner or Supervisor permission group. **M cannot perform cashier operations.** Every command enforces this in service layer, independent of routing and shortcuts. A separately authenticated manager may approve a cashier's request, but does not execute the cashier operation as themselves.

Notation: **Y** = allowed; **N** = denied; **P** = business-configured; **A** = may request action requiring Manager approval; **V** = view only.

| ID | Domain / Action | C | M | Implementation rule |
|---|---|:---:|:---:|---|
| AUTH-01 | PIN login and session lock | Y | Y | Active, unique credential |
| AUTH-02 | Create Cashier login | N | Y | PIN uniqueness and audit |
| AUTH-03 | Create another Manager login | N | Y | Same exact role, reauthentication |
| AUTH-04 | Reset/deactivate a staff PIN | N | Y | No PIN exposure |
| AUTH-05 | Configure auth, audit, backup policy | N | Y | High-risk confirmation |
| POS-01 | Create/edit an order cart | Y | N | M denied even via service |
| POS-02 | Add/remove item, modifiers and deals to cart | Y | N | Transaction is cashier-only |
| POS-03 | Hold, recall, abandon drafts | Y | N | Session/ownership rules |
| POS-04 | Customer phone lookup for billing and repeat order | Y | N | M may see management customer analytics only |
| POS-05 | Apply published discount to current bill | Y | N | Presets configured by M |
| POS-06 | Receive cash/card/wallet/split payment | Y | N | M cannot cashier checkout |
| POS-07 | Confirm bill/allocate daily token | Y | N | Shift open; atomic posting |
| POS-08 | Print/share customer receipt if later enabled | Y | N | No kitchen ticket feature |
| ORDER-01 | Update live prep/ready/out for delivery/delivered | Y | N | M oversight view only |
| ORDER-02 | Review any order and history | P | V | C own/assigned only |
| ORDER-03 | Edit/remove/change confirmed order items, modifiers, quantity | Y | N | No manager PIN; append revision/event + financial and inventory deltas |
| ORDER-03B | Cancel confirmed order | Y | N | No manager PIN; mandatory reason, stage and stock disposition, audit |
| ORDER-03C | Record a legitimate refund of collected funds | Y | N | No routine manager PIN; bounded by net paid/refundable amount; real tender movement and audit |
| ORDER-04 | Review order amendments/cancellations/refunds | N | Y | Post-facto oversight; no routine authorization step |
| DEL-01 | Assign rider/dispatch trip | P | N | C operational action |
| DEL-02 | Record failed delivery/redispatch | P | N | C operational action |
| DEL-03 | Receive rider COD cash at counter | P | N | C cashier shift event |
| DEL-04 | Review rider shortages/approve writeoff | N | Y | M managerial approval/adjustment |
| SHIFT-01 | Open own cashier shift and float | Y | N | Business day must be open |
| SHIFT-02 | Count and submit own blind closing drawer | Y | N | Hide expected until submission |
| SHIFT-03 | View/review shift reconciliation and variances | N | Y | M cannot submit C's count |
| DAY-01 | Open business day | N | Y | Manager workflow |
| DAY-02 | Close/lock business day, approve Z | N | Y | Manager workflow |
| MENU-01 | CRUD menu item/category/modifier | N | Y | Price/version audit |
| MENU-02 | CRUD deals and recipes/BOM | N | Y | Deactivate rather than delete referenced |
| MENU-03 | CRUD discount presets | N | Y | Eligible presets visible to cashier |
| STK-01 | CRUD raw ingredients and packaging | N | Y | Supplied item mappings |
| STK-02 | Stock purchases/receipts, transfers, wastage | N | Y | Append-only stock ledger |
| STK-03 | Physical counts and post adjustments | N | Y | Snapshot/reconciliation |
| SUP-01 | CRUD supplier and supplied catalog | N | Y | Arbitrary custom supplied items |
| SUP-02 | Record purchase on cash/credit | N | Y | Inventory and payable atomic |
| SUP-03 | Supplier payments/Khata and reversals | N | Y | Explicit payment source |
| CASH-01 | Pay in/out operational shift drawer | P | N | Cashier own shift; reason |
| CASH-02 | Create operational petty cash request | P | N | Configurable approval policy |
| CASH-03 | CRUD expense categories | N | Y | Archive if used |
| CASH-04 | Create/approve/void administrative expense | N | Y | Management ledger action |
| STAFF-01 | CRUD employee profile/department | N | Y | Archive linked history |
| STAFF-02 | Manage monthly salary, advances, ledger | N | Y | Reverse posted errors |
| STAFF-03 | Create Manager PIN/account | N | Y | Same Manager role, extra confirmation |
| REP-01 | Own shift summary | P | N | Only appropriate operational figures |
| REP-02 | All financial/profitability reports | N | Y | Filters/export/revisions |
| REP-03 | Generate/email/WhatsApp daily report | N | Y | Approved recipients and durable outbox |
| SET-01 | Shortcut/quick-action layout config | N | Y | C may invoke only cashier actions |
| SET-02 | Feature flags/general settings | N | Y | Do not erase in-flight/history |
| SEC-01 | View audit and security incidents | N | Y | Confidential |
| SEC-02 | Edit/delete audit rows | N | N | Impossible |
| FIN-01 | Silently delete posted ledger or historic order | N | N | Reverse/adjust with traceability |

## Navigation and independent execution

**Cashier application shell:** Cashier POS, Held Orders, Customer Lookup, Live Orders/Delivery, Rider Handover, Own Cash Shift/Count, limited own activity. No management shortcuts in this shell.

**Supervisor/Owner (Manager) shell:** Overview/Exceptions, Menu & Deals, Discounts, Inventory/Packaging, Suppliers & Khata, Expense Categories/Management Cash, Employees/PIN/Payroll, Shift Reconciliation, Business Day Close, Reporting/Exports, Report Distribution, Settings/Shortcut Builder, Security/Backup/Audit. **No POS checkout or cart.** Manager may inspect orders read-only to investigate and approve.

**Approval:** Ordinary confirmed-order edits, removals and cancellations **do not use an approval overlay**. Cashier performs and the system audits; Manager reviews after the fact. A distinct escalation flow, if later configured for exceptional financial cases, is not part of routine order editing/cancellation. Approval is not a role switch. Manager may reject and no posting occurs. Where dual-control between two distinct managers is required, specify a second Manager account; Supervisor/Owner label does not create a separate tier.

## Mandatory negative tests

- M cannot start cashier shift, sell products, confirm checkout, record live rider cash, hold order, edit cart, or trigger POS hotkey.
- C cannot use direct service, keyboard shortcut, deep link or hidden route to edit stock/menus/supplier/expense categories/roles.
- Manager creates another Manager with same privileges; no separate Owner screen/role appears.
- M can create, edit and archive expense category, menu, deal and supplier records; linked financial records remain immutable.
- Cashier confirmed-order amendment and cancellation proceed without manager PIN and record every change; any actual refund stays bounded and traceable.
- An exceptional manager approval, where later configured, never changes cashier identity or duplicates posting.


## v7 additional role permissions

| Action | Cashier | Manager (Supervisor=Owner) | Rule |
|---|---|---|---|
| Enter items into draft cart | Yes | No | No token yet |
| Open customer-details step and select/create customer/address | Yes | No | Order operation |
| Select serviceable delivery area | Yes | No | Must be enabled/allowed at final commit |
| Override unavailable area or alter fee | No | No as part of cashier sale | Manager can adjust zone policy from settings; Cashier must reselect |
| Create, edit, enable/disable, archive delivery area | No | Yes | Audit, preserve historical snapshot |
| Upload/replace/reorder/delete menu item photos | No | Yes | Optional, secure offline gallery |
| Upload/replace/reorder/delete deal photos | No | Yes | Optional, recipe separately mandatory |
| Confirm order after details and payment | Yes | No | Atomic order+customer+token+stock+tender posting |


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 25 — Automatic and manual end-of-business-day report delivery (email / WhatsApp)

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


**Feature status:** newly requested and included as a production module. Email with PDF/Excel delivery is the **recommended first-release implementation**; manual WhatsApp sharing is a practical optional first-release shortcut; automated WhatsApp Business Platform is an explicit integration phase requiring a configured provider/account, internet and appropriate recipient consent. Owner must approve final channel, pricing and retention policy. Do **not** claim that WhatsApp delivery works offline.

## 1. Goals [SEND-01…12]

- [SEND-01] On finalized business-day close, generate immutable-versioned **Z-report PDF**, detailed **XLSX workbook**, and optional **CSV** based on committed local data; include business date, timezone, restaurant, report generation time, revision/hash, and event range.
- [SEND-02] Save generated reports locally and record `report_run_id`, `business_day_id`, file path, digest, version, snapshot cutoff, creator and generated time. Day close success is independent of network delivery.
- [SEND-03] Manager configures a list of verified/approved email recipients; owner may separately approve WhatsApp recipients and their permission/consent state.
- [SEND-04] Manager configures enabled channels, attachment choices, auto-send on close, retry policy, confidential financial sections, subject/template and whether supervisors may manually resend.
- [SEND-05] Manager can select **Send now** from an authorized closed-day report and see clear delivery attempt state: Queued, Sending, Provider accepted, Confirmed delivered (only with provider evidence), Failed retryable, Failed final, Cancelled. **Provider accepted is not proof of inbox receipt.**
- [SEND-06] When offline, enqueue locally durable delivery jobs with complete immutable report references; retry later using backoff and bounded attempts. Never generate a duplicate report just to retry sending.
- [SEND-07] Idempotency: unique `business_day_id + report_revision + channel + recipient + template_version + delivery_purpose` or equivalent stable key; explicit resend creates an auditable new attempt without duplicating the original automatic job.
- [SEND-08] A failed email/WhatsApp send does not roll back a closed business day, reopen a cash shift, duplicate stock postings or change Z totals.
- [SEND-09] Report access is restricted, reports exclude PINs, credential hashes, system secrets and unnecessary customer PII; recipient email/phone and attachments treated as sensitive.
- [SEND-10] Delivery history is available to supervisor/owner; owner can disable a channel, revoke recipients and inspect retry/error reason without exposing API secrets.
- [SEND-11] If PC is powered down with a queued job, a **local-only** implementation cannot send until the Windows worker runs again. If sending must continue while store PC is off, use a cloud service *after* securely uploading and queuing the immutable artifact while internet is available.
Manager (Supervisor/Owner) is the only management role, with identical permissions for both titles; Manager can administer and approve but cannot perform cashier tasks. See chapters 01 and 24.

## 2. Operator workflows

### A. Owner one-time setup

1. **Settings → Reports → Delivery settings**. Switch on Email and/or WhatsApp, choose automatic-on-close and allowed manual resends.
2. For Email: set verified sender/domain/provider, owner recipients, CC/optional staff recipient list, PDF + Excel toggles, subject and approved summary sections. Tap **Send test report**; show delivery attempt status.
3. For WhatsApp: choose **Manual** or **Official API**. Manual opens WhatsApp/chat and allows the operator to attach file; cannot silently attach+send from a plain share link. Automatic requires a supported business provider account, sender/business phone, correct API credentials, approved message template for business-initiated delivery as required by platform rules, recipient permissions and cost/limits review.
4. Set schedule: recommended trigger **After business day successfully closes**, not at a fixed midnight. Enable additional scheduled summary only as an optional separate operation (no duplicate accounting day closure).
5. Set retry window, max attempts, retention and encryption. Save and audit changes; test delivery. Owner sees which channels are ready and any configuration blocker.

### B. Supervisor closes the day

1. Supervisor resolves or acknowledges outstanding shifts, rider cash discrepancies, supplier payables, refunds and stock exceptions according to blocking/non-blocking rules.
2. Supervisor reviews Z-report, counted cash and financial warnings; selects **Close & Lock Business Day**.
3. One atomic close transaction persists `closed_at`, `closed_by`, final totals/snapshot reference and immutable close event. Generating report artifact uses committed state; report delivery is a separate workflow.
4. PDF and XLSX are saved to local protected report storage; `report_run` and attachment checksums are recorded.
5. For each enabled approved recipient and selected channel, create an outbox record. If internet available, worker submits; if not, mark **Queued — waiting for connection**.
6. Close success view shows separately: **Business day closed**, **PDF generated**, **Excel generated**, **Email queued/sent/failed**, **WhatsApp queued/sent/failed**. A failed send cannot undo closure.
7. Supervisor can open **Reports → Delivery History** and retry permitted failed jobs. Reason must be required when deliberately resending a successfully submitted report to avoid accidental duplication.

### C. Owner receives report

Email subject example: `Restaurant — Business Day 2026-10-12 — Z Report` (business day, not necessarily calendar send date).

Message text example (illustrative values, never hard-code):

> Restaurant Daily Business Report — 12 Oct 2026  
> Net sales: Rs. 85,400  
> Orders: 78  
> Cash variance: Short Rs. 300  
> Supplier payables: Rs. 42,000  
> Pending rider cash: Rs. 3,100  
> Attachments: Z_Report_2026-10-12.pdf; Daily_Operations_2026-10-12.xlsx  
> Generated from finalized business-day records. Review exception details in the attached report.

A WhatsApp message may include a short approved summary and, using the official API when configured, send a document attachment supported by the current provider/platform constraints. Template/media requirements vary: confirm current Meta policy and limits at integration time rather than encoding assumptions in the domain.

## 3. Delivery modes and responsibilities

| Mode | Sending mechanism | Required infrastructure | What it can promise |
|---|---|---|---|
| Email automatic | HTTPS transactional email service or authenticated SMTP relay | Working internet; protected secrets; configured sender, sender reputation | Can attach PDF/XLSX and observe provider submission status |
| Email manual | Open mail client with recipients/subject and let user attach report; optional shell share | Configured mail client; human action | User-controlled sending, no automatic guarantee |
| WhatsApp manual | Open approved WhatsApp chat or share workflow | App/browser and human attaching document | Convenience only; never mark 'Sent' unless user confirms |
| WhatsApp automatic | Official WhatsApp Business Platform / supported provider | Business setup, template/recipient permission, secured integration, internet | Automated messages/documents subject to template, size, delivery and platform policies |
| Cloud relay | HTTPS upload to secure service, server processes queue and callbacks | Cloud hosting, authentication, encryption, support operation | Can keep processing after desktop goes offline **only when job was uploaded first** |

**Recommended architecture:** Flutter calls application `CloseBusinessDay` command → Drift transaction → `ReportGenerationService` writes versioned files → `ReportOutboxRepository` → Windows worker/service while app is running (optionally service independent of UI) → `EmailTransport` or `WhatsAppTransport`. For API token safety, prefer a controlled backend relay with short-lived desktop authentication; do not ship long-lived master API keys in the distributed binary.

## 4. Settings and UI contract

**Settings → Delivery:** delivery enabled; channels; sender identity; verified recipients; WhatsApp mode and approved numbers; auto-on-close; PDF/XLSX/CSV options; report section visibility; test; retry; report password/encryption/secure-link mode; recipient validation; live health/status of channel. Manager manages credentials/global recipients with audited changes.

**Close day:** report preview; generated file choices; `Email owners` and `WhatsApp owners` statuses; prevent re-closing and duplicate job creation. Show queued badge and meaningful retry time.

**Delivery History:** business date, report revision, channel, recipient (partially masked), queued time, latest attempt, provider reference, attempt count, status, sanitized error, retry action, manual resend action. Filter by status/date/channel.

## 5. Minimal logical schema

```text
report_runs(id, business_day_id, revision, snapshot_cutoff_utc, created_at_utc,
  created_by_staff_id, status, content_hash, schema_version, locked)
report_artifacts(id, report_run_id, kind[pdf|xlsx|csv], storage_path,
  size_bytes, sha256, encryption_info, created_at_utc)
report_recipients(id, channel[email|whatsapp], address_encrypted,
  masked_address, verified_at_utc, consent_basis, active, created_by)
report_delivery_policies(id, enabled, channel, purpose, auto_on_close,
  attach_pdf, attach_xlsx, attach_csv, allow_supervisor_resend,
  retry_max, retry_backoff_policy, report_scope, created_by, updated_at)
report_delivery_jobs(id, report_run_id, recipient_id, channel, purpose,
  unique_idempotency_key, requested_by, requested_at_utc,
  state, next_retry_at_utc, attempt_count, latest_error_code)
report_delivery_attempts(id, job_id, attempted_at_utc, provider_request_id,
  provider_message_id, result, sanitized_error, response_code, duration_ms)
report_delivery_events(id, job_id, source, state, provider_event_id,
  happened_at_utc, received_at_utc)
```

Use a job lease or transactional state claim to prevent two workers sending the same job concurrently. Account for a crash after the provider accepts a request but before local success is saved: stable provider idempotency keys if supported, or explicit ambiguous-delivery status requiring guarded retry.

## 6. Failure behavior and security

- **Internet disconnected on close:** local day close and file generation succeed; queued job persists, due after reconnection. Do not repeatedly prompt cashier during checkout.
- **Provider rejects credentials:** mark failed with actionable owner message; never log secret contents. Retry only after credential/configuration fix.
- **Unknown recipient, wrong number or invalid format:** owner corrects recipient; old attempts remain in log; never silently change destination of an already queued job.
- **API rate limit / temporary outage:** exponential backoff with jitter; configurable maximum; no hot polling.
- **Attachment too large:** keep immutable report and offer secure link/passworded archive policy or smaller PDF summary; disclose delivery truncation and never silently omit detailed workbook.
- **Sensitive report sent to wrong recipient:** disable destination, audit incident, rotate any exposed access credentials, apply report retention/access controls. Do not include customer phones and staff payroll details in default WhatsApp summary.
- **Reports generated more than once for the same closed day:** create explicit version/revision with old report retained and reason if corrected snapshot permitted; no silent overwrites.
- **Worker restarts mid-send:** lease expiry recovery, deduplicated attempt and ambiguous status monitoring.
- **WhatsApp read/delivery status:** only mark Delivered when real provider callback/confirmation exists; otherwise 'Submitted/Accepted' at most.
- **Backups:** report artifacts, outbox and recipient settings need backup/restoration policy. Encrypt sensitive addresses, tokens and file archives per security standard.

## 7. Acceptance scenarios [SEND-QA]

1. Offline close → PDF/XLSX persisted, email queue pending → restart app still pending → network returns → one send per recipient.
2. Business date spanning midnight appears consistently in attachment filename, title and summary.
3. Two successive close clicks result in one finalized business day and one automatic send job per recipient/channel.
4. Provider timeout after accepting submission does not cause automatic duplicate delivery without reconciliation.
5. Supervisor tries to send to unapproved email/WhatsApp number: denied; owner adds recipient: allowed and audited.
6. Email and WhatsApp recipients receive role-appropriate content; no PIN, secrets or excessive customer PII.
7. Retry a failed WhatsApp template submission gives actionable error and does not corrupt financial report.
8. Reports still show closed status when email fails or PC is turned off.
9. User changes email recipient after close: existing queued job continues to reference its verified intended recipient; new approved delivery is a new audited job.
10. Corrections to historical financial postings after close create auditable adjustment in allowed later day and/or explicitly revised report; never edit prior attachment silently.

## 8. Recommended implementation milestones

- **Phase A — MUST:** Generate PDF + XLSX, local outbox/delivery history, manager-approved email recipients, automatic + manual send and retry, no close blocking, tests.
- **Phase B — SHOULD / optional first release:** Manual WhatsApp share link and export/open file UX, safe messaging disclaimer.
- **Phase C — requires integration decision:** Official WhatsApp automatic delivery through secure backend provider, approved template and consent management, webhook event receipts and cost/rate-limit controls.


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 26 — Complete feature catalog, user handbook and cross-module behavior

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


**Audience:** restaurant owner, shift supervisor, cashier, implementation agent and QA. This chapter is the functional acceptance map, backed by detailed requirements in chapters `00–25`. It does not supersede accounting rules. **Confirmed** means requested; **Provisional** means configurable/needs owner agreement; **Future** is excluded from launch.

## A. Application foundation and operation [CORE]

**Capabilities:** Native Windows app, offline-first local persistent database, PIN login, staff session, business-day clock, shift cash session, automatic migrations, backup/restore, role-controlled navigation, searchable lists, audit and exception reporting. UI in English with local business terminology (`Khata`, `Mandi`); timezone display Asia/Karachi. Operates without internet for sales, stock, payouts and reports. Network needed only for actual email/WhatsApp sending. No browser tab or cloud sign-in required to bill.

Manager (Supervisor/Owner) is the only management role, with identical permissions for both titles; Manager can administer and approve but cannot perform cashier tasks. See chapters 01 and 24.

**End of day:** Confirm all shifts accounted for and pending delivery/rider balances surfaced, review refunds, cash and inventory exceptions, submit supervisor-approved Z report, lock day, generate PDF/XLSX, back up, queue email/WhatsApp if enabled. Next day's token sequence starts from configured daily boundary.

**System status:** Header displays authenticated staff, business day, shift, local time, offline/network state and blocking errors. A short alert must never erase user input. Background report-sending errors never interrupt billing.

## B. Staff, departments, account access and payroll [STAFF]

**Staff creation:** Manager enters full name, optional employee code/contact, department/job, employment status, monthly salary or wage basis, commencement date and POS role. Employee may have no login. If role Cashier/Manager, a unique 4–8 digit PIN is created/confirmed; Manager account may only be created/elevated by Owner. Hash PIN, unique keyed lookup, lockout/cooldown and audit. Every account has an explicit role independent of department.

**Employee CRUD:** Create/view/filter/edit contact/department/salary effective date; disable/deactivate without deleting past orders and finance. PIN rotation must not reveal old PIN; role changes audited; no duplicate PIN even between cashier and supervisor. If employment ended, no new login but prior shift attribution remains intact.

**Payroll:** Period setup, salary accrual, advance issued, deductions, partial salary paid, reversals and outstanding liability. Employee balance view must separate **gross earned**, **advances recovered**, **deductions**, **salary paid**, **remaining owed**. Staff payment from drawer produces one cash outflow and one payroll allocation; bank/outside-drawer payment changes payroll liability only, not drawer. Payroll posts must never be casually edited or deleted; use reasoned corrections. Reporting includes department costs and due dates. Attendance-linked payroll optional future unless approved.

**Typical flow:** Create employee → assign optional POS role/PIN → start salary period → record advance (drawer/bank source) → accrue salary → record payroll payment → review balance/history → close period. If an advance is recovered, prevent counting it twice as both cash expense and deduction.

## C. Menu, categories, deals, discounts and recipes [MENU]

**Menu categories CRUD:** name, sort order, optional marker/icon and active flag; reorder, rename, archive. Archived category/items remain readable in historic sales. Menu product CRUD: code/SKU, name, description, category, price, tax configuration, sale status, optional image, options/modifiers, recipe and effective dates. Users may create arbitrary categories and products, not fixed video items.

**Deals/combinations:** Supervisor adds deal title/code, customer price, active dates/time, constituent products/quantities, required option groups, upgrade choices, quantity limits, display ordering and BOM decomposition. Example: Family Deal includes four burgers and two drinks with choice of drink; the cashier sees one concise choice dialog. Saving a deal validates its component mapping and total, and prevents selling invalid/inactive components based on policy. Version deal composition when sold.

**Modifiers:** Add cheese, no mayo, extra sauce etc. Each can change sale price and recipe consumption independently. Recipe BOM links ingredients to base units and precise quantities; avoid negative or ambiguous inventory calculations. Packaging BOM is separately tied to fulfillment mode and packaging version. Tax rules/rounding and delivery-fee treatment must be owner/accountant approved, not hardcoded from screenshot.

**Discounts:** Manager create active eligible presets (`5%`, `10%`, flat Rs amount, item/deal-specific, min spend, cap, date window, stackability, authorization). Active eligible presets **always visible to cashier** in the discount section. Cashier can apply only those. Expired/disabled presets hidden/clearly ineligible; cart revalidates on confirm. Store applied discount ID plus immutable details for historical reproducibility.

**CRUD rules:** Items with no references may hard-delete; referenced masters deactivate/archive, not destroy. Historic orders snapshot names/prices/deal/discount. Manager price change never retroactively alters existing held or posted orders silently—held drafts must recalculate/confirm on recall.

## D. High-speed cashier counter [POS]

**UI:** Designed for Windows display (1366×768 baseline). Category tabs plus product search; optional images; 3–5-column compact grid depending width; persistent right cart/amount panel and checkout control; minimal visual distractions and *no routine page scrolling for simple bill*. Keyboard shortcuts shown and configurable by Owner. Cart rows display quantity ±, modifiers and line price. Quick-action toolbar role aware.

**Modes:** Delivery (phone, name, address, area, landmark, rider later, delivery fee), Takeaway (phone optional), Dine-in (table 1–5, open state, guest count if configured). All use same order engine but appropriate mandatory fields and packaging rules. Tables never silently merge; combining/check splitting requires separate approved scope.

**Quote vs order:** Product selection builds ephemeral/durable draft. Discounts and taxes preview, but no stock or payment ledger posted until confirmation. Hold saves draft separately; recall opens and validates stale prices/availability/discount rules, preserving untouched draft if takeover denied. Repeating historical order clones lines into new cart at current price/eligibility after confirmation; never silently duplicates payment or stock usage.

**Tender:** Cash: received amount + change, underpayment disabled. Electronic: choose configured card, bank/Raast, Easypaisa, JazzCash and mark verified according to actual integration or cashiers' manual confirmation policy. COD: order confirmed with collection outstanding, *not cash sales yet*. Split: lines per tender sum exactly to total; refunds later allocate against tender(s). Avoid fake gateway confirmation. Support cancel/back without clearing cart. Atomic submit once; save with idempotency key to survive double-click/crash.

**When saved:** Create immutable order lines/snapshots, sequential business-day token, payment obligation/collections, fulfillment event, stock ingredient and packaging usage once, audit. On-screen success: order/token, amount, payment state and next action. Digital receipt/PDF if enabled. Kitchen verbally informed; **no KOT or kitchen station**.

**Shortcuts:** Manager maps action to key (F2 new, F3 hold, F4 recall, F5 customer, F6 discount, F7 pay etc. as examples). Prevent duplicate assignments and protected OS combinations; context-aware (e.g., do not trigger while typing), enforce role permissions on invocation, restore defaults and audit changes. Cashier cannot reassign global shortcuts.

## E. Customer records and ordering history [CRM]

Phone search normalizes local Pakistan numbers; duplicate detection with manager resolution and non-destructive merge policy. Customer has names, multiple phone entries where needed, labeled addresses, areas, landmarks, notes (avoid sensitive unnecessary detail), first/last order and order history. Ability to search by phone before bill, auto-fill address/fee policy and create repeat-order cart. Order history remains authoritative if customer name/address is later updated. Support walk-in and anonymous orders. Protect phone lists in exports. **Loyalty/rewards and automated marketing are future**.

## F. Manual preparation and order status [ORDER]

Proposed main path: Confirmed → Preparing → Ready → Out for Delivery → Delivered for delivery, and Confirmed → Preparing → Ready → Collected for takeaway. Dine-in can use Ready → Served → Completed. Each transition stores timestamp, actor and optional reason. Status buttons on Orders screen; no printer, kitchen queue, SMS or rider app. Configurable stage delay thresholds trigger in-app supervisor alerts; a delayed warning is informational and does not silently change status.

**Cancellation/void:** Before commit: remove draft. After commit: role/approval, reason, original amounts and explicit food disposition. Cooked/served stock is NOT automatically restored as fresh inventory. Refund is a separate tender movement/receivable reversal. Voided order and events remain in reports; no deleted historical row.

## G. Delivery, riders, trips and failed returns [DELIVERY]

Rider directory links employee names/contact/status; supervisor assigns available rider to an order or batch/trip. A trip has unique ID, rider, departure time, included order IDs, expected COD, handovers and close status. Avoid assigning one order simultaneously to two active trips. A rider may carry multiple orders; order status and payment state distinct.

**Out for Delivery:** dispatch timestamp and rider recorded. On delivered: mark delivery, optionally note COD collected by rider; actual drawer not increased until rider hands cash in. On return/fail: record reason (customer not available, rejected, address incorrect, rider issue, etc.), attempts, return time, inventory/packaging/food decision, payment/refund decision; allow supervised redispatch under explicit linked attempt. Never assume cooked food is saleable stock or auto-refund.

Manager (Supervisor/Owner) is the only management role, with identical permissions for both titles; Manager can administer and approve but cannot perform cashier tasks. See chapters 01 and 24.

## H. Inventory, purchasing, packaging and wastage [INVENTORY]

Inventory master CRUD supports name, code, ingredient/packaging/other type, base unit, stock threshold, cost method, reorder level, supplier associations, stockable flag and status. Supervisor can create arbitrary items inside supplier creation or inventory form. Requiring a supplier-product link is mandatory for supplier-specific purchase. Purchase dropdown filters and validates linkage. Manager can edit associations; historical deliveries reference their original supplier/item. For sold recipes, ingredient and packaging consumption posts once as a stock ledger movement.

**Stock receipts:** Source supplier, line item, quantity, unit, unit conversion, unit/extended cost, invoice/ref, partial/full payment, expected/received date. Decimal precision and dimension validation prevent unit error. Mandi units configurable (Mann, Pao, Bori, Dharri, Darjan, Peti/crate) with explicit per-item conversion; do not assume every crate contains same amount.

**Wastage:** damaged/burned/expired/spoiled food with mandatory reason, staff and estimated cost loss; create negative stock movement. Supplier returns from unsold inventory have separate credit/quantity and payable effects; cooked customer return is not automatically a stock increase.

**Physical stock count:** Freeze base snapshot or calculate movement-safe delta, count actual, show variance by item, require manager approval when threshold exceeded, post precise adjusting movement once. Include counted time, snapshot revision, counters, approver and signed results. Real-time stock warnings and reorder alerts are configurable. No requirement to block cashier at negative stock unless owner policy says so.

## I. Supplier CRUD and Khata [SUPPLIER]

**Create supplier:** name, primary phone, address(optional), contact, note, status, opening payable if approved and **supplied inventory items** (multi-select). Manager can type arbitrary new product name on the same screen, define type/unit and add to inventory master, then associate it. During purchase choose supplier first, then select only assigned items; server command validates association again. Supplier status: `No purchases` when no payable purchase; `No payments` when payable purchases exist and sum paid = zero; `Partially paid` when 0 < paid < due basis; `Paid` when purchases settled. Opening balances, debit/credit notes and repayments require derived ledger-aware status, not simple counters.

**Purchases:** partial cash/bank/credit payment; stock received + liability logged once; invoice/slip ref; reject exact duplicates or request override; due date and supplier statement. **Khata:** payable = approved opening amount + posted deliveries/charges - valid supplier returns/credits - applied payments. Show outstanding/overdue aging (0–30,31–60,61–90,90+) and chronological statement. Paying from active drawer creates exactly one drawer outflow; paying outside drawer does not affect cashier drawer. No supplier with history can be silently deleted; archive instead.

## J. Business day, expenses, cash and reconciliation [FINANCE]

**Cash movement taxonomy:** cash sale collection, opening float, expense pay-out, supplier payment from drawer, rider cash pay-in, customer refund, salary from drawer, adjustment and discretionary pay-in/pay-out (with approval). Every entry identifies source, purpose, business day/shift and reference. Do not double-count supplier/advance/expense as separate pay-outs for the same physical cash.

**Expense categories:** Manager full CRUD on category master (create/edit/rename, list, archive and delete unused). Add unlimited restaurant-specific categories (gas cylinders, electric bill, staff meal, petrol). No fixed uneditable category set. Category rename updates display without corrupting historical grouping; category deletion denied when referenced and deactivation offered.

**Expense posting:** category, amount, description, paid-to, payment source, date/business day, approval if threshold, receipt/file optional and tax/cost treatment if approved. Void/correct posted entry via reversing event; not destructive edit. Expense expense type distinct from supplier inventory purchase, payroll payment and refund for profit classification.

**Blind shift close:** cashier enters counted cash without seeing expected. `Expected drawer = opening float + actual cash collected into drawer + approved pay-ins - physical cash pay-outs - cash refunds/cash drops`; variance = counted - expected. Supervisor reviews discrepancy, signs reason, can proceed with next shift under approved nonblocking policy; outstanding rider COD never included until cash is actually handed in.

## K. Reports, owner intelligence and export [REPORT]

Filters: business day, chronological date interval, order mode, product/category/deal, cashier, shift, payment type, area, rider, supplier, ingredient, status, expense category and staff. Tables support sort/search/drill-down, chart and downloadable PDF, XLSX (multiple sheets), CSV. Report results are based on **posted ledger events and snapshots**, not an HTML approximation. Owner-level reports:

1. Executive summary: gross sales, discounts, refunds, net sales, taxes, delivery fees, order count, average order value, tenders and exceptions.
2. Sales by product/category/deal, bestseller units, margin data quality and modifier analysis.
3. Hour/day/week/period trends, peak hours, weekday mix and comparable periods with correct filters.
4. Delivery performance by area/rider/trip: accepted, preparing, dispatch, failed/returned, elapsed, lateness, cash settlement, shortages.
5. Customer mix: new/repeat, total value, repeat-order frequency, address/area penetration. Minimal necessary PII in exports.
6. Inventory consumption, packaging cost, reorder, negative stock, count variance, physical wastage, stock valuation and purchase price trends.
7. Supplier Khata: invoices, aging, overdue credit, spending, partial payments, returns and procurement cost.
8. Drawer and shifts: floats, payment mix, pay-ins/outs, expenses, cash variance, unpaid COD and X/Z audits.
9. Staff/payroll: accrued salary, advances, paid, remaining, department wages and dates.
10. Profitability: food cost vs net sales, gross margin by menu item/period, expenses and net profit **only when verified cost/accrual inputs complete**. Label incomplete/unreliable metrics rather than inventing money.
11. Exceptions and audit: voids, refunds, price override approvals, late orders, cash discrepancies, stock loss, failed sends and backup failures.
12. Export scheduling/delivery: close-day immutable Z-report and deep Excel workbook; approved email recipients, manual WhatsApp share, optional official automated WhatsApp, offline outbox and retries (chapter 25).

## L. Owner/supervisor settings [ADMIN]

Manager (Supervisor/Owner) is the only management role, with identical permissions for both titles; Manager can administer and approve but cannot perform cashier tasks. See chapters 01 and 24.

## M. First release vs later

**MUST for accepted production scope:** offline app, RBAC/PIN, business-day+shift, cashier billing, menu/deal CRUD, discount visibility, customer lookup/hold/recall, payments, delivery/trips/cash, stock and packaging, supplier-supplied items and Khata, expenses and custom categories, salary/advances, owner reports, PDF/XLSX export, email delivery with queued retry, basic backup/restore, tests and audit.

**RECOMMENDED/CONFIGURABLE:** manual WhatsApp sharing, supervisor expense posting permission, negative-stock blocking vs warning, certain report drill-downs, noncash payment verification details, supplier invoice aging and salary accrual policy.

**FUTURE pending explicit approval:** automatic WhatsApp Business Platform if not provisioned in first release, loyalty rewards/points, kitchen KOT/display, physical receipt printer/cash drawer hardware, delivery rider mobile app/GPS, cloud remote database, multi-terminal conflict resolution, multi-store/branch, full accounting/tax filing integrations.

## N. Minimum complete daily scenario

- Supervisor opens business day. Cashier PIN login and starts shift with Rs. 5,000 opening float.
- Cashier looks up returning customer's phone, selects prior address, adds a deal plus separate burger, selects published discount and checks out a COD delivery.
- BOM consumes chicken/bun/sauce plus correct delivery packaging **once**. Kitchen hears order verbally; cashier marks Preparing/Ready. Assigned rider takes order; customer receives it; rider cash is later handed in and counted exactly once.
- Supervisor adds new supplier, creates 'Charcoal' as a supplied item, purchases quantity partly on credit. Inventory receipt and supplier payable are created atomically; supplier gets Partially paid status or No payments if no amount was settled.
- Supervisor records a gas-cylinder petty cash expense using a newly created category. Drawer money decreases once, owner expense report classifies correctly.
- Supervisor creates cashier employee, PIN and salary, issues advance and partial salary payment; payroll ledger and cash source remain reconciled.
- Cashier submits blind cash count, supervisor reviews difference. Day is closed and locked, PDF/XLSX created, email queued and WhatsApp manual/automatic handled per configuration. Owner sees genuine net sales and warnings for uncosted profit figures.
- PC restarts: saved order, stock, supplier balances, PIN roles, financial history, queued emails and daily reports remain intact.


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 27 — Screen-by-screen contract: fields, roles, actions and validation

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


**Design target:** Flutter Windows, 1366×768 baseline; operational screens optimized for 1-monitor point-of-sale. Tables/forms may scroll, but **cashier's ordinary bill flow must not require vertical page scrolling**. Each screen MUST have loading, empty, error and permission-denied states, inline validation, keyboard order and unsaved-change guard. Buttons are commands, not decorative mock controls.

## 1. Authentication / PIN lock

- **Who:** any active PIN-authorized employee. **Fields:** masked 4–8 digit PIN, numeric keypad; optional staff hint (do not expose others' PINs).
- **Actions:** unlock, clear, backspace, lock register, authorized recovery.
- **Validation:** active unique credential; throttle; wrong PIN has no hints about whose PIN; no plaintext history/log. Start/resume authorized session only.
- **Result:** route to cashier or supervisor home with active identity, role and department shown.

## 2. Business-day opening / status

- **Who:** S/O open/close; C view day and own shift.
- **Fields:** business date, opening timestamp, timezone, optional daily notes; current day state.
- **Actions:** Open day, inspect pending prior-day exceptions, close day (separate review wizard), view day history.
- **Validation:** one open day, no conflicting write lock; midnight alone never creates or closes a business day.

## 3. Shift opening / drawer float

- **Who:** cashier for own shift; S/O oversight.
- **Fields:** opening cash total, optional denomination counts, cashier identity, drawer, shift start.
- **Actions:** Start shift; cancel before start.
- **Validation:** positive/zero amount, drawer availability, active day, lock against duplicate start; do not reuse previous cashier's unreconciled float invisibly.

## 4. Cashier POS — primary selling workstation

- **Who:** Cashier only; active shift required for posting.
- **Fields/layout:** categories/search left; product/deal tiles center; always-visible cart, quantity, modifier, subtotal, published discounts, delivery fee, tax and total right. Customer phone/address and fulfillment mode appear in compact header/expandable section. Owner-configured shortcut hints.
- **Actions:** new, search, tap item, edit quantity/options, delete draft line, mode, choose customer, hold, recall, choose eligible preset discount, Pay, clear with confirmation. All keyboard accessible.
- **Validation:** positive quantity, price/deal and modifier snapshot valid, discount active/eligible, required delivery address, valid table. Payment totals correct; no unintentional change of posted bill.
- **Design test:** basic takeout bill completed without scrolling, one click per ordinary product, single concise payment sheet, no massive sidebar/distracting owner analytics on cashier surface.

## 5. Deal configuration sheet

- **Who:** Cashier selects deals; Manager maintains deals in management screen.
- **Fields:** preconfigured required groups, choice options, quantities, paid upgrades, price preview, constituent products.
- **Actions:** select options, add deal, cancel.
- **Validation:** one choice for radio groups, max counts/stock if hard block, current active deal version; do not add incomplete package.

## 6. Checkout/payment sheet

- **Who:** Cashier only.
- **Fields:** amount owed, payment method (Cash, JazzCash, Easypaisa, Bank/Raast, Card, COD, Split), cash received/change, split amounts, optional transaction reference and COD collection assignment. **No provider verification or payment-processing states.**
- **Actions:** exact cash, suggested notes, add split tender, remove tender line, confirm, back to cart.
- **Validation:** forbid cash underpayment, overallocated split and duplicate submit; cashier selects method and records payment without official APIs, secondary verification workflow, or `Unverified`/`Processing` tags. COD remains amount due until collected. Payment is not identical to delivery status.

## 7. Held orders / recall

- **Who:** Cashier owns held carts; Manager may view for audit, not recall/operate carts.
- **Fields:** draft ID, customer, operator, age, mode, line count, estimated total, last saved at.
- **Actions:** hold from POS, search, preview, recall, transfer ownership with approval, discard unsaved draft with reason.
- **Validation:** stale price/item/discount conflict shown before applying; recall cannot overwrite nonempty current cart without explicit choice.

## 8. Orders list / order details / status

- **Who:** C operational subset, S/O all.
- **Fields:** token, business day, customer, items, amount, order type, fulfillment status, payment status, rider, age, timestamps, reason and audit.
- **Actions:** status progression, assign rider, inspect tender, duplicate into new order, request void/refund, mark failed delivery, view receipt PDF.
- **Validation:** state machine, no silent backward transition, manual kitchen milestone entry; no KOT or kitchen queue.

## 9. Customer directory / address editor

- **Who:** Cashier edits customers in order workflow; Manager may view/manage customer directory without creating orders; export restricted.
- **Fields:** name, phones, address labels, area, directions/landmark, active/primary address, order history summary.
- **Actions:** search by normalized phone, add/edit address, mark primary, start repeat order.
- **Validation:** duplicate phones flagged, no accidental overwrite of historical order delivery address, phone formatting and access permissions.

## 10. Menu item list / editor

- **Who:** S/O CRUD; C sees sellable items only.
- **Fields:** category, SKU/code, product name, description, sales price, tax profile, image(optional), active flag, display sort, start/end availability, BOM and packaging associations.
- **Actions:** create, view/edit, duplicate, activate/deactivate, archive, delete unused, preview tile.
- **Validation:** positive/zero pricing per policy, required category/code, code unique, references prevent hard deletion, historical price snapshot immutable; **complete recipe/BOM mandatory before any menu item can be activated or sold**. A draft may be saved while incomplete.

## 11. Menu category manager

- **Who:** S/O.
- **Fields:** category name, order, optional icon/marker, active flag.
- **Actions:** add, rename, reorder, archive, delete unused.
- **Validation:** linked products must be moved or archived first; inactive categories hidden from new POS selection.

## 12. Deal/combo builder

- **Who:** S/O.
- **Fields:** title, active, retail price, category, included product/quantity lines, required choice groups, upgrades, discount compatibility, start/end dates, availability schedule.
- **Actions:** create/edit/version/archive/delete unused, preview cashier chooser, run price/recipe validation.
- **Validation:** positive priced components or legitimate free choice, no infinite nested loops, **every selectable item/variant has a validated recipe and exact aggregated deal BOM**, including packaging; block activation while incomplete; outdated deal versions still reconstructable.

## 13. Modifier/recipe BOM editor

- **Who:** S/O.
- **Fields:** ingredient, required quantity/base unit, substitution/add-on, price delta, stock consumption delta, waste factor if approved; live estimated food cost.
- **Actions:** add/edit/remove recipe components; preview order stock movement.
- **Validation:** compatible units, no hidden float rounding, require at least one valid recipe component (or explicit non-stock classification for authorized non-inventory item), block invalid recipe references; new BOM effective version not retroactive.

## 14. Discount preset management

- **Who:** S/O manage; C select eligible active only.
- **Fields:** title/code, percent/flat, cap/min spend, item/deal applicability, valid time window, stacking, approval thresholds, allowed roles, active.
- **Actions:** add/edit/activate/deactivate/archive; preview eligible bills.
- **Validation:** percent in valid range, no unintended additive stacking, policy changes audited, published discounts immediately visible to cashier after refresh/restart.

## 15. Inventory item editor / stock dashboard

- **Who:** S/O full CRUD, C optional read-only availability hint.
- **Fields:** name, code, type Ingredient/Packaging/Other, base unit, reorder threshold, available count, last cost, status, supplier associations.
- **Actions:** add/edit/archive/delete unused, add supplier association, receive stock, wastage, stock count, movement history, reorder list.
- **Validation:** cannot change unit dimension after movements without explicit migration, no negative received quantity, references block hard-delete, posting every stock event idempotently.

## 16. Stock receipt / wastage / adjustment

- **Who:** S/O.
- **Fields:** item, reason type, entered quantity/unit, base quantity preview, supplier/reference for receipt, item cost, actor, timestamp and approval.
- **Actions:** receive, issue/waste, attach evidence, review, post; reverse incorrect posting.
- **Validation:** dimension conversion, positive magnitude and explicit sign, cost method, no posting twice; negative quantity policy; logged loss for cooked/expired returns.

## 17. Physical stock count

- **Who:** S/O; distinct-approver threshold configurable.
- **Fields:** count ID, snapshot, location/bin, SKU, book quantity, actual count, difference, reason, count time and staff, approve/post status.
- **Actions:** begin, pause/resume, enter quantities, review variance, approve, post and export difference report.
- **Validation:** snapshot movement-safe count, no duplicate post, no blind overwrite of movements posted while count underway.

## 18. Supplier creation / edit and supplied-item manager

- **Who:** S/O.
- **Fields:** supplier name, primary phone/alternate contact, address(optional), account notes, payment terms, opening balance by approved entry, active status, multi-select list of supplied inventory items.
- **Inline creation:** `+ Add custom supplied item` opens compact form for arbitrary name, item type, base unit and optional reorder level; creates inventory master (or reuses a matching existing SKU), then selects it for this supplier. Not limited to preseeded items.
- **Actions:** create supplier, add/remove association, edit contact/payment terms, archive supplier, view statement, delete unused supplier.
- **Validation:** case/whitespace duplicate prompts, phone optional but validated, item link unique per pair; deleting association must not change prior invoices or receipts. Supplier with financial history cannot hard-delete.

## 19. Supplier purchase / credit delivery

- **Who:** S/O.
- **Fields:** supplier first; line item dropdown automatically filtered to its supplied items; qty, purchase unit and conversion, unit cost/amount, invoice number, delivery date, due date, paid-now amount, payment source and evidence.
- **Actions:** add/remove lines, review subtotal/total, save as received purchase, record separate settlement later, post supplier return/credit.
- **Validation:** supplier-item link rechecked on command, payment ≤ amount unless vendor advance explicitly supported, unique invoice policy, stock receipt once, payable once, cash outflow once for drawer-funded payment. If new item absent, create it only via authorized supplier association flow.

## 20. Supplier Khata / payment screen

- **Who:** S/O.
- **Fields:** supplier ledger chronological entries, opening balance, invoices, credits, paid amount, remaining, due/overdue, payment source, amount, reference/note.
- **Actions:** pay supplier, allocate payment to invoices, view PDF statement, mark dispute, adjust via approved reversals.
- **Status:** No purchases / No payments / Partially paid / Paid, derived from posted invoice and settlement events; negative payable/credit shows explicit vendor credit rather than fabricated `Paid`.
- **Validation:** source Active Drawer vs Outside Drawer mandatory; no double count, no modifying old payment silently.

## 21. Cash expenses / custom expense categories

- **Who:** S/O category CRUD and expenses; C expense entry only if delegated.
- **Fields:** expense category dropdown; inline `+ New category` for S/O; amount, memo, payee, source (drawer/bank/owner pocket), receipt reference, staff/shift/business day, approval and status.
- **Actions:** create/edit/archive/delete unused category; record expense; view history; void/correct posted expense with reason; filter/export category totals.
- **Validation:** category rename preserves group identity, archived category hidden from new expense, linked category can't hard-delete, no duplicate drawer pay-out, positive amount and valid source. Supplier invoice purchase is NOT automatically a petty cash expense.

## 22. Cash movement and blind shift close

- **Who:** C own shift count, S/O reconciliation/approval.
- **Fields:** denomination rows/count, optional note, cashier identity, posted pay-in/out types; expected balance **hidden before count submission**.
- **Actions:** start count, submit blinded physical amount, confirm, supervisor review variance/resolve, export X report.
- **Validation:** no viewing expected total during entry, pending shift close atomic, discrepancy not silently offset by arbitrary payment.

## 23. Rider / delivery trip manager

- **Who:** C assigned operational actions if delegated; S/O all.
- **Fields:** trip ID/rider/order list, dispatch and return time, trip state, expected COD/collected vs handed in, discrepancy, attempts and route/area notes.
- **Actions:** create/assign/dispatch/mark delivered/record failed/reassign, collect handover, close trip with exception.
- **Validation:** one active trip per order, delivered state separate from paid status, only counted cash goes to drawer, attempts preserved.

## 24. Staff directory / PIN setup / payroll

- **Who:** S/O master payroll/credentials with owner privilege reserved.
- **Fields:** full name, department, employment dates, status, role selection, masked 4–8 PIN/confirmation when role login enabled; monthly salary, salary periods, advances, deductions, payment source and outstanding ledger.
- **Actions:** create, edit, deactivate, reset PIN, edit authorized role, issue advance, accrue, pay salary, correct via reversal, export payslip/ledger. Delete unused employee only.
- **Validation:** PIN unique system-wide for active credentials, Manager cannot be created by supervisor, salary payments idempotent, no removal of historic payroll.

## 25. Owner/supervisor dashboards and reporting explorer

- **Who:** S/O; C limited own shift as configured.
- **Fields:** business day/date range, grouping and comparisons, filters (product/customer anonymized/rider/area/supplier/employee/category/tender), metrics, charts, warnings/data quality tags, drill-down and export.
- **Actions:** choose report, save preset, print-to-PDF, Excel/CSV export, inspect source records, send approved report. Detailed formulas in 21.
- **Validation:** date filter **must really filter** records, accurate net/gross semantics, profit hidden/qualified if no stock costs. Never expose staff PIN/customer full address unnecessarily.

## 26. Day-end Z, backups and delivery queue

- **Who:** S/O close/export; O delivery credentials/recipient policy.
- **Fields:** day summary, shift reconciliation, unsettled rider balances, unresolved refunds, PDF/XLSX file statuses, email/WhatsApp enablement, approved recipients, job attempt history.
- **Actions:** preview, finalize day, generate immutable files, queue automatic send, retry allowed jobs, export historical report, restore backup (Owner/approved specialist only).
- **Validation:** day close cannot be submitted twice, file generation independent of email success, offline outbox persists, provider accepted not confused with received; WhatsApp manual requires actual operator action and WhatsApp automatic requires official configured provider.

## 27. Owner system settings / action shortcuts

- **Who:** O global security/shortcuts; S operational settings as delegated.
- **Fields:** name/logo, business timezone, retail/tax profile, roles, feature toggles, approval thresholds, stock policies, report recipients, shortcuts/action maps/role context, backup location/schedule.
- **Actions:** edit with preview, validate conflicts, save version, revert, audit changes.
- **Validation:** disabled features do not erase historical data; no critical shortcut collisions; no unmanaged credentials; policies cannot self-grant Manager authority.

## 28. Logs, approvals and exception queues

- **Who:** S/O.
- **Fields:** event ID, timestamp, operator, action, resource, before/after redacted values, reason, approval actor, source record, status.
- **Actions:** filter/resolve exceptions, inspect audit chain, approve permissible request, create corrective entry; never delete/modify audit events.
- **Validation:** stale approval cannot authorize a different payload, approval identities retained if staff inactive later.

## Shared UX requirements

- Every list includes search, date/business-day filter (where applicable), meaningful empty state, record detail and permissions-aware actions.
- Destructive master change confirmation says exact consequences; finance change uses reversal/correction not hard-delete.
- Every monetary entry uses integer-paisa/decimal-safe formatter, validation, transaction preview and posted receipt/reference.
- Network failure affects report delivery only, not local order confirmation. Background jobs show status and never pop up in a cashier's cart.
- Error messages include recovery action: invalid PIN → retry policy, stale cart → reprice, supplier-item mismatch → manage supplied items, insufficient cash tender → enter payment, report failed → retry send, backup invalid → stop restore.

## v5 required manager menu/deal creation screen behavior

Manager creates or edits menu/deal → Details → **Mandatory recipe step** → BOM expansion preview → Activate. Save as inactive draft is allowed; activate/publish is disabled until complete recipes and all deal choice paths validate. Each recipe line has ingredient identifier, quantity, unit and optional modifier relationship; packaging deduction rules are included. Manager cannot bypass recipe validation. Stock balances of 0 or negative NEVER prohibit publication solely for stock reasons once the recipe itself is valid.

## v5 simple cashier payment sheet

Method tabs/buttons: Cash | JazzCash | Easypaisa | Bank/Raast | Card | COD | Split. Tap method then **Complete payment** (cash amount/change where relevant). Reference number is optional. No provider/API integration; no `Unverified`, `Processing`, `Verification pending`, or wallet-specific validation badges. COD is `Amount due` until payment is actually collected. Real persistence is still transactional and duplicate-submit-safe.


## v6 explicit screen acceptance

**First-run wizard:** Steps include required primary Cashier four-digit PIN following Manager creation, unique PIN validation, day-opening then cashier shift handover.

**Cashier amend screen:** Preparing/Ready/Out for Delivery editable before rider trip settlement; after settled, line controls locked and only Refund/Adjustment or a new order offered. Log before/after.

**Payment sheet:** Digital tender exact paisa, cash due nearest whole rupee with small rounding adjustment line, COD unpaid until collected. Tax-inclusive shelf price stays unchanged by default.

**Modifier editor:** Sauce group radio options Normal/No/Extra with immediate replacement, not conflicting checkboxes.


## v7 screen contracts — new/updated

**Cashier cart/Continue — Customer:** Cart item ID, qty, selected modifiers, order mode, estimated total. Continue validates at least one sellable item, recipe-active components, then opens a non-persistent customer sheet (no allocated order token). Manager role forbidden.

**Customer-details sheet:** Fields: phone (lookup; optional where appropriate), name, delivery area dropdown (active/serviceable options only), house/building, street/address, landmark, special instructions, saved customer/address selection. Delivery phone/name/address/area required; present inline errors and one-tap saved addresses. For takeaway/dine-in requirements are relaxed. Customer link and address snapshot are saved only at final order commit. `Back` returns to cart without wiping progress. If area disabled/removed mid-entry, fail final commit gracefully and preserve draft for new area selection.

**Delivery-area management (Manager only):** list/search/filter by active/serviceable, create/edit form (name, code, fee, min order, ETA, coverage notes, optional schedules), activate/deactivate, archive and audit. Fee cannot be negative; name must be unique among active areas; history-backed area cannot be hard-deleted.

**Menu/deal picture editor (Manager only):** Optional upload button `Add photos (recommended)` supporting multiple JPG/PNG/WebP files; preview/reorder gallery, set primary image, captions/alt, replace/delete. Reject unsupported/oversize/malicious files with clear reason; show fallback preview. No image = fully valid draft/published item provided mandatory BOM exists. Media changes should not mutate recipe versions.

**Payment/final confirmation:** Show line items, immutable-selected delivery area and derived fee, customer, total, simple manual tender choices and `Complete Order`; no `Unverified`/`Processing` tags. Only final confirmation allocates daily token and posts stock exactly once.


---


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


---


**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 29 — Comprehensive acceptance walkthrough, role-based scripts and release verification

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


**This is a hands-on test plan**, not a demo. Test against real Drift/SQLite persistent storage and deterministic fixture data. Run core scenarios offline, after restart, with expired sessions, after schema migration, and with deliberately failed I/O. Each issue must include steps to reproduce, expected vs actual, DB evidence and owner/supervisor acceptance.

## 1. One-hour role walkthrough for manager approval

Manager (Supervisor/Owner) is the only management role, with identical permissions for both titles; Manager can administer and approve but cannot perform cashier tasks. See chapters 01 and 24.

**Scenario 2: Supervisor catalog/stock (10 minutes).** Create categories Burgers, Deals; add Zinger Burger, Fries, Soda; create ingredient Chicken, Bun and wrapper; assign BOM; create Family Meal combo with choices and add-ons; publish 10% preset. Start cashier and verify new items and discount present. Archive deal: disappears from new cart while a prior sold order still reports original deal price.

**Scenario 3: Cashier fast billing (10 minutes).** Open business day and shift with Rs.5,000 float; phone-lookup existing customer, select address; add combo, change quantity, choose discount, place COD delivery. Hold a second order, lock/unlock and recall. Run exact cash takeaway. Repeat old order as *new* bill and confirm current prices. Basic checkout must fit 1366×768 with fixed cart and no routine vertical scrolling.

**Scenario 4: Rider and returns (5 minutes).** Assign two COD deliveries to same rider trip; mark one Delivered and one Failed; record return reason and food disposition. Post partial cash handover: cash drawer increases only by actual received, shortage remains; refund requires explicit authorized workflow and does not automatically put cooked ingredient stock back.

**Scenario 5: Supplier, stock and Khata (10 minutes).** Supervisor creates new supplier `Karachi Supplies`; inline creates `Charcoal` and `Paper Bags`, selects both; purchase filters to only those items. Buy 10kg charcoal Rs.6,000 with Rs.0 paid → supplier `No payments`. Pay Rs.2,000 from drawer → `Partially paid`, drawer decreases Rs.2,000; pay remaining Rs.4,000 from bank → `Paid`, no second drawer outflow. Try delete supplier: archive offered because ledger history exists. Perform physical stock count with one variance and adjustment approval.

Manager (Supervisor/Owner) is the only management role, with identical permissions for both titles; Manager can administer and approve but cannot perform cashier tasks. See chapters 01 and 24.

## 2. Role-specific destructive/action tests

| ID | Test | Expected |
|---|---|---|
| ROLE-001 | Cashier tries create supplier | Denied at service boundary, not only hidden button |
| ROLE-002 | Cashier tries delete expense category | Denied |
| ROLE-003 | Cashier tries edit menu product price | Denied |
| ROLE-004 | Cashier tries set discount preset | Denied; only apply published eligible |
| ROLE-005 | Supervisor creates expense category, edits and archives it | Allowed; historic expenses preserved |
| ROLE-006 | Supervisor creates menu product and combo deal | Allowed; cashier sees active product/deal immediately |
| ROLE-007 | Supervisor archives sold menu item | Allowed; historical sales correct |
| ROLE-008 | Supervisor creates cashier/manager PIN | Allowed only if globally unique |
| ROLE-009 | Supervisor creates/promotes Manager account | Denied |
| ROLE-010 | Manager configures F2/F3 etc. shortcuts | Allowed; conflicts rejected and recorded |
| ROLE-011 | Cashier runs restricted action by handcrafted command | Denied/audited |
| ROLE-012 | Supervisor changes company-wide email recipient without owner permission | Denied |
| ROLE-013 | Manager tries hard delete posted supplier transaction | Denied; reversal path available |
| ROLE-014 | Manager tries edit historic paid order in place | Denied; refund/rebill/adjust path |
| ROLE-015 | Archived staff PIN attempts authentication | Denied, prior audits preserved |

## 3. Checkout data and pricing tests

- Duplicate clicking Pay Confirm, switching rapidly between modes and killing app mid-save generates one or zero complete sale, never two.
- Tax-inclusive vs exclusive taxes, percentage/flat discounts, min spend, caps, stacking, deal upgrades, refunds and delivery fee tax treatment follow explicitly chosen policies. Test penny-level rounding using integer paisa.
- Held cart survives restart; if product price changed while held, operator sees proposed new total before continuing.
- Customer repeat order always creates new ID and current-line price, with archived menu conflicts surfaced.
- COD order saves as outstanding obligation; delivered fulfillment does not imply receipt of cash.
- Split tender sums exactly; cash change computed on actual retained amount, payment source constraints checked.
- No kitchen KOT, printer queue or hidden print attempt exists in happy-path or void-path.

## 4. Supplier/stock expense matrix

| Case | Stock | Supplier payable | Drawer cash | Report semantics |
|---|---|---|---|---|
| New item inline during supplier creation | Item exists with 0 stock | No change | No change | Catalog addition only |
| Supplier purchase Rs.4,000 all credit | +received units | +Rs.4,000 | 0 | Inventory acquisition not cash expense |
| Same purchase Rs.1,000 paid from drawer | +received units | +Rs.3,000 net | −Rs.1,000 once | Partial supplier settlement |
| Supplier paid remaining Rs.3,000 outside drawer | No change | 0 | 0 | Bank source, `Paid` |
| Supplier with unpaid purchase and Rs.0 paid | Stock still received | Positive payable | 0 | `No payments` |
| Receipt returned with vendor credit | −returnable units | −approved credit | 0 | Vendor credit/return separately |
| Cash expense Rs.800 fuel | No stock change | No change | −Rs.800 once | Expense fuel category |
| Stock wastage 2kg | −2kg | No change | 0 | Waste cost from inventory valuation |
| Physical count mismatch | +/− approved delta only | No change | 0 | Audited count variance |
| Kitchen food consumed in failed delivery | No automatic +stock | No automatic change | Depends on refund/handover | Waste disposition required |

## 5. Delivery/rider/payment matrix

- Rider trip with 3 COD orders: one Delivered+Collected, one Delivered+Rider Cash Pending, one Failed. Expected cash uses eligible actual collection events and recorded policy, not just `ordered_total`.
- Partial rider cash received twice sums exactly to expected; third replay with same command ID is no-op.
- Different operator cannot assign order to second concurrent active trip. Redispatch of Failed order creates new attempt event with link.
- Cashier shift close with rider handover pending flags exception according to policy but does not automatically count pending rider cash in drawer.
- Payment refunded by card should not create cash drawer outflow; refund tender/source consistent with policy.

## 6. Custom expense category CRUD tests

1. Supervisor creates category named `Gas Cylinders`, saves and reloads; category exists.
2. Create expense assigned to category; rename to `Cooking Gas`; historic expense remains linked and aggregates by stable category ID.
3. Attempt delete referenced category: hard-delete rejected with **Archive** action available; new expenses cannot pick archived category; existing history unchanged.
4. Create and delete an unused duplicate test category; no orphan records.
5. Category changes audited with before/after and actor; cashier not permitted to alter category.

## 7. Owner report acceptance catalog

- Trend dates grouped by **business day** with cutoff crossing midnight; filtering exactly matches drill-down and exported workbook totals.
- Net sales calculate discount, refund, tax/fees correctly under chosen accounting policy; customer payment and rider remittance separate.
- Sales by item/deal/category and discount redemption sum to eligible underlying detail with stable snapshots.
- Inventory beginning+receipts-consumption-waste-adjustment equals ending, with precise units and costing source.
- Supplier aging and `No payments` match each supplier ledger; payments from outside drawer do not change shift cash.
- Salary accrual and advances not double-charged; reporting discloses missing period data.
- When BOM cost missing, margin/net profit displays `insufficient cost data`, no invented figures or zero placeholders.
- Full export includes PDF and Excel and creates safe filenames; workbook opens in Windows Excel/LibreOffice independently of DB changes.
- Cash variance shows counted−expected with correct sign and stores submitted blind count separately.

## 8. Email / WhatsApp report acceptance catalog

| ID | Given/action | Expected |
|---|---|---|
| MSG-001 | Auto-email enabled, close day online | Z/PDF/XLSX generated, one queued/sent job per approved recipient |
| MSG-002 | Close while offline | Day closed; local report exists; jobs queued, sending retries later |
| MSG-003 | Restart after offline closure | Jobs and artifacts survive restart |
| MSG-004 | Click Close Day twice | One close + no duplicate automatic jobs |
| MSG-005 | Provider accepts send but callback delayed | State Accepted, not false Delivered |
| MSG-006 | Email provider times out after receiving request | Stable idempotency/ambiguous-delivery handling; avoid duplicate |
| MSG-007 | WhatsApp manual selected | Opens chat/share, operator attaches PDF; never marked auto delivered |
| MSG-008 | Automatic WhatsApp unconfigured | UI indicates requires official API setup; no silent fake send |
> Permission correction: Manager (Supervisor/Owner) has one unified management permission set, no cashier permissions; see 01 and 24.
| MSG-010 | PDF contains financial report | No PINs, API secrets, raw database paths, unneeded customer PII |
| MSG-011 | PDF renderer fails after close | Rebuild report intent; day stays closed and totals preserved |
| MSG-012 | Send failure | Logged in delivery history; retry does not close again |
| MSG-013 | Same business day past midnight | Report subject/attachment business date matches close snapshot |
| MSG-014 | PC powered off with jobs pending | Documentation/UI makes clear that local sending resumes when worker runs, unless cloud relay already received job |

## 9. Audit, security and backup tests

- Attempt privilege escalation and SQL injection via untrusted names/search/notes; parameterize queries and sanitize CSV spreadsheet injection (`=`, `+`, `-`, `@` strings).
- No four-to-eight-digit PIN stored, logged, displayed or included in report. Pin uniqueness robust against race, failed attempts persist across restart.
- Revoke/deactivate staff while session active; privileged new commands cease according to session-revocation policy.
- Backup under write load yields consistent SQLite checkpoint/snapshot; encrypted restore verified by checksums and controlled key handling.
- Apply old→new DB migration with orders, refunds, supplier payables, past salary payments and queued report sends; all balances and unique constraints verified.
- Simulate disk full, removable backup missing and expired API token: local billing remains reliable wherever storage itself is available; failures surface proper recovery.
- Audit immutability: any existing audit event can be read by authorized users but no UI/service route modifies or deletes it.

## 10. Exit criteria and delivery handover

- All modules exercised on target Windows hardware, keyboard and touchscreen if applicable.
- Developer provides executable installer, tested migrations, startup data paths, written backup restore procedure, role-admin handbook, operator POS cheat sheet, example owner reports, privacy and support notice, issue log, known limitations and reproducible tests.
- Owner approves unresolved business decisions from `22-decisions-and-assumptions.md` (tax, costing, negative-stock, refunds, cash variance, supplier advance, PIN recovery and report recipient policies) **before** real transactions.
- No demo seeded sales, sample PIN or exposed developer key in production installer.
- No inferred kitchen printing, rewards or remote rider tracking implemented as first-release functionality.
- All accepted end-of-day notification requirements match `25-business-day-report-email-whatsapp-delivery.md`, including graceful offline behavior and provider-dependent limits.


## v6 mandatory additions

Execute all ten Chapter 32 acceptance cases, including integer paisa rounding boundaries (49,50 paisa), split final balancing cash remainder, inclusive tax, non-recycled tokens, required separate Cashier wizard PIN, opposing modifier radio rules, revision+settlement lock race, nullable approved_by DB migration, and post-settlement correction by documented refund. No regression may require Manager PIN for ordinary pre-settlement edits or routine drawer movements.


---


# 30 — FINAL AUTHORITATIVE BUSINESS DECISIONS: cashier amendments, perpetual stock, and manual tenders (v4)

**Status: CONFIRMED, 12 October 2026. Supersedes all contradictory sections of chapters 00–29, original 01–10 files and the frontend demo.**

## A. Roles remain strictly separated

Only `CASHIER` and `MANAGER` (Supervisor and Owner are the **same** management role). Cashier alone creates/edits/cancels order transactions and receives customer/rider payments. Manager alone configures products/deals/discounts, employees/PINs, supplier items, stock/counts, salaries, expense categories, reports, settings/shortcuts and business-day closure. Managers **do not** use cashier POS. All commands require server/service-side authorization even offline in SQLite app.

## B. Cashier may modify a confirmed order without Manager PIN

| Action | Cashier | Manager PIN | Mandatory journal |
|---|---|---|---|
| Increase/decrease quantities | Allow | **NO** | order revision and item/BOM delta |
| Add item/modifier/deal | Allow | **NO** | before/after revision and delta |
| Remove item or modifier | Allow | **NO** | reason, cashier ID, item, qty, timestamps, stock disposition |
| Cancel entire confirmed order | Allow | **NO** | reason, original snapshot, stage, payment and stock disposition |
| Change delivery details/mode while operationally possible | Allow | **NO** | before/after snapshots and fee/packaging changes |
| Record collected-money refund separately | Allow within validated refundable funds | **NO routine PIN** | refund and tender-specific cash/external evidence ledger |
| View all edits/cancellations/refunds | Manager | Not applicable | searchable supervisory reports |

1. Use `orders` stable identity; `order_revisions` and `order_revision_lines` append-only (never overwrite original snapshot).
2. Captures `cashier_id`, order ID, business day, old/new values, reason, timestamp, customer/request context, preparation status and adjustment ID.
3. Calculate new item, deal, discount, tax and delivery-fee totals deterministically. If paid and reduced, show *refund owed* and require distinct refund action; **never assume money was returned** when order is edited/cancelled.
4. If unpaid and revised, adjust receivable once; if amount increases after payment, show additional amount due and record separate tender when collected.
5. Stock: create **delta** ingredient/packaging entries exactly once per revision, with consumed/prepared disposition. Pre-prep removals can reverse eligible consumption; already-cooked or spoiled food cannot automatically go back to ingredient stock.
6. Dispatch/delivered/settled orders need stage-aware UI to avoid falsifying rider settlement. Editing an already closed business day requires dated corrective document, not mutation of locked historical Z reports.
7. Cashier can cancel an order at any time allowed by financial reconciliation controls; if deliveries are active, mark rider notification/action required and leave immutable delivery attempts.
8. Do not add approval overlay or blocking supervisor/owner PIN for routine amendments/cancellations even if older specs say so. Record all changes and surface them in Manager audit/report views.

### Separate collected-funds refund

The cashier may record refund of money genuinely collected; required reason, order link, `amount <= paid minus prior refunds`, original method, actual disbursement source and manual verification. Cash refund reduces drawer **once**. JazzCash/Easypaisa/bank/card outbound refund must be actually sent by the restaurant and confirmed manually before marking paid; otherwise mark pending. Retain idempotency keys, audit and cash variance. **No automatic refund just because cancellation occurred.** No routine Manager PIN. Any exceptional limits are an optional *future business policy*, never a default gate.

## C. Perpetual inventory NEVER blocks cashier billing

- Stockout, zero and negative quantities are **warnings**, never checkout errors for stock reasons.
- Use one canonical `stock_ledger` that posts recipe and packaging consumption at each successful checkout; no duplicate posting on retries.
- Example: 2 kg on hand − 3 kg consumed = −1 kg. Purchase receipt +5 kg = 4 kg. **Do not deduct the missing 1 kg again** because it was already posted at order time.
- Display warning in manager stock dashboard and exception reports. Preserve negative stock history.
- Inventory purchase, wastage, count, return and order revision create auditable movement events.
- Physical stock counts account for movements during counting via snapshot offsets; normal goods receipts reconcile negative balances naturally.
- Negative stock impacts cost valuation: show provisional/unknown COGS when price history is missing; do not fabricate margin.
- Supervisor cannot enable any stock-blocking flag for ordinary checkout. Other unrelated problems (invalid payment, app storage failure, missing business day) can still prevent checkout.

## D. Payment methods are recorded manually, without integrations

Supported configured tenders: **Cash, JazzCash, Easypaisa, Bank Transfer/Raast, Card, COD, Split**. All are offline/manual accounting entry only. Do **not** integrate gateways, APIs, callbacks, SDK merchant onboarding or bank account verification as a prerequisite.

**Flow:** cashier selects tender → customer pays the restaurant outside the POS when digital → cashier selects the payment method, checks actual payment in ordinary business practice outside the POS, and presses **Complete payment** (optional reference). The POS saves method and received amount; do **not** show `MANUALLY_CONFIRMED`, `UNVERIFIED`, `PROCESSING`, `PROVIDER_VERIFIED`, verification-pending, or API-style badges.

- Card and wallets are *manual tender categories* for reporting only.
- COD order may be confirmed/fulfilled while payment remains unpaid. Rider collections and handovers reconcile via trip ledger without assuming delivery = paid.
- Split allocations sum to payable. Cash change is computed only from physical cash tendered. A manually confirmed digital tender must not generate a cash-drawer movement.
- Maintain payment correction/reversal journal. No duplicate amount posted on retry; no impossible negative change or over-refund.

## E. Acceptance scenarios (mandatory)

1. Cashier confirms order, customer asks to remove burger: no manager PIN; original and revised versions, reason, tax/discount and BOM consequences present.
2. Cashier cancels confirmed unpaid order: no manager PIN; cancellation audit, receivable closed and no false refund.
3. Customer prepaid by JazzCash, then cancels: order cancellation succeeds without manager PIN; payable refund remains pending until cashier records real outbound payment.
4. Cashier edits after preparation: no restock of cooked food, wastage/disposition auditable.
5. Stock 2 kg, consumption 3 kg: sale succeeds, projected stock −1 kg; receipt 5 kg makes 4 kg; no second deduction.
6. Stock zero on order with both ingredient and packaging BOM: sale succeeds, negatives and warning visible.
7. JazzCash/Easypaisa/Raast/Card payment: cashier records manual verification/reference; sale saved offline without payment API. UI shows ordinary Paid status without verification labels.
8. COD delivered, rider has not handed over cash: revenue/status/pending settlement separate and accurately reported.
9. Manager login cannot create/change a customer's order; cashier login cannot change manager configuration.
10. Concurrent tap/retry on order revision/refund does not double-book sales, tender, stock or refund.

## F. Implementation artifacts

Introduce `order_revisions`, `order_revision_lines`, `order_revision_stock_dispositions`, `payment_manual_confirmations`, `refund_disbursements` if equivalent structures not already present. Use idempotent transactional migrations. Do not mutate finalized Z reports. Add management reports: order revision count and net correction amounts by cashier, cancellations by reason, refunded vs refund pending, negative stock occurrences and recovery, digital methods manually confirmed, rider cash not yet settled.

**Precedence:** This chapter and updated `README.md` supersede any mention of "cashier requests manager PIN for void," "stockout hard block," "manager-configurable stock blocking," or "payment API mandatory" elsewhere. Codex MUST apply these rules, not outdated paragraphs.

**v5 clarification:** Selecting a payment method is sufficient for the cashier-facing POS recording flow; no special gateway-style labels or extra verification screen. The legitimate outstanding states for COD and partial/split payment remain, because they represent whether money was collected, not whether a provider verified it. Also see chapter 31.


---


# 31 — Final mandatory recipe and simplified payments policy (v5)

**Confirmed 12 October 2026. THIS CHAPTER OVERRIDES conflicting statements in Chapters 00–30.**

## 1. Every sellable menu item requires a recipe (BOM)

A Manager (Supervisor/Owner, same permission role) must define the complete ingredient recipe when creating a menu item. The recipe defines ingredients, quantities, compatible measurement units, modifiers/variants and stock usage. The menu item cannot be **active, published, visible or sold** without a validated recipe.

- **Draft exception:** Manager may save an *inactive draft* while composing it, but cannot activate it or sell it without a valid BOM. This is for editing convenience, not a sale override.
- **Mandatory recipe gate is backend-enforced**, not just a disabled Flutter button.
- Every variant/size that changes ingredient consumption must have a defined recipe delta.
- Packaging BOM per order mode remains additive and configured; packaging inventory can be negative without halting sale.
- If the business explicitly configures a legitimate non-stock-bearing menu line (e.g., service fee), require a named non-stock classification and rationale. No accidental blank recipe.
- All recipe versions are immutable for historical order reconstruction. Editing creates a new version; older confirmed orders retain original snapshot.

## 2. Every sellable deal also requires a valid expanded recipe

A deal is not an exception. When Manager creates/edits a deal, it must include the complete composed BOM for **all included items and allowed choices**, quantities, modifiers, upgrades and extra packaging. Deal component item recipes must each be valid. Preview aggregate ingredient usage before activation. A missing recipe on **any selectable path** blocks publishing the deal until fixed.

**Deduction must happen once:** On successful cashier order commit, expand the actual selected deal to its constituent recipe components; write stock ledger entries once using stable order/revision IDs. Never deduct ingredient quantities from both a top-level deal BOM and its children again. For a removed/decreased component later, apply only the incremental stock correction with stage-aware cooked/wastage disposition.

## 3. Critical distinction: configuration vs available stock

| Condition | Result |
|---|---|
| Menu/deal recipe missing or invalid | Cannot activate/publish/sell configuration |
| Item recipe complete but ingredient quantity = 0 | Cashier sale continues; record negative stock + alert |
| Item recipe complete but stock is already negative | Cashier sale continues; more stock consumption recorded once |
| New stock arrives after negative balance | Add new receipt; balance automatically nets; **no catch-up second deduction** |

## 4. Cashier payment screen: just methods, no provider statuses

Methods: **Cash · JazzCash · Easypaisa · Bank/Raast · Card · COD · Split**. Cashier chooses the method, fills amount/change where applicable, optionally a reference, and presses **Complete payment**. No official APIs, SDKs, gateways, webhooks, external payment checks inside POS, or secondary provider confirmation.

**DO NOT DISPLAY:** `Unverified`, `Processing`, `Verification pending`, `Awaiting provider`, `Manual confirmation required`, `MANUALLY_CONFIRMED`, `PROVIDER_VERIFIED`, `API connected` or any equivalent payment badge suggesting gateway verification.

**Permitted business/accounting states only:** `Paid`, `Unpaid`, `Partially paid`, `Refunded`, `Refund due` where real financial balances require them. COD shows `Collection due` until the rider/customer pays; split shows remaining amount as appropriate. Ordinary saved electronic sale is displayed simply as **Paid** because cashier selected and recorded it. The POS itself cannot independently prove that an external transfer arrived—reporting and audits capture the cashier, method, amount, timestamp and optional reference.

Payment method selection is **not the same** as default marking COD paid. Preserve rider trip cash handovers and electronic payment/cash drawer separation. Refund must still reflect actual returned money, not merely an order cancellation.

## 5. Role effects

Only **Manager** creates/edits/activates recipes/menu/deals. Only **Cashier** enters checkout/takes customer payments. Manager cannot make bills or operate cashier sessions. Cashier cannot change recipe/BOM to get around recipe completeness. Manager can inspect product and payment audit data.

## 6. QA scenarios

1. Create Burger without recipe → inactive draft saved; cannot activate. Add Bun 1 pc, Patty 150g, Sauce 20g; now activation works.
2. Create Family Deal including Burger and Fries but Fries recipe missing → cannot activate even though Burger is complete.
3. Deal with alternative drink choices → all choices require valid product recipe or explicit non-stock classification; correct chosen option only is deducted.
4. Burger recipe requires 150g but inventory is 0g → bill succeeds, stock -150g, warning recorded; new delivery +1000g yields 850g.
5. Cashier completes JazzCash/Easypaisa/Raast/Card method payment → one step, shows `Paid`; no unverified/processing badges, no gateway calls.
6. Cashier confirms COD → keeps payment due; rider handover and collections reconcile separately.
7. Editing recipe after historical sales → past stock movements, food cost and original bill remain based on immutable prior recipe.


---


# 32 — FINAL ENGINEERING DECISIONS: post-confirmation lock, cash rounding, tax defaults, tokens, onboarding, modifiers (v6)

**Authoritative as of 12 October 2026. This chapter resolves the six detailed implementation decisions presented after v5 and takes precedence wherever older documents contradict it.** The product still has exactly two login roles: Cashier and Manager (Supervisor = Owner). Manager does not bill customers. Cashier actions listed here require NO manager PIN and remain fully audited.

## 32.1 Confirmed order revisions and rider trip settlement lock

- **Cashier may amend or cancel a confirmed order** in `Confirmed`, `Preparing`, `Ready`, and `Out for Delivery` while its linked rider trip has **not** reached `Settled`. Changing an out-for-delivery order must prominently flag the rider/dispatch reconciliation and record a communication/action-required event. Save revision `before` and `after` snapshots, cashier, timestamp, reason, price/tax/discount/fee deltas and stock disposition. No manager PIN.
- **If the associated rider trip is `Settled`, direct cart/line edits are locked**, regardless of the displayed order status. A correction to money previously collected is a separate **Refund/Adjustment** document with explicit actual disbursement, actor, reason, and settlement/audit links. Do not rewrite the prior trip handover or finalized order revisions.
- **For additions after settlement**, create a *new order* rather than editing settled lines. A refund must never have a positive extra-sale amount or create new item quantities. An already closed/locked business day also forbids in-place order changes; date later corrective documents in the current open business day.
- A rider trip that is returned but **not yet settled** is still editable subject to other order/business-day locks. Status and trip settlement are distinct. Avoid depending on literal status names alone: enforce a persisted `settled_at_utc` / settlement posting lock checked transactionally.
- If there is **no rider trip**, settlement-lock condition is false; business-day closure and other financial locks still apply.
- Cancellation of a paid order does not itself mean money was refunded. Log refund due/pending versus cash/online refund actually performed. Stock returns require unprepared vs already-cooked disposition.

**Atomic edit transaction:** verify cashier session, business day still editable and no settled trip; compare order revision number; insert `order_revisions` + `order_revision_lines`; insert price/tender receivable/stock deltas and audit; advance `orders.current_revision`; commit once with idempotency key. A failed comparison must reload, not overwrite.

## 32.2 Schema: durable revisions and nullable drawer approver

Add **real Drift/SQLite migrations**, not only Dart model classes. At minimum:

```sql
CREATE TABLE order_revisions (
  id TEXT PRIMARY KEY,
  order_id TEXT NOT NULL REFERENCES orders(id),
  revision_no INTEGER NOT NULL CHECK (revision_no >= 1),
  prior_revision_id TEXT REFERENCES order_revisions(id),
  action TEXT NOT NULL CHECK (action IN ('ADD','CHANGE','REMOVE','CANCEL','CORRECTION')),
  reason TEXT NOT NULL,
  cashier_id TEXT NOT NULL REFERENCES staff(id),
  business_day_id TEXT NOT NULL REFERENCES business_days(id),
  created_at_utc TEXT NOT NULL,
  old_total_paisa INTEGER NOT NULL,
  new_total_paisa INTEGER NOT NULL,
  money_delta_paisa INTEGER NOT NULL,
  prior_snapshot_json TEXT NOT NULL,
  new_snapshot_json TEXT NOT NULL,
  command_id TEXT NOT NULL UNIQUE,
  UNIQUE(order_id, revision_no)
);
CREATE TABLE order_revision_lines (
  id TEXT PRIMARY KEY,
  revision_id TEXT NOT NULL REFERENCES order_revisions(id),
  original_order_line_id TEXT,
  item_id TEXT,
  action TEXT NOT NULL,
  old_qty_decimal TEXT NOT NULL,
  new_qty_decimal TEXT NOT NULL,
  line_price_delta_paisa INTEGER NOT NULL,
  bom_disposition TEXT NOT NULL,
  ingredient_delta_snapshot_json TEXT NOT NULL
);
```

Existing `cash_movements.approved_by` **MUST be nullable** (`TEXT NULL REFERENCES staff(id)`). Routine cashier shift `PAY_IN` and `PAY_OUT` events do not need manager approval. `approved_by=NULL` means not manager-approved/approval not applicable, **not** missing an audit actor. Always require `actor/cashier_id`, movement type, positive amount, reason/source and idempotency key. Only special manager-authorized adjustments, if separately introduced, populate `approved_by`; do not make ordinary expense/drawer pay-in/out depend on it. For an existing SQLite NOT NULL column, perform a safe table-rebuild migration preserving records, foreign keys and indexes (SQLite cannot directly DROP NOT NULL). Test old-db upgrades.

`orders` must carry persisted `current_revision` and lock/version state. Optional `settled_at_utc` may be denormalized only if linked to authoritative settled trip posting. Ensure transaction checks for concurrent trip settlement and revision attempts; one must win and the other retry/fail cleanly.

## 32.3 Integer paisa and cash-only rounding policy

All calculation amounts remain **signed 64-bit integer paisa** (`Rs.1=100 paisa`). **Round physical cash due to the nearest whole rupee (100 paisa)** using mathematical **half-up for nonnegative amounts**; e.g., positive residue 50 paisa goes up. This is a *business display/tender rounding*, not a rounding of item price, tax calculations or digital tenders. Default rounding increment is exactly `100 paisa`, not Rs.5 or Rs.10; a configurable denomination policy can be added later as an explicit separate decision.

```text
round_cash_paisa(cash_due_exact_paisa) =
    floor((cash_due_exact_paisa + 50) / 100) * 100     // only cash_due >= 0
cash_rounding_paisa = rounded_cash_due_paisa - cash_due_exact_paisa
```

- For **cash-only**, exact order due 61,625 paisa (Rs.616.25) → cash due 61,600 (Rs.616), `cash_rounding_paisa = -25`.
- 61,650 → cash due 61,700 (Rs.617), rounding `+50`; 61,649 → 61,600 (`-49`).
- **Digital only** (JazzCash, Easypaisa, Card, Bank/Raast) retains 61,625 paisa exactly; `cash_rounding_paisa=0`.
- **Split tender:** first subtract *exact* valid noncash components from the exact remaining invoice; round the **final balancing cash portion exactly once**. Example Rs.616.25 total − Rs.200.00 wallet = Rs.416.25 cash exact → Rs.416 cash actual, delta −25 paisa; the wallet remains Rs.200.00. Digital Rs.200.25 → cash Rs.416.00, delta 0. Do not repeatedly round separate installments or round the entire order before allocating digital tender. Require the cash leg to be the final balancing payment for this initial version.
- Cash tendered and change are calculated against **rounded physical cash due**; change is whole-rupee. Prohibit cash underpayment; keep digital amounts untouched. Persist exact total, cash-rounding delta and finalized payable as separate values.
- On **COD cash collection** at delivery, apply the same rounding exactly once when the due balance is actually paid in cash, not at order confirmation if payment channel is still uncertain. Rider expected cash and handovers use that cash due amount. COD digital collection remains exact.
- `cash_rounding_paisa` must be stored as a signed integer on the finalized financial document/tender close (and reflected in a `ROUNDING_GAIN_LOSS` ledger account); do not bury it inside a menu item price, tax, discount, or net sale revenue. Ensure shift expected cash, day Z, refunds and analytics reconcile with the effective collected amounts. During refunds, reverse/allocate previous rounding explicitly rather than rerounding historical item totals.
- Never use floating point for 15%, prorated deal allocation, unit conversions involving money or tax: use integer arithmetic or checked fixed-decimal rational computation with a documented deterministic residue allocation to line IDs.

## 32.4 Tax defaults: predictable shelf prices, not legal assumptions

New restaurant setup defaults: `tax_pricing = TAX_INCLUSIVE`; `tax_rate_bps = 0` (0%) **until Manager configures a verified applicable rate and rules**. Show exactly the catalog price as the customer-facing item price. Never automatically add a tax percentage on top of a displayed item price under the default.

- **Inclusive rate example only:** manager sets 13% for a legally applicable category. Item display price Rs.500 stays Rs.500. Included tax is calculated from price using rational inverse formula, e.g. `tax_included = rounded_paisa(50000 * 1300 / 11300)`; taxable base = displayed price − included tax. Do not treat 13% as a legislated universal default.
- Different items, delivery fee and payment method may have different legally applicable treatment. Manager must configure these according to current advice from an accountant/tax advisor, including any required tax-inclusive/exclusive differentiation. Tax at checkout cannot silently change catalog total.
- Keep price/tax snapshots and tax-code revisions for historical receipts/reporting. Discount allocation and percentage rounding must use exact money arithmetic. Tax reporting requires final approved policy before go-live.

## 32.5 Daily tokens are consumed once and never recycled

- A confirmed order receives its business-day-local token via an **atomic persisted counter** in the checkout SQLite transaction. UNIQUE `(business_day_id, token_number)`.
- On a successful commit, token is permanently used even if the order is later canceled, edited, refunded or returned. Token #14 canceled → next is **#15**. Do not renumber orders or fill gaps from cancellations.
- Unconfirmed/held drafts **do not** receive tokens. A failed/rolled-back confirmation transaction has no committed token/order and may retry safely. Never allocate an order token outside the atomic commit. Business day change resets the separate day's sequence only.
- Duplicate click/retry with same idempotency key returns the same committed order and same token; never creates another order.

## 32.6 First-run setup cannot strand the restaurant without a Cashier

Initial setup wizard, in order:
1. Restaurant identity, local storage/backup location and business currency (PKR), with initial tax-inclusive/0% default clearly shown.
2. Create **first Manager (Supervisor/Owner)** PIN; unique 4–8 digits, securely hashed, and manager-only configuration access. Manager can never perform cashier billing.
3. **REQUIRED: Create primary Cashier account and unique 4-digit PIN**, different from Manager. Explicit heading: **“Create your primary Cashier counter profile and 4-digit PIN.”** Cashier may use later approved 4–8 digit PIN policy, but wizard defaults/asks exactly 4 digits for the primary cashier. The wizard cannot finalize without one enabled Cashier.
4. Create/defer restaurant menu setup; no saleable items without mandatory validated recipes. Explain the prerequisite rather than seeding fake recipe-less saleable products. Offer a reviewed import or a guided first recipe.
5. Manager opens the first **business day** (or the wizard provides a Manager-authorized Open Day action). Then a guided **Switch to Cashier** button opens cashier PIN login; cashier opens shift and opening float; only then is billing enabled. Show the checklist until ready, without logging a Manager into a Cashier session.

If the database is restored or Cashier is later deactivated, manager startup dashboard must show **“No active cashier — create one”** rather than misleading checkout. Ensure PIN uniqueness, role separation and recovery process.

## 32.7 Mutually exclusive modifiers and deterministic recipe calculation

- `modifier_groups` need explicit `selection_mode` = `SINGLE` (radio) or `MULTI`, `min_selected`, `max_selected`, `required`, and sort order. `modifier_options` belong to groups; optional explicit conflict-pairs may cover cross-group conflicts.
- Define **Sauce preference** (`SINGLE`, exactly one): `Normal Mayo` (base recipe 20g), `No Mayo` (target 0g), `Extra Mayo` (target base+30g = 50g, optional +Rs.30). UI auto-replaces the previous choice in that group. **No Mayo and Extra Mayo can never coexist**.
- Define recipe modifier semantics in terms of **target net ingredient consumption or delta from a known base**, never ambiguous combinations of “remove” and “add” with different ordering. Base recipe 20g + No Mayo delta −20g ⇒ 0g; Extra Mayo delta +30g ⇒ 50g.
- Additional unrelated modifiers (e.g. cheese and spice level) may be separate groups, with MULTI selection only when physically combinable. Enforce exclusivity both in UI and domain validators; reject invalid legacy/imported modifier combinations at sale commit.
- Deal choice modifiers and variants must obey identical group/conflict constraints, and all allowed selectable paths must have a complete validated recipe. Snapshot selected modifiers, price and BOM delta per order revision.

## 32.8 Acceptance tests (mandatory)

1. Edit Preparing, Ready, Out for Delivery orders as cashier: no manager PIN, logs revisions and stock/payment differences; rider communication flag on dispatched orders.
2. Set linked rider trip Settled: direct item/quantity/price edits rejected even if order remains Out for Delivery; new sale requires new order; refund correction creates separate document. Manager cannot edit cashier order.
3. Create revisions with same idempotency key twice: one revision only; concurrently settle trip and edit order: exactly one conflicting action succeeds deterministically.
4. Cash movement PAY_IN/PAY_OUT by cashier with `approved_by=NULL` persists, reason/cashier/time mandatory; migration from legacy NOT NULL schema preserves events.
5. Rs.725 with 15% discount → Rs.616.25 exact; cash sale Rs.616 and rounding −25 paisa; digital sale Rs.616.25, delta zero; split residual rounding exactly once; no fractional cash change.
6. Initial tax inclusive 0% item price Rs.500 → bill Rs.500 exactly. Configured 13% inclusive remains Rs.500 and included tax is broken out, not added on top.
7. Confirm token #14 then cancel → next order #15; held carts tokenless; retry same confirmation returns same token; new business day starts #01.
8. Fresh installation cannot finish without Manager and Cashier (distinct PINs); guided day open and cashier shift open lead to first bill; Manager checkout denied.
9. No Mayo selected then Extra Mayo → No Mayo auto-deselected; base sauce 20g plus Extra Mayo 30g posts 50g. Contradictory imported modifiers fail validation.
10. Post-order stock at zero/negative is allowed and subsequent receipts net without double consumption; every sellable menu and deal still requires a valid BOM.

## 32.9 Still needing owner/accountant configuration

These policies close the enumerated implementation ambiguities, but **do not mean the whole ERP has no unresolved decisions**. Actual applicable Pakistan/provincial tax rates and registrations, refund funding policy, negative-stock valuation method, cash discrepancy thresholds, depreciation/general accounting treatment, payment recipient details, and supplier-pack conversion settings must still be finalized before go-live. No claim of universal tax law is made here.


---


# 33 — Confirmed final workflow, delivery zones, and optional menu/deal images (v7)

**Authoritative update: 18 October 2026.** Supersedes contrary steps in Chapters 00–32. Chapters 30, 31, 32 remain authoritative for their respective confirmed decisions.

## 33.1 Cashier item entry → customer details → payment → one final commit

**User expectation:** Cashier rapidly builds cart (e.g. two burgers and fries), selects *Continue — Customer Details*, enters or finds customer, and only after this step chooses payment and completes the order.

- `Continue — Customer` is not actual confirmation. No token, order record in `CONFIRMED`, tender ledger or stock BOM posting before final `Complete Order`.
- Customer fields for delivery: **name, phone, delivery area, full delivery address** (house/street/building), optional landmark, alternate phone, customer notes and delivery instructions. Business may configure reasonable validation constraints; ensure delivery requires usable contact and address.
- Search by normalized phone while typing; display matching customers and saved addresses. Selecting a customer fills details, but cashier can explicitly choose another saved address.
- Dine-in and takeaway can use Guest/Walk-in and skip delivery-only fields.
- The *selected area* is Manager-controlled, and its fee and availability are validated before final transaction. Fee is shown in order total; fee and area name are snapshotted.
- Payment choices remain simple/manual with no wallet/gateway states. Final commit is atomic and idempotent; UI keeps draft intact on errors.
- For later edits to confirmed orders, follow Chapter 30 and Chapter 32 (no Manager PIN, lock direct cart edits after rider trip settlement).

## 33.2 Manager CRUD for service areas

The **Manager**, equivalent to Supervisor/Owner, can add, edit, activate/deactivate, and archive delivery areas; only unused zones may be hard-deleted. Fields: area ID, name, optional code, coverage description, available yes/no, delivery fee integer paisa, optional minimum order/ETA, and optional business hours. Cashier may **only select** enabled serviceable zones for new delivery orders and cannot change fees.

- Selecting unavailable or deactivated zone is rejected at final order commit, including race when Manager updates while cart is open.
- Manager can change availability without deleting historical orders.
- Preserve order-time immutable area name/address/delivery fee snapshots for historical reports and settlements.
- If customer is outside supported areas, cashier may switch to takeaway or select another supported address, not override delivery eligibility.
- Area list is explicit local data, no Google Maps integration required.
- Reporting should support sales/order value/failures by delivery area.

## 33.3 Optional multi-photo menu and deal galleries

Manager can upload **one or more raster pictures** per menu item **and** per deal, and may choose which is primary. The UI **encourages** adding a clear picture, but it must NEVER be compulsory.

- Supported: JPEG, PNG, WebP (configurable upload size/pixel limits); safe decode, strip EXIF, generate thumbnails. Multiple images with reorder, preview, replace, primary selection, delete and optional alt text.
- Local SQLite references plus offline file storage; include media in backup/restore integrity.
- Cashier grid uses primary image or text/category fallback; it must be fast with no horizontal/vertical distraction or upload dependency.
- **Recipe completeness is still mandatory**, per Chapter 31, on both menu items and every deal-component option. Missing pictures do not prevent publishing, missing recipes do.
- Image additions/removals do not change BOM versions, pricing, past order ledger or customer bills.
- Role security: Manager can create/update/delete images; Cashier can read published thumbnails only.

## 33.4 Revised permissions

| Action | Cashier | Manager |
|---|---|---|
| Build cart, customer selection, payment and final order save | YES | NO |
| Look up customer and select saved delivery address | YES | Read for management purposes |
| Select available delivery area | YES | NO via cashier session |
| Configure/disable delivery areas and fees | NO | YES |
| Create/edit/remove menu/deal pictures | NO | YES |
| Activate recipe-complete item without any photo | NO | YES |
| Adjust a confirmed order without PIN (before trip settled) | YES | NO |

## 33.5 Required schema and invariants

Create/extend `delivery_areas`, `customer_addresses`, `catalog_images` and indexed relationships; see Chapter 16. Do not mutate old order snapshots when zone or image details change. Gallery images are files in local app media directory; DB stores relative paths and checksums. Historical confirmed orders must remain reconstructible if a zone or image is later deactivated.

## 33.6 Mandatory acceptance tests

- Cart of three items → customer screen → final payment confirmation; tokens/stock generated only once on final save.
- Existing phone/addresses prefill accurately; choosing a different address updates area and fee.
- Manager creates area `Gulshan`, activates it, fee Rs. 150; cashier can select it. Manager disables it mid-checkout: final save gives recoverable error without losing cart.
- Manager edits fee to Rs. 200; new delivery order gets Rs. 200; historical order remains Rs. 150.
- Valid item/deal with complete BOM but zero pictures can be published and sold.
- Manager uploads multiple pictures, sets primary, replaces, archives one; thumbnail persists across app restart and offline backup/restore.
- Unsupported/invalid/oversize pictures rejected; cashier cannot upload or modify them.
- Manager cannot operate cashier sale; Cashier cannot change delivery area setup or recipe gallery.
- Nonblocking stock (including zero/negative) and manual payment methods remain unchanged.


---


# 34 — Final visual theme: Street-Food / Mafia Branding (v8)

**Confirmed 18 October 2026. Authoritative theme update.** This chapter replaces older **Warm Counter** UI color/design direction wherever they conflict. It does **not** change any functional rule from chapters 00–33, including the two roles, mandatory recipes, optional images, cashier order editing, service areas, manual tenders and audit/stock invariants.

## 34.1 Identity and intended feel

High-energy street-food / mafia-influenced restaurant visual identity, inspired by bold menu advertising aesthetics: stylized crown icons, sparing brush-stroke graphics, strong sans-serif headings and realistic product photography. Do not copy Crunch Cartel's actual protected logos, graphics or copyrighted photos; use authorized restaurant assets and original design patterns. Prioritize usability rather than imitation.

## 34.2 Color tokens (suggested, not official brand codes)

| Name | Hex | Usage |
|---|---|---|
| Obsidian Black | `#050708` | Primary app background |
| Dark Navy | `#101820` | Fixed compact sidebar, deepest surfaces |
| Cartel Yellow | `#FFC400` | Primary CTAs, highlighted active navigation |
| Burnt Gold | `#F5A623` | Secondary accents, subtle brush strokes |
| Off White | `#F5F7FA` | Main readable text |
| Card Surface | `#14242D` | Cards, modals, data tables |

Supplement with tested accessible grays/borders and semantic green (ready), amber (preparing), blue (delivery), red (cancelled/failed); the team must validate contrast, especially small text on dark surfaces.

## 34.3 Component principles

- **Background:** black and charcoal, no distracting texture in cashier task surfaces.
- **Sidebar:** fixed, dark, compact, visible labels and clear active-state yellow marker.
- **Cards:** dark navy surfaces, restrained 1px border, subtle shadows; avoid oversized dashboard cards.
- **Primary button:** bright yellow with dark text; high focus affordance, proper disabled/loading states.
- **Typography:** bold sans-serif brand header, readable mid-weight functional text, tabular figures for money and quantities.
- **Icons:** simple outline icon system; yellow highlights only for selected or important states. Crowns belong to brand identity, not generic controls.
- **Tables:** dense yet legible, sortable, compact, accessible row actions. No distracting colors on financial rows.
- **Status badges:** green Ready, amber Preparing, blue Out for Delivery, red Cancelled/Failed; always text + icon, never color alone.
- **Food pictures:** crisp realistic images when Manager has uploaded any; gallery is OPTIONAL and a text/icon fallback always works.
- **Corners:** slightly rounded, mostly 8–12px, not excessive pills.
- **Shadows:** restrained depth, extremely subtle glow only in promotional or brand regions, never as a system health signal.

## 34.4 Flutter token implementation guidance

Create semantic token classes rather than scattered hex literals. Example constants:

```dart
class BrandPalette {
  static const obsidian = Color(0xFF050708);
  static const darkNavy = Color(0xFF101820);
  static const yellow = Color(0xFFFFC400);
  static const burntGold = Color(0xFFF5A623);
  static const offWhite = Color(0xFFF5F7FA);
  static const cardSurface = Color(0xFF14242D);
}
```

Define additional accessible `onSurface`, `secondaryText`, `border`, `focus`, `error`, `warning`, `success`, `info`, `disabled` through the theme. Do not use yellow for every status. Test text-on-yellow and text-on-card in the actual Windows rendering engine; do not presume contrast from raw hex values alone.

## 34.5 Cashier screen layout remains operational

At baseline 1366×768: dark fixed sidebar and narrow header; product grid and search on left, pinned cart/total/Continue action on right. Flow `Cart → Customer Details → Payment → Complete Order`. The main action gets bright yellow. Long product lists scroll inside their own grid only; the whole cashier page and total do not move. Photos use thumbnails and optional manager-uploaded cover, with fallback; price and item title stay prominent. One-tap add, hold/recall, discount presets and configured keyboard shortcuts remain unobstructed.

## 34.6 Manager pages and reports

Apply tokens to Menu & Deals/recipe editor, inventory, suppliers/Khata, payroll, cash expenses, delivery areas, reports, staff PINs and settings. Reports use dark tables and accessible graphs, not excessive yellow charts. Management CRUD sheets maintain labels/validation clearly; yellow primary actions are reserved for Save/Publish/Confirm. Menu/deal editor displays an optional picture uploader and mandatory recipe gate separately.

## 34.7 Pass/fail acceptance

1. Check default light/warm style is no longer present as production default, and theme palette uses exact six provided hex values.
2. Primary yellow CTA is readable with dark text and keyboard focus visible.
3. Cashier at 1366×768 completes a simple sale without page-level scrolling; totals, price and action persist with optional food photographs.
4. Product with no photograph renders designed readable placeholder and can be sold if BOM complete.
5. All four semantic statuses use text and accessible colors.
6. Back-office ledger tables remain readable with many rows and large currency values at 100%, 125% and 150% Windows scaling.
7. Brand crown/brush strokes appear only in restrained identity/accent placement, not on cash fields, error text or stock/count numbers.
8. No copyrighted third-party photos/brand art are bundled without authorization.
9. Complete keyboard and screen-reader focus/contrast acceptance for cashier and Manager forms.

**Precedence:** Chapter 34 governs visual treatment, while chapters 30–33 continue to govern order edits, stock, payments, mandatory recipes, engineering specifics, service areas, customer step and optional media.


---
