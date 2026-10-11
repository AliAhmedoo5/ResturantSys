# Fast-Food POS & Operations System Specification

## Problem Statement

Newly launched fast-food restaurant owners face prohibitive costs and operational friction when relying on cloud-based point-of-sale systems. Recurring monthly software subscriptions drain razor-thin startup margins, while unstable in-store internet connections lead to counter freezes during rush hours. Furthermore, restaurants frequently suffer from financial shrinkage and operational chaos due to:
1. Cashier fraud and undocumented cash drawer access.
2. Inventory theft disguised as unrecorded food waste or kitchen prep errors.
3. Inaccurate recipe-level stock tracking where assembled meals (combos, burgers) do not deduct raw components.
4. Mismatches between corporate procurement models and local wholesale markets, where ingredients are bought in traditional measures (Mann, Darjan, Peti) or on informal supplier credit (Vendor Khata).
5. Cumbersome end-of-day accounting that relies on open spreadsheet editing prone to file locking, formula corruption, and data tampering.

## Solution

A standalone, offline-first Desktop POS & Operations System built with Flutter and an embedded SQLite database running locally on an in-store Windows laptop or PC. The system eliminates cloud dependencies, subscription fees, and internet reliance. It provides:
1. High-speed counter billing with customizable keyboard hotkeys, dynamic modifier handling, 1-tap combo choice selectors, and rapid change calculation.
2. Decoupled silent dual-ticket thermal printing (Customer Tax Receipt and Kitchen Order Ticket) with automatic RJ11 cash drawer kicks on cash tenders and an asynchronous reprint queue.
3. Recipe-level Bill of Materials (BOM) inventory engine with soft stock deduction (allowing negative balances during peak rushes without halting sales).
4. Localized "Quick Mandi Purchase" flow supporting traditional wholesale units (Mann, Darjan, Peti, Bori) and an integrated Vendor Khata for supplier credit tracking.
5. Strict anti-theft shift controls featuring blind cash drawer counts (X-Report and Z-Report), non-blocking discrepancy logging, supervisor PIN overrides, and automatic kitchen void slips.
6. 1-click generation of a comprehensive, tamper-resistant 6-sheet daily Excel workbook (.xlsx) capturing revenue, item sales, ingredient consumption, wastage, shift audits, and supplier balances with unalterable audit timestamps.

## User Stories

### Counter Billing & Cashier Operations
1. As a cashier, I want to log into the terminal using a 4-digit numeric PIN, so that I can unlock the register in seconds without typing alphanumeric passwords.
2. As a cashier, I want to input my opening float at the start of my shift, so that my drawer base cash is registered before taking orders.
3. As a cashier, I want to browse menu items via large touch-friendly category tabs and item tiles, so that I can quickly locate food during a customer rush.
4. As a cashier, I want to navigate and ring up orders using customizable keyboard hotkeys, so that I can operate at maximum speed on a standard laptop without trackpad clicks.
5. As a cashier, I want to tap a Deal on the menu grid to open a 1-tap selection modal with radio groups for drink and side choices, so that I can record customer preferences in seconds.
6. As a cashier, I want to select optional add-on modifiers (e.g., Extra Cheese) that increase the price and adjust the recipe deduction, so that customer customizations are billed accurately.
7. As a cashier, I want to select ingredient removal modifiers (e.g., No Mayo) with zero price change, so that the kitchen is notified and zero sauce is deducted from stock.
8. As a cashier, I want to select a Dining Type (Dine-In, Takeaway, Delivery) for each order, so that kitchen staff know how to pack the food and takeaway packaging is automatically deducted.
9. As a cashier, I want to edit, remove, or discard unpaid cart items without supervisor permission, so that ordering mistakes before payment create zero operational friction.
10. As a cashier, I want to select from pre-approved discount buttons configured by management without needing a supervisor PIN, so that promotional checkout moves quickly while logging my cashier ID.
11. As a cashier, I want to enter the cash amount tendered by a customer and see the exact change return calculated in large numerals, so that mental math mistakes are eliminated under pressure.
12. As a cashier, I want to settle orders using Cash, Card, Raast QR, or Split Tender (e.g., partial cash and partial Raast), so that customer payment flexibility is fully supported.
13. As a cashier, I want the system to silently print a Customer Receipt and Kitchen Order Ticket (KOT) with a daily sequential Token number upon checkout, so that food assembly and pickup proceed smoothly.
14. As a cashier, I want the cash drawer to automatically kick open only on Cash transactions, so that the drawer remains safely locked during card and Raast settlements.
15. As a cashier, I want a dedicated Reprint tray to reprint the last receipt or KOT with a single tap, so that paper jams or printer disconnects do not block ongoing counter sales.
16. As a cashier, I want to record Cash Pay-In and Pay-Out movements (petty cash for ice, milk runs, or owner cash drops) with amounts and mandatory notes, so that drawer cash outflows are accounted for.
17. As a cashier, I want to submit a blind physical cash count at shift handover without seeing system totals, so that my shift closes cleanly and generates an interim X-Report.
18. As a cashier, I want to hand over the register to the next cashier even if my blind count has a discrepancy, so that line operations are never frozen while awaiting supervisor review.
19. As a cashier, I want to initiate a void on an already-printed order by picking a reason and calling a supervisor, so that customer cancellations after payment are properly audited.

### Kitchen Staff Operations
20. As a kitchen cook, I want to receive a printed KOT displaying the Token number and Dining Type in large bold text without prices, so that I can prepare orders accurately without clutter.
21. As a kitchen cook, I want the KOT to clearly highlight meal modifiers and bundle choices (e.g., + EXTRA CHEESE, *** NO MAYO ***), so that cooking mistakes are avoided.
22. As a kitchen cook, I want the printer to automatically output a bold KOT Void Slip whenever an order is cancelled post-print, so that I immediately halt cooking and eliminate food waste.
23. As a kitchen cook, I want to switch to the on-screen Kitchen Token Station using my Kitchen PIN and tap active tokens to mark them Ready, so that counter staff know food is on the pass.
24. As a kitchen cook, I want to log kitchen food wastage (burned patties, dropped buns) under my Kitchen PIN with categorized reasons, so that accidents are distinguished from inventory theft.

### Supervisor & Owner Operations
25. As a supervisor, I want to authorize sensitive actions (post-print voids, drawer overrides, high discounts) via a transient 4-digit PIN modal, so that permissions are verified without logging out the cashier.
26. As a supervisor, I want to manage universal staff profiles across custom departments (Front Counter, Kitchen, Management), assigning names, PINs, and operational roles.
27. As a supervisor, I want to toggle operational feature flags (Token Tray on/off, Cashier Void Requests on/off), so that the POS interface adapts to my restaurant's workflow.
28. As an owner, I want to create and manage Menu Categories, Menu Items, and tax-inclusive pricing, so that counter prices remain round figures while taxes are back-calculated.
29. As an owner, I want to define recipe Bill of Materials (BOM) linking menu items and modifiers to raw ingredients, so that inventory is deducted at the ingredient level upon sale.
30. As an owner, I want to configure Deals and Combos with bundled item groups and upgrade options, so that promotional meal sets automatically decompose into their raw components.
31. As an owner, I want to create pre-approved discount campaigns with defined percentage or flat rupee limits, so that cashiers can apply promotions without manager intervention.
32. As an owner, I want to use a localized "Quick Mandi Purchase" screen with traditional units (Mann, Darjan, Peti, Bori, Dharri, Pao), so that wholesale market purchases automatically calculate recipe unit costs.
33. As an owner, I want to manage a Vendor Khata for suppliers who deliver on credit, logging delivery slips, phone numbers, and outstanding balances.
34. As an owner, I want to settle Vendor Khata balances either directly from active drawer cash (auto-logging Pay-Out) or outside the drawer from bank funds, so that drawer cash balance integrity is maintained.
35. As an owner, I want counter sales to proceed even when stock balances reach or drop below zero during a rush, so that delayed inventory entry never blocks customer queues.
36. As a supervisor, I want an asynchronous Discrepancy Review queue to inspect flagged cashier shifts with high cash variances, reviewing historical discrepancy logs without register downtime.
37. As a supervisor, I want to perform the End-of-Day Z-Report, locking all shifts, resetting the daily token sequence to #01, and concluding the Business Day.
38. As an owner, I want the system to automatically backup a timestamped copy of the SQLite database to a local archive and secondary external/USB path on every Z-Report, so that historical data is disaster-proof.
39. As an owner, I want to download a comprehensive 6-sheet daily Excel workbook (.xlsx) with 1 click, capturing revenue, item sales, stock consumption, wastage, shift audits, and vendor balances with ISO audit timestamps.

## Implementation Decisions

### Architectural Shape
- Standalone single-instance Flutter desktop application running locally on Windows 10/11.
- Embedded local SQLite database via direct FFI bindings, stored in secure local application data directory (`%ProgramData%\ResturantPOS\data\pos.db`). Zero client-server databases, zero background cloud synchronizers, and zero open spreadsheet read/write operations.
- Fullscreen touch-optimized Kiosk Mode with customizable keyboard hotkey acceleration.
- UI Design System: "Warm Counter" theme featuring calm neutral surfaces, deep green primary actions, Inter/Segoe UI typography with tabular figures, and 48px touch targets (see ADR-0007 and `docs/design/warm-counter-theme.md`).

### High-Level Domain Modules & Seams
1. **`PosOperationsEngine` (Primary Facade Seam)**:
   - Exposes public application methods for Business Day lifecycle, shift management, atomic order checkout, supervisor voids, inventory movements, Khata settlements, and Excel exports.
   - Manages atomic SQLite transactions ensuring that financial ledger rows, inventory ledger rows, and audit trails commit or rollback together.
2. **`InventoryEngine`**:
   - Manages Raw Ingredients, 3-tier Recipe BOM decomposition (Raw Ingredient ➔ Menu Item ➔ Deal/Combo), and modifier adjustments.
   - Executes soft inventory deduction policy: logs negative stock balances with low-stock audit warnings without throwing checkout exceptions.
   - Provides Desi Mandi conversion multipliers (`1 Purchase Unit = N Recipe Units`).
3. **`ShiftAndCashController`**:
   - Manages Business Day lifecycle (spanning across midnight with supervisor authorization) and sequential Cashier Shifts.
   - Implements blind count discrepancy evaluation: $\text{Discrepancy} = \text{Counted Cash} - (\text{Opening Float} + \text{Cash Sales} + \text{Cash Pay-Ins} - \text{Cash Pay-Outs})$.
   - Enforces non-blocking discrepancy logging: flags shifts exceeding supervisor threshold without halting counter operations.
4. **`HardwareDeviceAdapter` (Hardware Seam)**:
   - Emits raw ESC/POS byte streams supporting 80mm standard paper (with 58mm compact toggle) and hardware auto-cutter commands (`GS V 0`).
   - Configurable printer routing: Single Printer (sequential dual cuts) or Dual Printer (Counter USB + Kitchen Network/USB).
   - Generates RJ11 drawer kick pulse (`ESC p 0 25 250`) strictly on Cash tenders and supervisor manual drawer overrides.
   - Houses asynchronous Reprint Queue for failed or jammed print jobs.
5. **`ExcelReportingEngine`**:
   - Generates structured, pre-formatted multi-sheet `.xlsx` workbooks containing:
     1. Executive Summary
     2. Sales by Item
     3. Stock & BOM Consumption
     4. Kitchen Wastage Log
     5. Shift Handover Audits
     6. Vendor Khata Ledger
   - Stamps all exported records with unalterable local audit timestamps (`YYYY-MM-DD HH:MM:SS`).

### Core Database Entities & Schemas
- `business_days`: `id`, `opened_at`, `closed_at`, `opened_by_staff_id`, `closed_by_staff_id`, `status` (`OPEN`, `CLOSED`).
- `shifts`: `id`, `business_day_id`, `staff_id`, `opened_at`, `closed_at`, `opening_float`, `counted_cash`, `expected_cash`, `discrepancy`, `discrepancy_status` (`CLEAN`, `FLAGGED`, `RESOLVED`), `status` (`OPEN`, `CLOSED`).
- `staff`: `id`, `name`, `department_id`, `pin_hash`, `role` (`CASHIER`, `KITCHEN`, `SUPERVISOR`, `OWNER`), `is_active`.
- `departments`: `id`, `name`, `created_at`.
- `categories`: `id`, `name`, `display_order`, `color_hex`.
- `menu_items`: `id`, `category_id`, `name`, `base_price`, `tax_rate`, `is_tax_inclusive`, `is_active`.
- `raw_ingredients`: `id`, `name`, `storage_unit` (`g`, `kg`, `ml`, `count`), `current_stock`, `low_stock_threshold`, `cost_per_recipe_unit`.
- `recipes`: `id`, `menu_item_id`, `raw_ingredient_id`, `quantity_per_recipe_unit`.
- `deals`: `id`, `name`, `base_price`, `is_active`.
- `deal_items`: `id`, `deal_id`, `category_id_or_group`, `default_menu_item_id`, `is_upgradeable`, `upgrade_price`.
- `modifiers`: `id`, `name`, `menu_item_id`, `price_delta`, `raw_ingredient_id`, `ingredient_qty_delta`.
- `orders`: `id`, `business_day_id`, `shift_id`, `cashier_id`, `token_number`, `dining_type` (`DINE_IN`, `TAKEAWAY`, `DELIVERY`), `subtotal`, `discount_amount`, `discount_id`, `tax_amount`, `grand_total`, `payment_status` (`SETTLED`, `VOIDED`), `created_at`.
- `order_items`: `id`, `order_id`, `menu_item_id`, `deal_id`, `quantity`, `unit_price`, `total_price`, `modifiers_json`.
- `order_payments`: `id`, `order_id`, `payment_method` (`CASH`, `CARD`, `RAAST`), `amount_tendered`, `change_returned`, `reference_code`.
- `order_voids`: `id`, `order_id`, `voided_by_supervisor_id`, `cashier_id`, `reason`, `voided_at`.
- `cash_movements`: `id`, `shift_id`, `staff_id`, `type` (`PAY_IN`, `PAY_OUT`), `amount`, `category`, `notes`, `created_at`.
- `vendor_khata`: `id`, `vendor_name`, `phone`, `current_balance`, `updated_at`.
- `vendor_transactions`: `id`, `vendor_id`, `shift_id`, `type` (`PURCHASE_CREDIT`, `PAYMENT_DRAWER`, `PAYMENT_EXTERNAL`), `amount`, `reference_slip`, `notes`, `created_at`.
- `kitchen_wastage`: `id`, `staff_id`, `raw_ingredient_id`, `quantity`, `cost_loss`, `reason` (`BURNED`, `DROPPED`, `EXPIRED`, `TESTING`), `created_at`.
- `system_settings`: Key-value configuration for printer topology, paper width (80mm/58mm), discrepancy threshold, feature toggles (Token Tray, Void Requests), hotkey bindings, and backup directory paths.

## Testing Decisions

### What Makes a Good Test
- Tests must verify observable external behavior and state outcomes, never private implementation trivia or internal method call ordering.
- Tests exercise domain boundaries using real SQLite database instances (in-memory or transient test database files) to validate relational integrity, constraint violations, and transactional rollbacks.
- Hardware devices are tested via in-memory adapter fakes capturing raw ESC/POS byte buffers to assert ticket typography, cut commands, and drawer pulse codes deterministically.

### Modules Under Test
1. **`PosOperationsEngine` Integration Tests**:
   - Business day and shift lifecycle transitions (opening, handover, closing, extending past midnight).
   - Atomic checkout execution: verify accurate tax calculation, sequential token reset at new Business Day, and correct raw ingredient stock deductions across complex combos and modifiers.
   - Soft inventory tolerance: verify that checkout succeeds and records negative stock when ingredients are at zero balance.
   - Void transaction testing: assert that post-print voids require supervisor PIN, record void audit records, reverse ingredient consumption, and dispatch KOT void slips.
   - Blind cash discrepancy calculations: assert exact variances across opening floats, sales, cash pay-ins, and pay-outs.
   - Non-blocking discrepancy policy: assert that high-discrepancy shifts flag status for supervisor review while allowing incoming shifts to open without delay.
2. **`InventoryEngine` & Mandi Calculations**:
   - Verify unit conversion multipliers from traditional units (Mann, Darjan, Peti) into metric recipe units.
   - Verify kitchen wastage cost computations and stock updates.
3. **`HardwareDeviceAdapter` Byte Stream Tests**:
   - Assert standard 80mm ESC/POS byte formatting for receipts and KOTs.
   - Assert inclusion of large bold token headers on KOTs and suppression of prices.
   - Assert presence of `GS V 0` cut commands and `ESC p` cash drawer pulse bytes.
4. **`ExcelReportingEngine` Export Verification**:
   - Verify that generated `.xlsx` workbooks contain all 6 sheets with matching sums and valid ISO datetime formatting.

## Out of Scope
1. Multi-terminal local network synchronization or client-server database clustering (strictly single standalone PC in V1).
2. Kitchen Display System (KDS) tablets or mobile ordering terminals.
3. Wall-mounted HDMI Customer Facing Display (CFD) / Token TV screen (deferred to future roadmap).
4. Customer smartphone QR status tracking via in-store Wi-Fi or public cloud servers (deferred to future roadmap).
5. Integrated electronic card reader pinpads or automated Raast banking APIs (unintegrated manual tender recording only).
6. Online web ordering, third-party food delivery aggregators (Foodpanda, UberEats), or customer loyalty mobile apps.

## Further Notes
- **Target OS**: Windows 10 and Windows 11 (64-bit).
- **Recommended Hardware**: Any standard Intel Core i3 / AMD Ryzen 3 laptop or desktop with 4GB+ RAM, 80mm USB Thermal Receipt Printer with auto-cutter, and standard RJ11 24V Cash Drawer.
- **Data Durability**: Dual-target automated backups generated on every Z-Report closure guarantee zero data loss in the event of local operating system corruption or hardware failure.
