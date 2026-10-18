# Fast-Food POS & Operations System

An offline-first standalone desktop point-of-sale and kitchen inventory operations system for fast-food restaurants.

## Roles & Access

**Cashier**:
The front-counter operator authorized exclusively to create carts, input customer details, record manual payments, issue tokens, and revise or cancel confirmed orders.
_Avoid_: Counter clerk, operator, teller

**Manager**:
The unified administrative role (encompassing Supervisor and Owner) authorized to manage catalog, recipes, stock, suppliers, staff PINs, settings, and business day closures, but strictly prohibited from operating cashier billing.
_Avoid_: Admin, supervisor (as a distinct tier), owner (as a distinct tier)

**Onboarding Wizard**:
A mandatory first-run setup sequence provisioning restaurant identity, a Manager profile, and a primary Cashier profile before counter operations can begin.
_Avoid_: Setup screen, initial form, admin wizard

## Operations & Ordering

**Business Day**:
An operational accounting period opened and closed by a Manager, during which daily tokens increment and cashier shifts occur.
_Avoid_: Calendar day, working date

**Shift**:
A continuous work session by a designated cashier operating the cash drawer with an opening float and closing blind count.
_Avoid_: Turn, work slot

**Token**:
An immutable, daily auto-incrementing pickup identifier (#01, #02...) allocated atomically upon final order confirmation and never recycled.
_Avoid_: Queue number, ticket number, order index

**Token Burning**:
The permanent retirement of a daily token upon order confirmation, ensuring canceled or revised order numbers are never recycled or reassigned.
_Avoid_: Token gap, queue skip, order reuse

**Order**:
A finalized commercial transaction containing menu items, deals, modifiers, customer delivery details, and payment tender.
_Avoid_: Transaction, bill, cart

**Collection Due**:
The uncollected payment state of a confirmed or delivered Cash on Delivery order prior to cashier rider trip settlement.
_Avoid_: Pending COD, unpaid bill, rider debit

**Order Revision**:
An append-only modification or cancellation of a confirmed order executed by the Cashier without a Manager PIN, capturing reason, price deltas, and stock disposition.
_Avoid_: Order void, order wipe, silent cancellation

**Stock Disposition**:
An auditable classification (raw return vs cooked wastage) assigned to removed items during an order revision, determining whether ingredients return to stock.
_Avoid_: Ingredient return, scrap toggle, food restock

**Settled Trip Lock**:
An unalterable boundary triggered upon rider trip settlement, permanently locking all contained orders from direct line edits or cancellations.
_Avoid_: Order freeze, delivery lock, dispatch closure

**Hold**:
A temporary, unconfirmed cart snapshot saved locally for later recall before token allocation or payment collection.
_Avoid_: Draft order, parked sale, paused bill

**Receipt**:
A customer-facing summary slip detailing ordered items, applied taxes, discounts, delivery fees, and payment tenders.
_Avoid_: Bill, tax invoice slip, customer check

**Dining Type**:
The fulfillment channel for an order (Dine-In, Takeaway, or Delivery), driving packaging BOM deductions and delivery area requirements.
_Avoid_: Service style, dining mode, order category

**Delivery Area**:
A manager-configured geographical zone with an associated fixed delivery fee that must be selected for all delivery orders.
_Avoid_: Delivery sector, delivery zone, postal zone

**Split Tender**:
A payment transaction settled across multiple distinct payment methods (such as partial cash and partial Raast/wallet).
_Avoid_: Multi-pay, mixed payment, partial settlement

**Manual Tender**:
A payment method (Cash, JazzCash, Easypaisa, Bank Transfer/Raast, Card, COD) recorded manually by the Cashier without external payment gateway APIs.
_Avoid_: Payment gateway, API tender, verified payment

**Pre-Approved Discount**:
A management-configured promotional reduction that a cashier can select during checkout without requiring a supervisor PIN.
_Avoid_: Cashier discount, custom concession, manual promo

**Integer Paisa**:
The signed 64-bit integer monetary unit (1 Rupee = 100 paisa) used for all currency storage and exact mathematical calculations.
_Avoid_: Floating-point price, decimal rupees

**Cash Rounding**:
The mathematical half-up rounding of the physical cash payable to the nearest whole rupee (100 paisa), with the delta tracked in a rounding variance ledger.
_Avoid_: Bill rounding, discount rounding, change truncation

**Tax Carve-Out**:
The internal calculation of sales tax included within a shelf price without increasing the customer's checkout total.
_Avoid_: Tax addition, checkout markup, sales surcharge

## Inventory & Menu Catalog

**Raw Ingredient**:
A bulk kitchen stock element tracked by count, weight (g/kg), or volume (ml/l).
_Avoid_: Stock item, raw material, supply unit

**Bill of Materials (BOM)**:
The defined list of raw ingredients and packaging consumed when preparing a menu item, deal component, or modifier.
_Avoid_: Recipe formula, component list

**Recipe Gate**:
The mandatory system validation ensuring a Menu Item or Deal cannot be published or sold without a complete, verified Bill of Materials.
_Avoid_: Stock check, recipe lock, publish block

**Perpetual Stock**:
An inventory ledger policy where ingredient and packaging consumption is posted immediately at checkout and sales are never blocked by zero or negative stock.
_Avoid_: Stock bypass, negative override, unconstrained inventory

**Desi Unit**:
A localized traditional wholesale packaging unit (such as Mann [40kg], Darjan [dozen], Peti [crate], or Bori [sack]) mapped to metric stock balances.
_Avoid_: Informal measure, market unit

**Vendor Khata**:
A localized supplier ledger tracking credit purchases, delivery slips, and balance settlements for raw ingredient deliveries.
_Avoid_: Supplier debt, accounts payable ledger, vendor balance

**Payment Source**:
The designated financial origin (active shift drawer cash vs external management funds) used when settling supplier Khata or issuing staff advances.
_Avoid_: Cash bucket, money origin, fund type

**Menu Item**:
A single sellable catalog item backed by a mandatory Bill of Materials recipe and optional photograph gallery.
_Avoid_: Product, dish, catalog item

**Deal**:
A bundled promotion containing multiple menu items and customer-selected options, where every selectable option has a verified recipe.
_Avoid_: Combo, set meal, bundle

**Kitchen Wastage**:
Raw ingredients or prepared food discarded due to burning, dropping, or expiration, logged with reason and financial loss.
_Avoid_: Spoilage, shrinkage, scrap

## Cash & Shift Control

**Opening Float**:
The baseline physical cash placed in the cash drawer at shift start to provide change.
_Avoid_: Base cash, drawer seed, petty cash

**Cash Movement**:
A manual inflow (Pay-In) or outflow (Pay-Out / Petty Cash / Cash Drop) logged against the active cash drawer during a shift without requiring routine manager approval.
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

**Blind Count**:
A shift-closing cash count performed by the cashier without visibility into system-expected drawer balances.
_Avoid_: Secret count, hidden total, blind audit

**Offline Outbox**:
A local durable queue storing end-of-day reports with retry schedules, ensuring business day close succeeds without internet connectivity.
_Avoid_: Send cache, email queue, sync queue

**Audit Timestamp**:
The unalterable local date and time permanently recorded on every database transaction, cash movement, revision, and inventory log.
_Avoid_: System time, clock stamp

**Manager Portal**:
The back-office administrative section of the application protected by a Manager PIN for catalog CRUD, recipes, Khata, staff PINs, settings, and reporting.
_Avoid_: Admin panel, backend, supervisor portal
