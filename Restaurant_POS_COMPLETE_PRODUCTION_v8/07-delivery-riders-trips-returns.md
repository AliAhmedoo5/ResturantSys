**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 07 — Delivery lifecycle, rider trips, failed/returned orders, cash settlement

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Order fulfillment [DEL-01…10]

Delivery statuses use explicit timestamps and actor IDs: Confirmed → Preparing → Ready → Out for Delivery → Delivered. Exception branches: Failed Attempt, Returned, Redelivery Requested, Cancelled. Status changes must be valid for prior status and not silently alter payment. Cashier updates kitchen/prep milestones manually; kitchen is close and there is **no KOT or kitchen queue**.

Order detail: token, customer phone masked by role where appropriate, delivery area/address/landmark, items/notes, amount, discount, fees, paid/unpaid, rider assignment, timestamps, reason history and status-changing actions. Pending ready orders may be dispatched by cashier/supervisor. Assigning rider and dispatch is an explicit recorded event.

## Rider master and trips [RIDE-01…12]

Rider can be a staff record with delivery role, active/inactive state and optional contact. Trip record has ID, rider, start/return times, business day, assigned orders (possibly multiple), cash expected by actual tender/payment channel, total COD amount, cash received, settlement state, creator/receiver actors and notes. Prevent same active order being assigned to overlapping active trips without recorded transfer. Support reassign with reason.

**Cash expected ≠ gross trip sales.** Already-prepaid card/bank orders do not add cash expected. COD amount may be adjusted by refund/partial-collection events; compute from order receivables, not a fixed copied total without reconciliation.

### Trip settlement

1. Display trip manifest with per-order payment status and expected cash to collect.
2. Mark trip Returned; enter actual collected by order where possible (supports customer partial payment), then enter **physical cash handed over**.
3. Compare **expected rider remittance** vs received cash; show shortage/overage and mandatory explanation. Do not treat rider cash as drawer cash until accepted handover transaction.
4. Source drawer/shift specified for handover; post one cash pay-in and rider settlement allocation atomically.
5. Partial settlements allowed with remaining rider receivable. Supervisor can resolve variance with approved adjustment; never mark shortage "paid" merely because order delivered.
6. Cashier may start next trip while prior shortage remains if configured; unresolved liabilities remain reported.

## Failed/returned delivery [FAIL-01…09]

Capture failure reason list (customer unavailable, invalid address, refused, rider issue, other), optional detailed note, attempt timestamp and rider ID. Distinguish:

- **Redeliver same prepared food:** policy must validate safe/time limit; record new attempt and rider/trip; do not deduct recipe again.
- **Remake replacement:** creates new consumption/wastage trail for previous batch and production of replacement; cost separately.
- **Return usable sealed inventory:** selective supervised stock return of unopened products only; never auto-return cooked ingredients.
- **Customer refund/partial refund:** separate payment reversal with tender/source, approval and cash effect.
- **Mark loss/wastage:** inventory cost loss is recognized without fake receipt.

No GPS, photo, OTP, automated courier integrations or rider app required at launch.

## Exceptions

COD order Delivered but rider unpaid; rider collected less than order amount; rider's trip has card-paid order; two trip handovers in separate cashier shifts; over-collection/change owed; duplicate delivery status clicks; returned order after day close; redelivery on next business day; customer refuses meal already cooked. Explicit lineage prevents double sales and ingredient deduction.

## Reporting and acceptance

Track fulfillment duration from timestamps, not UI clocks; median/p90 preparation and delivery time, area efficiency, rider trip counts, failed delivery rates and reasons, aging COD/rider receivables, settlement discrepancies. Tests: delivery/paid independent; multiple trips; cash expected excludes prepaid; physically handed cash posts once; partial settlement; failure reattempt no automatic restock or refund; cross-day settlement linked to original order and receiving shift.


## v7 — Manager-managed delivery service areas

Manager (Supervisor/Owner same role) has full CRUD for **delivery areas/zones**, including display name, optional code, description/coverage notes, active/serviceable flag, delivery fee in integer paisa, optional minimum basket, target ETA, priority/sort and optional availability schedule. Zones can be temporarily unavailable without deletion; historical orders keep immutable area name, fee and ETA snapshot. Used zones must be archived/deactivated rather than hard-deleted. Area eligibility is validated at final order save as well as UI selection (protect against a Manager disabling zone while Cashier is entering order). Only serviceable currently-enabled zones are selectable for *new* deliveries, with a clear unavailable response and alternative takeaway option. Managers may add/edit zones; cashiers only select them and read eligibility. Do not infer availability from maps/geocoding; serviceability comes from Manager setup. No external map API required.

Delivery fee comes from the **selected zone's configured fee**, captured on the order and included in total before payment. If order area is changed after confirmation but before trip settlement, recompute fee with audited revision and any payment difference under v6 amendment rules. After rider trip settlement, keep cart locked and use documented adjustment/refund mechanism.
