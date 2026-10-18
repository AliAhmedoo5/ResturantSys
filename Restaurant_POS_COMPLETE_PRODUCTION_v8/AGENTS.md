**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# Implementation instructions for Codex / engineering agents

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


This folder is the functional authority for the production Restaurant POS. Do not implement from screenshots or the HTML demo alone.

## Mandatory corrected role model

Manager (Supervisor/Owner) is the only management role, with identical permissions for both titles; Manager can administer and approve but cannot perform cashier tasks. See chapters 01 and 24.

## Non-negotiable engineering rules

1. Read `README.md`, `01-permissions-and-business-rules.md`, `15-architecture-and-offline-runtime.md`, `16-database-schema.md`, and `17-audit-accounting-and-integrity.md` before writing data-changing code.
2. Follow the numbered module specification. Every mutation must have permission enforcement **in the domain/service layer**, not just hidden buttons.
3. Use Drift transactions for order confirmation, stock postings, purchases, supplier balance events, expense cash movements, shift closes and settlements. No dual-write that can partially succeed.
4. Give each financial/stock operation a unique idempotency key. Prevent double-post on retry, double-click or process restart.
5. Never store PIN plaintext. Design install-level keyed fingerprint for uniqueness plus a slow verifier and rate limits; protect keys with Windows DPAPI. Create first Manager with deliberate onboarding, not a published default PIN.
6. Posted ledger entries are immutable. Correct with a linked opposite-signed entry; preserve original, actor, reason and timestamp.
7. Inactive/deleted catalog entities remain resolvable in old order snapshots. Effective-dated pricing/discounts/deals are copied into committed order lines.
8. Keep order status, payment status, inventory usage, dispatch status and rider cash settlement as **independent** state machines; never infer one from another.
9. Treat the kitchen as face-to-face; **do not add KOT, print queues or a kitchen screen** to the initial build.
10. Ensure the cashier can bill using keyboard and mouse without vertical page scrolling on 1366×768 under normal catalog sizes. Exercise empty, busy, offline, input-error and high-volume states.
11. Do not invent tax percentages, serving weights, actual food-cost data or local payment integration results. Default configuration is editable and business-approved before live transactions.
12. Add tests for every required invariant and acceptance scenario in `19-testing-and-acceptance.md`. Update migrations and fixtures with schema changes.

## Suggested repo layout

```
lib/
  app/                 # app setup, router, theme, role-based navigation
  core/                # result/error types, time, IDs, money, units, auditing
  data/                # Drift db, migrations, DAOs, transaction services
  features/
    auth/ business_days/ shifts/ catalog/ discounts/ pos/ orders/
    customers/ delivery/ riders/ inventory/ procurement/ suppliers/
    cash/ expenses/ staff/ reports/ settings/ backup/
  shared/              # reusable forms, numpad, money fields, modal sheets
 test/                 # domain, repository, widget, integration, migration tests
 integration_test/
 tools/                # export validation, backup restore tests, packaging
```

The domain/service layer is pure Dart where practical. Riverpod controllers coordinate UI; GoRouter handles navigation with role gates; Drift owns transactions and queries. No widgets execute raw SQL.

## Implementation routine

For each module: write migrations → domain models and validation → transactional service → Riverpod state → widget screens → unit/widget/integration tests → role/security review → data migration and recovery tests. Record unresolved choices in `22-decisions-and-assumptions.md`; do not silently assume a new business rule.

## Release gate

Only ship after an offline end-to-end trial on the target Windows machine with a restorable database backup and full shift/day reconciliation. The browser demo is not evidence of production readiness.

## Mandatory review of extended chapters and report sending

Before coding read:
- `23-video-reference-feature-decisions.md`: video feature adoption/exclusion. Do not build KOT/printing merely because it appears in reference footage.
- `24-exhaustive-role-permission-matrix.md`: enforce on every command, not UI visibility only.
- `25-business-day-report-email-whatsapp-delivery.md`: durable report outbox, offline, official API/manual share distinction and recipient permissions.
- `26-complete-feature-catalog-and-operational-manual.md`: user-facing feature definitions.
- `27-screen-by-screen-forms-fields-and-actions.md`: form field, validation and action requirements.
- `28-state-machines-accounting-postings-and-transaction-boundaries.md`: transaction invariants and recovery.
- `29-comprehensive-qa-and-real-restaurant-walkthrough.md`: end-to-end and adversarial acceptance.
Do not create or claim real API integration without configured keys/account/consent. Do not use a mocked sent=true flag for production report delivery. Mark provider-accepted status separately from delivered. Keep first release Windows offline first and kitchen ticket-free. Maintain traceability of **MUST** requirements to automated tests.
\n## Hard requirements confirmed in v4\nRead `30-final-cashier-amendments-stock-and-manual-payments.md` first. Do not request Manager PIN for confirmed-order cashier edits or cancellations; audit every revision. Keep checkout operational at negative stock and never perform catch-up double deductions. Record JazzCash/Easypaisa/Bank/Card/Cash tenders manually with cashier attestation, no API dependency. Managers cannot access cashier checkout. Write regression tests for all four rules.\n
## Authoritative v5 addendum — required recipe + simplified tenders

**Read `31-required-recipes-and-simple-tender-ui.md` before implementation.** Manager must build valid complete recipes for all published menu items and deals, without override; incomplete drafts are not sellable. Cashier payment sheet only selects cash/JazzCash/Easypaisa/Bank-Raast/Card/COD/Split and completes collection, no Unverified/Processing/payment-provider tag and no gateway API. Chapter 31 prevails over earlier contradictory wording.\n

## v6 hard-coded engineering guardrails

Before coding read **Chapter 32**. Enforce rider Settled order-revision lock at SQLite transaction boundary. Create order_revisions and order_revision_lines real tables. cash_movements.approved_by must be nullable. Round ONLY final physical cash tender due to nearest Rs.1 (signed delta) and leave digital exact. Default TAX_INCLUSIVE + 0% in onboarding pending local tax configuration. Never recycle a canceled token; wizard requires unique Cashier PIN; opposing modifiers must be mutually exclusive in both UI and domain validators. Write every Chapter 32 acceptance test.


## v7 authoritative changes (18 October 2026)

Read Chapter `33-final-customer-delivery-area-and-menu-image-decisions.md`. Cashier workflow is **cart → customer/details → payment → final commit**, not a committed sale before customer data. Manager CRUDs delivery service areas and fees; Cashier selects only active/serviceable ones. Menu and deals can carry **multiple optional pictures**, primary image, thumbnails, secure local offline files and fallback when missing; images are encouraged but **not required**. Complete BOM/recipes remain mandatory for published menu/deal configurations. Chapter 33 overrides inconsistent older statements.

## v8 Theme rule (18 October 2026)

Read **`34-street-food-mafia-brand-theme.md`**. The production UI defaults to dark Street-Food / Mafia Branding: `#050708` obsidian, `#101820` navy, `#FFC400` yellow, `#F5A623` gold, `#F5F7FA` text, `#14242D` cards. Restrained crown/brush-stroke identity, bold sans-serif, real optional food imagery, dark dense readable tables, text-labeled semantic statuses. This replaces earlier Warm Counter palette; cashiers must still bill without page scrolling. Chapter 34 has visual precedence; it does not override business rules in chapters 30–33.
