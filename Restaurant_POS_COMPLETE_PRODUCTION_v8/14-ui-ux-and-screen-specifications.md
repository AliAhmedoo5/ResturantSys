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
