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
