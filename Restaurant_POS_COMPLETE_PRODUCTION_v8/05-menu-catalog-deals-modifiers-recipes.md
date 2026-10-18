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
