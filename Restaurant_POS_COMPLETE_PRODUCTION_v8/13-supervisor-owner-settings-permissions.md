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
