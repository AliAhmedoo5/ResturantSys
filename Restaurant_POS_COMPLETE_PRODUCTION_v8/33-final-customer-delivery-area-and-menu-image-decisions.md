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
