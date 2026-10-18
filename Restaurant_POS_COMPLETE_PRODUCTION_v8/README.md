**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

> **v3 role correction: Supervisor = Owner = single `MANAGER` login role. The Manager NEVER serves as Cashier. The Cashier exclusively handles billing, checkout, live order status, and shift operations. See chapters 01 and 24.**

# Restaurant POS & ERP — FULL PRODUCTION SPECIFICATION v6.0

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


**Updated:** 12 October 2026 · **Status:** full product/engineering requirements for the REAL Windows application · **Not a demo**

**Platform direction:** Flutter Windows + Riverpod + GoRouter + Drift SQLite; offline-first, single restaurant delivery-first. **Reporting delivery:** PDF/XLSX saved locally, automatic email with offline outbox, and manual/official-auto WhatsApp modes as configured. Provider setup and finance/tax business decisions require manager approval before deployment.

## Start here

- **For the restaurant owner:** `26-complete-feature-catalog-and-operational-manual.md` → `24-exhaustive-role-permission-matrix.md` → `27-screen-by-screen-forms-fields-and-actions.md` → `22-decisions-and-assumptions.md`.
- **For Codex/developer:** `AGENTS.md` → `00`–`02` → `23`/`24` → module chapters `03`–`13` → `25`–`29` → `14`–`22`.
- **For QA:** `29-comprehensive-qa-and-real-restaurant-walkthrough.md`, `19-testing-and-acceptance.md`, then chapter-specific acceptance scenarios.
- **For the original video:** `23-video-reference-feature-decisions.md` lists each observed UI behavior, adopted feature, improvement or explicit exclusion.

## Contents of this package

| Files | What they cover |
|---|---|
| `00`–`02` | Scope, principles, permissions, end-to-end daily/financial flows |
| `03`–`05` | Staff/PIN/payroll; fast cashier POS/shortcuts; catalog/deals/modifiers/recipes |
| `06`–`09` | Customer history, riders/delivery, inventory/packaging/counts, suppliers/Khata |
| `10`–`13` | Business day/shifts/cash/expenses; refunds; owner reports; administration |
| `14`–`18` | UI/UX, architecture, database, accounting/audit, security and backups |
| `19`–`22` | QA, phased build, metric definitions and unresolved owner choices |
| **`23`** | **Video feature mapping**: what to build vs exclude |
| **`24`** | **Complete role/action permission matrix** (Owner, Supervisor, Cashier etc.) |
| **`25`** | **Daily report email/WhatsApp: auto/manual, queue, retries, provider integration** |
| **`26`** | **Every user-facing feature and cross-module scenario explained** |
| **`27`** | **All major screens with exact fields, role access, validation and actions** |
| **`28`** | **State machines, source-of-truth ledgers, transaction boundaries and recovery** |
| **`29`** | **Real restaurant walkthrough, role-negative tests, reporting/send acceptance** |
| **`30`** | **Final confirmed cashier order edits/cancellations, negative stock, manual payment rules (v4)** |\n| `AGENTS.md` | Codex/engineering rules and build discipline |
| `README.md` | Navigation, precedence, scope and exclusions |

## Confirmed product decisions (latest wins)

- **No kitchen KOT, printing, kitchen display/token queue, or forced kitchen device**; counter is approximately one meter from kitchen. Cashier manually manages prep statuses; no ticket goes to kitchen. Digital/PDF receipts allowed; physical printer and cash drawer hardware are deferred.
- **Cashier speed**: delivery-first, takeaway and few dine-in tables; no routine scrolling for ordinary bill, instant menu/category/search, hold/recall, repeat customer lookup by phone, item quantity control, payment/change, fixed running total and owner-configurable shortcuts.
- **Supervisor and owner full management of operational masters**: menu/products/categories, combos/deals, discounts, inventory ingredients/packaging, supplier profiles and supplier-specific supplied products, expenses/custom categories, staff PINs and salaries. Posted accounting history is immutable; delete unused, archive used, reverse wrong financial postings.
Manager (Supervisor/Owner) is the only management role, with identical permissions for both titles; Manager can administer and approve but cannot perform cashier tasks. See chapters 01 and 24.
- **Supplier creation includes editable/customizable supplied items**, including arbitrary newly created stock entries. Recording a purchase filters to linked products. Status explicitly distinguishes `No purchases`, `No payments`, `Partially paid`, `Paid` (and vendor credit where applicable).
- **Inventory is non-blocking even at zero or negative stock**: full consumption posted once; later purchase receipts offset negative balances without second deduction.\n- **Confirmed order edits and cancellations need no Manager PIN**: cashier edits/removes/cancels with reason and immutable audit, including correct financial/stock changes. Refunds of collected funds are separate bounded financial postings, not silent cancellations.\n- **Cash/JazzCash/Easypaisa/Card/Raast/Bank are manual cashier-confirmed tender records; no payment APIs are required.**\n- **Inventory** includes recipe BOM, packaging, local units when configured, supplier purchases, physical counts, wastage and reconciliation.
- **Operations** include delivery rider trips/cash handovers, failed/returned orders, blind cash counts, shift/day closures, salary/advance ledger, petty cash and expense categories.
- **Reporting** is broad: actual revenue, item/deal performance, customer trends, rider performance, supplier overdue Khata, inventory/costs, cash variance, payroll and valid profitability only with complete cost data; PDF/XLSX/CSV and scheduled delivery.
- **End-of-day report** generation on local day close, manager-approved email delivery with durable retry, manual WhatsApp share; official automated WhatsApp possible after provider/business setup. Network delivery never blocks day close.
- **Loyalty/rewards deferred**; rider app/GPS, cloud multi-terminal/multibranch, kitchen printing and payment-gateway claims deferred until separately approved.

## Requirement precedence

1. Most recent confirmed manager decisions and this README plus chapters `23`–`30` resolve changes/contradictions from earlier drafts.
2. Domain specifics `03`–`22` remain normative wherever they do not contradict newer confirmed decisions.
3. `22-decisions-and-assumptions.md` contains provisional policies; choose with owner before live transactions. **Do not silently invent tax law/rates, cost valuation, PIN recovery or refund treatment.**
4. Old `01`–`10` documents and the HTML demo are reference material only, not final scope; especially their kitchen hardware/tickets are superseded.

## What to hand Codex

Unzip the package in a project docs folder. Ask Codex to read `AGENTS.md` and `README.md` completely, create a traceability checklist, identify unresolved Manager decisions, then implement milestones in `20-delivery-plan.md` with Flutter Windows, Drift transaction/repositories, Riverpod state, automated tests, no placeholder pretend persistence and no fake WhatsApp/email delivery. Run QA scenarios from `19` and `29` on Windows.

## Important engineering guardrails

- Staff department is not authorization role; check permissions at service boundary. Owner shortcuts never bypass RBAC.
- Never mutate/delete financial or stock events silently; use versioned master data, archive and reversible ledger postings.
- Do not infer paid from delivered or cash from COD order; don't double count supplier and staff payment as petty cash.
- Calculate prices/taxes/discounts/COGS with defined decimal/integer-paisa policy; reconcile source-of-truth ledgers; display missing profit data clearly.
- Local billing and business-day close must survive offline/reboot; report emails/WhatsApp require real transport and lifecycle statuses.
- Test backup **restoration**, not only creation. Avoid default shared PINs, plaintext secrets or unverifiable report delivery claims.

## Authoritative v5 addendum — required recipe + simplified tenders

**Read `31-required-recipes-and-simple-tender-ui.md` before implementation.** Manager must build valid complete recipes for all published menu items and deals, without override; incomplete drafts are not sellable. Cashier payment sheet only selects cash/JazzCash/Easypaisa/Bank-Raast/Card/COD/Split and completes collection, no Unverified/Processing/payment-provider tag and no gateway API. Chapter 31 prevails over earlier contradictory wording.\n

## v6 precedence

**Read `32-final-implementation-decisions.md` first.** It is authoritative on cash rounding, tax-inclusive/0% initial configuration, token burning, compulsory Cashier onboarding, mutually exclusive modifiers, order edits until rider trip settlement, revision table migrations and nullable routine cash-movement approver. It supersedes contradictory language in Chapters 00–31. Other owner-specific tax/legal and valuation policies remain to be approved.


## v7 authoritative changes (18 October 2026)

Read Chapter `33-final-customer-delivery-area-and-menu-image-decisions.md`. Cashier workflow is **cart → customer/details → payment → final commit**, not a committed sale before customer data. Manager CRUDs delivery service areas and fees; Cashier selects only active/serviceable ones. Menu and deals can carry **multiple optional pictures**, primary image, thumbnails, secure local offline files and fallback when missing; images are encouraged but **not required**. Complete BOM/recipes remain mandatory for published menu/deal configurations. Chapter 33 overrides inconsistent older statements.

## v8 Theme rule (18 October 2026)

Read **`34-street-food-mafia-brand-theme.md`**. The production UI defaults to dark Street-Food / Mafia Branding: `#050708` obsidian, `#101820` navy, `#FFC400` yellow, `#F5A623` gold, `#F5F7FA` text, `#14242D` cards. Restrained crown/brush-stroke identity, bold sans-serif, real optional food imagery, dark dense readable tables, text-labeled semantic statuses. This replaces earlier Warm Counter palette; cashiers must still bill without page scrolling. Chapter 34 has visual precedence; it does not override business rules in chapters 30–33.
