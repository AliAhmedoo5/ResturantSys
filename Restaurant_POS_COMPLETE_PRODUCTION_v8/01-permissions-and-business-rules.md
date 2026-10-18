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
| Edit or cancel already-confirmed order (reason + audit) | Yes, no Manager PIN | No (read-only oversight) |\n| Record supported collected-funds refund with strict ledger checks | Yes, no routine Manager PIN | No (read-only oversight) |\n| Review cashier amendments, cancellations and refunds | No | Yes |
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
