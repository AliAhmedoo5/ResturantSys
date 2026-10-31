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
A customer-facing digital summary detailing ordered items, applied taxes, discounts, delivery fees, and payment tenders. Physical printing is outside the business workflow.
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

**Moving Weighted Average Cost (Moving WAC)**:
The perpetual inventory valuation methodology that recomputes an ingredient's average unit cost in integer paisa upon each inbound purchase receipt using the weighted formula $\frac{(Q_{\text{current}} \times \bar{C}_{\text{old}}) + (Q_{\text{purchase}} \times C_{\text{purchase}})}{Q_{\text{current}} + Q_{\text{purchase}}}$, eliminating FIFO batch fragmentation.
_Avoid_: FIFO valuation, average cost estimate, periodic WAC

**Perpetual Negative Stock**:
An inventory state where on-hand quantity drops below zero due to continuous cashier checkout and real-time BOM consumption prior to the entry of physical purchase invoices.
_Avoid_: Stock deficit, unbilled negative balance, stockout breach

**Pegged Last Known Cost**:
The valuation rule holding an ingredient's unit cost constant at its last verified valid purchase rate while on-hand quantity remains negative, ensuring valuation consistency until new invoice reconciliation.
_Avoid_: Estimated fallback rate, zero-cost fallback, arbitrary cost peg

**Negative Balance Valuation Badge**:
An explicit report and UI transparency indicator (`Estimated valuation: item in temporary negative balance`) alerting managers that an inventory line's asset value is reported as PKR 0.00 while awaiting supplier invoice entry.
_Avoid_: Negative asset warning, stock error flag, inventory deficit alert

**Mandi Unit Conversion Snapshot**:
The immutable conversion multiplier and base unit permanently recorded on a purchase invoice row at entry time (e.g., 1 Mann = 40 kg = 40,000 g), guaranteeing that future unit configuration changes never distort historical stock quantities or valuation.
_Avoid_: Unit configuration link, live unit factor, dynamic conversion

**Acquisition-Rate Sales COGS**:
The immutable cost of goods sold snapshotted into order items (`bom_json`) at the time of sale based on event-time ingredient acquisition rates, strictly decoupled from subsequent inventory valuation fluctuations.
_Avoid_: Revalued COGS, replacement food cost, retroactive COGS

**Inventory Quantity Bridge**:
The mathematical reconciliation verifying that ending inventory at any historical cutoff equals opening stock plus purchases minus sales BOM consumption, packaging, kitchen wastage, and physical adjustments.
_Avoid_: Stock reconciliation formula, inventory equation, stock balance proof

**Unknown Cost Quality**:
An explicit metadata classification (`CostQuality.unknownCost`) assigned to inventory lines lacking purchase cost evidence in early operational history, preventing silent zero-cost assumptions and enabling honest coverage disclosure.
_Avoid_: Missing cost flag, zero cost fallback, uncosted inventory

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
A single sellable catalog item backed by a mandatory Bill of Materials recipe and one optional photograph.
_Avoid_: Product, dish, catalog item

**Deal**:
A bundled promotion containing multiple menu items and customer-selected options, where every selectable option has a verified recipe, with one optional photograph for the promotion.
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
The immutable time at which an action was recorded, retained with its original UTC or offset evidence and displayed in Asia/Karachi. Naive legacy values carry a disclosed Asia/Karachi assumption; they are not proof of the actual event time.
_Avoid_: System time, clock stamp

**Event Time**:
The time at which the recorded activity actually occurred, distinct from its Audit Timestamp when entry was delayed. Unknown historical Event Times remain unknown.
_Avoid_: Entry time, posting time (when referring to actual occurrence)

**Manager Portal**:
The back-office administrative section of the application protected by a Manager PIN for catalog CRUD, recipes, Khata, staff PINs, settings, and reporting.
_Avoid_: Admin panel, backend, supervisor portal


**Line-Level Sales Allocation**:
The proportional distribution of order-level discounts and carve-out taxes to individual order items in integer paisa, ensuring exact reconciliation to order receipts without altering sealed historical records.
_Avoid_: Item discount guess, revenue slice

**Rounding Residual**:
The remaining integer paisa produced when allocating an order discount or tax via floor division, distributed deterministically to the highest-value lines to ensure zero paisa leakage.
_Avoid_: Fractional paisa loss, rounding error

**Deal Component Expansion**:
The proportional distribution of a deal or combo selling price across its constituent items based on their standalone menu prices, enabling item-level contribution margins and recipe food cost analysis.
_Avoid_: Combo decomposition, package unbundling

**Line Contribution Margin**:
Net sales allocated to an order line item minus its snapshotted recipe BOM food cost, measuring item profitability in integer paisa.
_Avoid_: Item gross margin, food profit

**Allocated Discount**:
The portion of an order discount assigned to a specific item line using integer paisa proportional allocation.
_Avoid_: Item discount, line reduction

**Unallocated Legacy Order**:
A closed historical order created before line-level allocation ledgers were introduced, presented in reports with honest missing-allocation disclosure rather than fabricated line splits.
_Avoid_: Incomplete order, corrupted order

## Kitchen & Delivery Fulfillment

**Preparation Duration (Prep Time)**:
The elapsed duration from order confirmation ($T_{\text{confirmed}}$) to the initial kitchen milestone marked READY ($T_{\text{ready}}$), summarized via median (p50) and 90th percentile (p90) rather than simple arithmetic means.
_Avoid_: Cooking speed, kitchen latency, average prep time

**Rework Cycle**:
An append-only kitchen transition moving an order back from READY to PREPARING (and back to READY) for remakes, heat-lamp warming, or customer changes without overwriting the primary READY milestone timestamp.
_Avoid_: Prep reset, kitchen retry, remake overwrite

**Milestone Sample Coverage**:
The ratio of eligible orders possessing observed, non-null milestone timestamps divided by total orders in the period, ensuring missing taps are disclosed with sample counts rather than synthesized as zero minutes.
_Avoid_: Milestone completeness, timer uptime, tap score

**Rider Travel Time**:
The transit duration measured from courier trip departure ($T_{\text{dispatched}}$) to delivery completion ($T_{\text{delivered}}$) recorded at the doorstep or upon counter return.
_Avoid_: Trip length, ride duration, delivery transit

**Delivery Area Target ETA**:
The manager-configured expected fulfillment duration in minutes assigned to a specific delivery area (also referred to as Area Target ETA), used as the benchmark for evaluating on-time delivery performance.
_Avoid_: Zone Target ETA, area deadline, zone SLA, standard delay

**Delivery SLA**:
The service level threshold evaluated against the Delivery Area Target ETA (or a 45-minute fallback from confirmation) to classify orders as on-time or late.
_Avoid_: Delivery commitment, dropoff guarantee, speed quota

**Reattempted Delivery**:
A subsequent courier delivery dispatch following a returned, incomplete trip attempt (e.g. unreachable customer or gated address), tracked distinctly without counting as an order failure.
_Avoid_: Delivery failure (for temporary return), second trip, retry penalty

**Final Delivery Failure**:
A terminal fulfillment failure reached when an order is explicitly canceled before delivery (`CANCELLED_UNDELIVERED`) or returned with food written off to kitchen wastage (`RETURNED_WASTED`).
_Avoid_: Returned run, failed attempt, courier bounce

**Unsettled COD Aging Clock**:
The operational duration counter tracking uncollected Cash on Delivery funds beginning at courier trip return ($T_{\text{trip\_return}}$) at the counter, rather than from order creation.
_Avoid_: COD age, cash delay, driver debt timer

**Aging Bands**:
The operational classification of unsettled COD exposure categorizing pending collections into Current Shift, Overdue / Unsettled (0–24h), Aged (1–3 days), and Critical (>3 days).
_Avoid_: Overdue buckets, debt stages, aging brackets

