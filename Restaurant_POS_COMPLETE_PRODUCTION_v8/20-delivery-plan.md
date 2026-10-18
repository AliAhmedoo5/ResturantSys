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
