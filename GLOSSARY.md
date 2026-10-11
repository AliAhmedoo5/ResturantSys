# Fast-Food POS & Operations System

An offline-first standalone desktop point-of-sale and kitchen inventory operations system for fast-food restaurants.

## Operations & Ordering

**Business Day**:
An operational accounting period opened and closed by staff, during which daily tokens increment and shifts occur.
_Avoid_: Calendar day, working date

**Shift**:
A continuous work session by a designated cashier operating the cash drawer with an opening float.
_Avoid_: Turn, work slot

**Token**:
A daily auto-incrementing pickup identifier (#01, #02...) reset at the start of each Business Day.
_Avoid_: Queue number, ticket number, order index

**Order**:
A finalized commercial transaction containing menu items, deals, modifiers, and payment tender.
_Avoid_: Transaction, bill, cart

**Receipt**:
A customer-facing tax slip detailing ordered items, applied taxes, discounts, and payment tender.
_Avoid_: Bill, tax invoice slip, customer check

**Kitchen Order Ticket (KOT)**:
A production slip routed to kitchen stations detailing token number, dining type, and item modifiers without prices.
_Avoid_: Kitchen slip, food chit, cook ticket

**Dining Type**:
The fulfillment channel for an order (Dine-In, Takeaway, or Delivery), driving packaging BOM deductions and kitchen routing.
_Avoid_: Service style, dining mode, order category

**Token Queue**:
A lightweight on-screen status board tracking active tokens through fulfillment states (Preparing, Ready, Delivered).
_Avoid_: Order tracker, kitchen monitor, dispatch queue

**Split Tender**:
A payment transaction settled across multiple distinct payment methods (such as partial cash and partial Raast QR).
_Avoid_: Multi-pay, mixed payment, partial settlement

**Pre-Approved Discount**:
A management-configured promotional reduction that a cashier can select during checkout without requiring a supervisor PIN.
_Avoid_: Cashier discount, custom concession, manual promo

**Void**:
A supervisor-authorized cancellation of a settled order, logging the cashier ID, supervisor PIN, reason, and reversing inventory deductions.
_Avoid_: Delete order, cancellation, wipe

**Feature Toggle**:
A supervisor-level operational switch that enables or disables specific POS workflows (such as the Token Tray or Cashier Void Requests).
_Avoid_: System flag, operational parameter, soft config

## Inventory & Menu Catalog

**Raw Ingredient**:
A bulk kitchen stock element tracked by count, weight (g/kg), or volume (ml/l).
_Avoid_: Stock item, raw material, supply unit

**Desi Unit**:
A localized traditional wholesale packaging unit (such as Mann [40kg], Darjan [dozen], Peti [crate], or Bori [sack]) mapped to metric stock balances.
_Avoid_: Informal measure, market unit

**Vendor Khata**:
A localized supplier ledger tracking credit purchases, delivery slips, and balance settlements for raw ingredient deliveries.
_Avoid_: Supplier debt, accounts payable ledger, vendor balance

**Menu Item**:
A single sellable catalog item backed by a Bill of Materials recipe.
_Avoid_: Product, dish, catalog item

**Deal**:
A bundled promotion containing multiple menu items and customer-selected options sold at a package price.
_Avoid_: Combo, set meal, bundle

**Bill of Materials (BOM)**:
The defined list of raw ingredients consumed when preparing a menu item or modifier.
_Avoid_: Recipe formula, component list

**Kitchen Wastage**:
Raw ingredients or prepared items discarded due to burning, dropping, or expiration, logged separately from sales.
_Avoid_: Spoilage, shrinkage, scrap

## Cash & Shift Control

**Opening Float**:
The baseline physical cash placed in the cash drawer at shift start to provide change.
_Avoid_: Base cash, drawer seed, petty cash

**Cash Movement**:
A manual inflow (Pay-In) or outflow (Pay-Out / Petty Cash / Cash Drop) logged against the active cash drawer during a shift.
_Avoid_: Drawer transaction, petty voucher, cash adjustment

**X-Report**:
An interim shift reconciliation report generated during cashier handover after a blind count without closing the Business Day.
_Avoid_: Shift slip, cashier audit, midway report

**Z-Report**:
The end-of-day financial settlement report generated after a blind cash drawer count that locks the business day.
_Avoid_: Day close report, cashout slip

**Discrepancy**:
The mathematical variance between physical cash counted during shift handover and expected cash calculated by the system.
_Avoid_: Shortage/overage, drawer variance, error

**Discrepancy Flag**:
An unresolved discrepancy status attached to a closed shift exceeding the supervisor threshold, logged for management review without blocking counter operations.
_Avoid_: Shift hold, lock error, cash penalty

**Audit Timestamp**:
The unalterable local date and time (YYYY-MM-DD HH:MM:SS) permanently recorded on every database transaction, cash movement, void, and inventory log.
_Avoid_: System time, clock stamp

**Department**:
A supervisor-defined organizational unit (such as Front Counter, Kitchen, Management, or Delivery) grouping staff members and their operational access rights.
_Avoid_: Staff group, team tier, role bucket

**Supervisor Portal**:
The back-office administrative section of the application protected by a Supervisor/Owner PIN for catalog CRUD, Khata, settings, and reporting.
_Avoid_: Admin panel, backend, control room
