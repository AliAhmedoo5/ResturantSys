**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 16 — Logical Drift/SQLite data model and constraints

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


This document defines domain schema boundaries, not a pasted finished SQL migration. Every table requires appropriate `created_at_utc`, `updated_at_utc` (mutable masters only), `created_by`, immutable primary ID, and migration/version handling as relevant. Use foreign keys, unique indexes and CHECK constraints. **All posted events must be append-only.** Actual SQL types should be finalized with a testable migration plan.

## Identity, security and system

| Entity / table | Important fields / constraints |
|---|---|
| `departments` | id, name unique among active, active, sort_order |
| `staff` | id, code UNIQUE, name, contact, department_id FK, pay_scheme, active, archived_at |
| `credentials` | id, staff_id FK UNIQUE, role enum, PIN_verifier_hash, PIN_salt, PIN_fingerprint UNIQUE active, enabled, last_rotated, failed_count, blocked_until; **no raw PIN** |
| `session_events` | id, staff_id, opened/locked/expired, terminal_id, time, reason |
| `permission_grants` | role/capability/scope, granted_by, effective timestamps; reserved manager policies enforced in code |
| `setting_definitions`, `setting_values`, `setting_change_events` | stable key/type/scope, revision, actor, old/new sanitized value, timestamp |
| `shortcut_profiles`, `shortcut_bindings`, `quick_action_layouts` | profile, role/context/action/key, revision, conflict index, active |
| `audit_events` | id, entity, entity_id, event_type, actor, approver, reason, immutable before/after hash/approved safe metadata, UTC, business_day_id |
| `idempotency_commands` | intent_key UNIQUE, kind, request_hash, result_entity_id, result_status, created_at |
| `backup_history` | id, file path, checksum, db_version, verified_at, result, error metadata |

## Day, shift and drawer

| Entity | Fields / constraints |
|---|---|
| `business_days` | id, business_date UNIQUE for restaurant, status, token_seq, open/close actors/times, close_version |
| `cash_drawers` | id, label, active, location |
| `shifts` | id, business_day_id, cashier_id, drawer_id, open/close time, opening_float_paisa, count_state, expected, submitted_total, review_state; one active shift per drawer |
| `cash_counts`, `cash_count_denominations` | shift_id, attempt number, actor, currency denomination, count, submitted_at, original immutable count |
| `cash_movements` | id, shift_id, direction, amount_paisa (>0), source_type, source_id UNIQUE scoped, actor, approved_by, reason, idempotency_key UNIQUE |
| `shift_discrepancy_reviews` | shift/count, calculated variance, threshold, reviewer/status/action, append-only |

## Catalog and configuration

| Entity | Fields / constraints |
|---|---|
| `menu_categories` | id, code/name, parent? sort, active |
| `menu_items`, `menu_item_revisions` | code, category_id, name, price_paisa, tax_code, active, revision/effective period; historical snapshot preserved |
| `variants`, `modifier_groups`, `modifier_options` | required/min/max, price delta, usage/selection constraints, active |
| `deals`, `deal_revisions`, `deal_groups`, `deal_choice_items` | code/price/eligibility, group min/max, included item/quantity/upgrade price; no cycles |
| `recipe_versions`, `recipe_ingredients`, `modifier_recipe_deltas` | menu/deal recipe revision, ingredient ID, decimal amount and base unit, effective period |
| `packaging_rules`, `packaging_rule_items` | mode/item/category/deal applicability, packaging stock item, qty, active/effective revision |
| `discount_presets`, `discount_rules`, `discount_changes` | %/flat value, dates, mode/category/deal, min/max, stacking, role, approval and audit |

## Customers, orders, tender and refunds

| Entity | Fields / constraints |
|---|---|
| `customers`, `customer_phone_numbers`, `customer_addresses` | customer, normalized_phone indexed, address version/default; avoid global UNIQUE if shared number policy allows and handle conflict explicitly |
| `order_drafts`, `draft_lines` | staff/session, draft_revision, hold_status, customer/address context, options, created/updated/expiry; no token |
| `orders` | id, `(business_day_id, token_number)` UNIQUE, staff, customer snapshot/mode, address snapshot, status projection, money snapshot total, idempotency key UNIQUE |
| `order_lines`, `order_line_components`, `order_line_modifiers` | immutable item/deal/product/qty/price/tax/discount selection snapshots and recipe references |
| `order_status_events` | order_id, from, to, actor, UTC, reason, attempt_id; immutable |
| `delivery_attempts` | order, attempt number, rider/trip/time, failure_reason, result, next_attempt linkage |
| `payment_allocations` | order, method, due/received/verified amount, reference, verification state and balance snapshots; append-only events preferred |
| `refund_requests`, `refund_events`, `approval_events` | original payment/order, amount, method/status, supervisor authorization, reason, inventory disposition |
| `financial_entries` | event ID, account/category, debit_paisa, credit_paisa, source document; balanced per transaction if full double-entry module enabled |

## Delivery

| Entity | Fields / constraints |
|---|---|
| `rider_trips` | id, rider_staff_id, business_day, departed/returned times, status, receiving shift |
| `rider_trip_orders` | trip/order association, assignment/return/transfer reason, UNIQUE active assignment per order |
| `rider_cash_handovers` | trip, cashier/shift, physically received cash, time, idempotency, actor |
| `rider_settlement_allocations` | handover/event, order payment allocation, amount, shortage/overage disposition |

## Inventory and purchasing

| Entity | Fields / constraints |
|---|---|
| `stock_items` | id, code UNIQUE, name, type, base_unit, dimension, track_stock, reorder level, active |
| `unit_conversions` | id, name, dimension, factor numerator/denominator, optionally stock_item/supplier_item scope, effective revision |
| `inventory_movements` | id, stock_item, qty_decimal, type, source_type/source_id, business day, actor, unit_cost_snapshot, reversal_of, idempotency UNIQUE |
| `inventory_cost_layers` | stock item, received qty, remaining qty, cost amount, source receipt, valuation_method |
| `stock_counts`, `stock_count_lines`, `stock_count_approvals` | count reference, snapshot event sequence, counted qty, variance, approver and posted movement |
| `wastage_events` | item, quantity, cost snapshot, reason, staff, event/approval reference |
| `suppliers`, `supplier_item_links` | supplier name/contact, inventory item, supplier SKU/unit factor/last_price, link active, UNIQUE supplier+stock_item active link |
| `purchase_invoices`, `purchase_lines` | supplier, invoice ref, date/due, posted status, line unit/qty/factor/cost and receiving item snapshots; unique supplier+external reference policy |
| `supplier_ledger_entries` | supplier, opening/invoice/payment/credit/reversal, signed payable_paisa, source, UTC, actor, reversal reference |
| `supplier_payments`, `supplier_payment_allocations` | amount/source/drawer-or-bank, invoice allocation, status, source event and idempotency |

## Expenses and payroll

| Entity | Fields / constraints |
|---|---|
| `expense_categories` | id, name casefold active UNIQUE, parent, active, archived_at, label revision |
| `expenses`, `expense_postings` | category id + label snapshot, amount, payee, source account, authorizer, reason, optional receipt, reversal reference |
| `staff_pay_terms`, `salary_periods` | employee/effective date/rate, payroll period/start/end, locked state |
| `staff_ledger_entries`, `staff_advances`, `salary_payments` | employee, type (accrual/advance/repayment/payment/adjustment), signed amount, funding source, source link, reversal_of |

## Mandatory constraints and indexes

- `NOT NULL` all essential actor/entity/time/amount fields; `CHECK(amount_paisa > 0)` for absolute posted payment, amount sign explicit through type/direction.
- Unique `(business_day_id, token_number)`, `idempotency_key`, `staff.code`, `stock_item.code`; use partial indexes for active mapping names/keys where SQLite supports them.
- Foreign key on every stock/order/supplier/staff reference; do not `ON DELETE CASCADE` financial history.
- Index `orders(business_day_id,status)`, `orders(customer_id,created_at_utc)`, `phone(normalized)`, `supplier_ledger(supplier_id,time)`, `inventory_movements(stock_item_id,time)`, `cash_movements(shift_id,time)`, `staff_ledger(staff_id,period_id)`.
- Order line/deal snapshots are immutable; historical names, prices and discounts must remain meaningful if masters renamed.
- Store `reversed_entry_id` with a one-to-one constraint to prevent double reversal; corrected invoice may have explicit successor link.
- Expense categories with history are archived only. Supplier with payable/history cannot be deleted. Stock item with any movement/BOM linkage cannot be deleted.

## Migration and seeds

Seed required system enum tables and suggested starter expense categories/menu examples **only in optional onboarding templates**, never as real sales. Seed one owner during guided onboarding only. Migrations tested with existing ledger fixtures; no automatic data reset on schema update.

## Reporting artifacts, outbound delivery and recipient policy (extension)

```text
report_runs(id PK, business_day_id FK, revision, report_kind, status,
  snapshot_cutoff_utc, report_hash, generated_by_staff_id, generated_at_utc,
  UNIQUE(business_day_id, revision, report_kind))
report_artifacts(id PK, report_run_id FK, format ENUM(PDF,XLSX,CSV),
  protected_path, file_sha256, bytes, created_at_utc)
report_recipients(id PK, channel ENUM(EMAIL,WHATSAPP), address_ciphertext,
  display_mask, verified_at_utc, consent_record, active, created_by_staff_id)
report_delivery_policies(id PK, channel, auto_after_close, attach_pdf,
  attach_xlsx, attach_csv, allowed_report_scope, delegated_roles,
  max_retry_attempts, backoff_profile, updated_by_staff_id)
report_delivery_jobs(id PK, report_run_id FK, recipient_id FK,
  channel, purpose, idempotency_key UNIQUE, state, requested_by_staff_id,
  queued_at_utc, next_attempt_utc, attempts_count, lease_owner, lease_until_utc)
report_delivery_attempts(id PK, job_id FK, attempted_at_utc,
  provider_request_id, provider_message_id, status, sanitized_error)
report_delivery_events(id PK, job_id FK, provider_event_id UNIQUE NULLABLE,
  state, received_at_utc, happened_at_utc)
```

Encrypt addresses/credentials and generated sensitive artifacts according to approved protection design. Do not store raw email API keys or WhatsApp tokens in tables by default. Keep recipient references stable for queued jobs; approve changed destination as a new job rather than mutating previously queued history. See `25`.


## v6 REQUIRED migration additions

Implement physical `order_revisions` and `order_revision_lines` tables, including FK to original order, monotonic revision/version, actor, reason, snapshots, amount deltas, stock disposition, and unique idempotency; see full SQL draft in Chapter 32. Set **`cash_movements.approved_by` NULLABLE** in SQLite and Drift schema. Routine cashier pay-in/out never requests manager PIN and uses NULL approver; event actor/reason remain mandatory. Add `cash_rounding_paisa INTEGER NOT NULL DEFAULT 0` to posted settlement documents or order tender finalization and `tax_pricing`, `tax_rate_bps`, `tax_code` configuration. Add persisted `orders.current_revision`, reader-lock linked to rider `Settled` event, modifier selection mode/conflict rules, and serial daily token sequence. Apply as tested migrations from existing v5 schemas.


## v7 — schema extensions (migration required)

- `delivery_areas(id PRIMARY KEY, name NOT NULL, code UNIQUE NULL, description NULL, active NOT NULL DEFAULT 1, serviceable NOT NULL DEFAULT 1, delivery_fee_paisa INTEGER NOT NULL CHECK(delivery_fee_paisa>=0), min_order_paisa INTEGER NULL CHECK(min_order_paisa>=0), target_eta_minutes INTEGER NULL, sort_order INTEGER NOT NULL DEFAULT 0, deleted_at NULL, created_at, updated_at, created_by, updated_by)`. Use stable primary key; validate uniqueness of normalized active area names.
- `delivery_area_availability_rules(id, area_id REFERENCES delivery_areas(id), weekday INTEGER, open_minute INTEGER, close_minute INTEGER, enabled INTEGER)` optional configured scheduling; no schedule means active all day.
- `customer_addresses(id, customer_id, area_id NULL REFERENCES delivery_areas(id), street_address, house_building, landmark, instructions, is_default, created_at, updated_at)` if not present in v6. Validate nullable historical area relationships.
- `orders` includes `customer_id NULL`, `delivery_area_id NULL`, `delivery_area_name_snapshot`, `delivery_address_snapshot`, `delivery_fee_paisa INTEGER NOT NULL DEFAULT 0`, and immutable order/revision address snapshots. Final commit validates area availability in the same serialized write transaction and captures effective fee. Never trust UI amounts.
- `catalog_images(id PRIMARY KEY, entity_type NOT NULL CHECK(entity_type IN ('menu_item','deal')), entity_id NOT NULL, relative_original_path NOT NULL, relative_thumbnail_path, content_type, byte_count, sha256_checksum, width_px, height_px, sort_order, is_primary, alt_text, created_at, created_by, deleted_at NULL)`. Enforce at most one active primary image per entity via partial unique index; validate references in service layer or separate join tables if strict foreign keys are preferred.
- `media_cleanup_jobs(id, catalog_image_id, relative_path, action, state, attempts, created_at)` for cleanup/retry after DB commit; media files are application-managed local resources.
- Add indexes on active delivery_areas, normalized customer phone lookup, customer_addresses.customer_id and catalog_images(entity_type, entity_id, deleted_at, sort_order).
- Migrations must preserve old orders even when an area or photo is archived; null-snapshot migrations must use safe defaults and must never reprice old orders. Follow exact units (paisa, not rupees), UTC timestamps, and existing drift migration/version controls.
