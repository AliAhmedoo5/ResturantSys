**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 26 — Complete feature catalog, user handbook and cross-module behavior

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


**Audience:** restaurant owner, shift supervisor, cashier, implementation agent and QA. This chapter is the functional acceptance map, backed by detailed requirements in chapters `00–25`. It does not supersede accounting rules. **Confirmed** means requested; **Provisional** means configurable/needs owner agreement; **Future** is excluded from launch.

## A. Application foundation and operation [CORE]

**Capabilities:** Native Windows app, offline-first local persistent database, PIN login, staff session, business-day clock, shift cash session, automatic migrations, backup/restore, role-controlled navigation, searchable lists, audit and exception reporting. UI in English with local business terminology (`Khata`, `Mandi`); timezone display Asia/Karachi. Operates without internet for sales, stock, payouts and reports. Network needed only for actual email/WhatsApp sending. No browser tab or cloud sign-in required to bill.

Manager (Supervisor/Owner) is the only management role, with identical permissions for both titles; Manager can administer and approve but cannot perform cashier tasks. See chapters 01 and 24.

**End of day:** Confirm all shifts accounted for and pending delivery/rider balances surfaced, review refunds, cash and inventory exceptions, submit supervisor-approved Z report, lock day, generate PDF/XLSX, back up, queue email/WhatsApp if enabled. Next day's token sequence starts from configured daily boundary.

**System status:** Header displays authenticated staff, business day, shift, local time, offline/network state and blocking errors. A short alert must never erase user input. Background report-sending errors never interrupt billing.

## B. Staff, departments, account access and payroll [STAFF]

**Staff creation:** Manager enters full name, optional employee code/contact, department/job, employment status, monthly salary or wage basis, commencement date and POS role. Employee may have no login. If role Cashier/Manager, a unique 4–8 digit PIN is created/confirmed; Manager account may only be created/elevated by Owner. Hash PIN, unique keyed lookup, lockout/cooldown and audit. Every account has an explicit role independent of department.

**Employee CRUD:** Create/view/filter/edit contact/department/salary effective date; disable/deactivate without deleting past orders and finance. PIN rotation must not reveal old PIN; role changes audited; no duplicate PIN even between cashier and supervisor. If employment ended, no new login but prior shift attribution remains intact.

**Payroll:** Period setup, salary accrual, advance issued, deductions, partial salary paid, reversals and outstanding liability. Employee balance view must separate **gross earned**, **advances recovered**, **deductions**, **salary paid**, **remaining owed**. Staff payment from drawer produces one cash outflow and one payroll allocation; bank/outside-drawer payment changes payroll liability only, not drawer. Payroll posts must never be casually edited or deleted; use reasoned corrections. Reporting includes department costs and due dates. Attendance-linked payroll optional future unless approved.

**Typical flow:** Create employee → assign optional POS role/PIN → start salary period → record advance (drawer/bank source) → accrue salary → record payroll payment → review balance/history → close period. If an advance is recovered, prevent counting it twice as both cash expense and deduction.

## C. Menu, categories, deals, discounts and recipes [MENU]

**Menu categories CRUD:** name, sort order, optional marker/icon and active flag; reorder, rename, archive. Archived category/items remain readable in historic sales. Menu product CRUD: code/SKU, name, description, category, price, tax configuration, sale status, optional image, options/modifiers, recipe and effective dates. Users may create arbitrary categories and products, not fixed video items.

**Deals/combinations:** Supervisor adds deal title/code, customer price, active dates/time, constituent products/quantities, required option groups, upgrade choices, quantity limits, display ordering and BOM decomposition. Example: Family Deal includes four burgers and two drinks with choice of drink; the cashier sees one concise choice dialog. Saving a deal validates its component mapping and total, and prevents selling invalid/inactive components based on policy. Version deal composition when sold.

**Modifiers:** Add cheese, no mayo, extra sauce etc. Each can change sale price and recipe consumption independently. Recipe BOM links ingredients to base units and precise quantities; avoid negative or ambiguous inventory calculations. Packaging BOM is separately tied to fulfillment mode and packaging version. Tax rules/rounding and delivery-fee treatment must be owner/accountant approved, not hardcoded from screenshot.

**Discounts:** Manager create active eligible presets (`5%`, `10%`, flat Rs amount, item/deal-specific, min spend, cap, date window, stackability, authorization). Active eligible presets **always visible to cashier** in the discount section. Cashier can apply only those. Expired/disabled presets hidden/clearly ineligible; cart revalidates on confirm. Store applied discount ID plus immutable details for historical reproducibility.

**CRUD rules:** Items with no references may hard-delete; referenced masters deactivate/archive, not destroy. Historic orders snapshot names/prices/deal/discount. Manager price change never retroactively alters existing held or posted orders silently—held drafts must recalculate/confirm on recall.

## D. High-speed cashier counter [POS]

**UI:** Designed for Windows display (1366×768 baseline). Category tabs plus product search; optional images; 3–5-column compact grid depending width; persistent right cart/amount panel and checkout control; minimal visual distractions and *no routine page scrolling for simple bill*. Keyboard shortcuts shown and configurable by Owner. Cart rows display quantity ±, modifiers and line price. Quick-action toolbar role aware.

**Modes:** Delivery (phone, name, address, area, landmark, rider later, delivery fee), Takeaway (phone optional), Dine-in (table 1–5, open state, guest count if configured). All use same order engine but appropriate mandatory fields and packaging rules. Tables never silently merge; combining/check splitting requires separate approved scope.

**Quote vs order:** Product selection builds ephemeral/durable draft. Discounts and taxes preview, but no stock or payment ledger posted until confirmation. Hold saves draft separately; recall opens and validates stale prices/availability/discount rules, preserving untouched draft if takeover denied. Repeating historical order clones lines into new cart at current price/eligibility after confirmation; never silently duplicates payment or stock usage.

**Tender:** Cash: received amount + change, underpayment disabled. Electronic: choose configured card, bank/Raast, Easypaisa, JazzCash and mark verified according to actual integration or cashiers' manual confirmation policy. COD: order confirmed with collection outstanding, *not cash sales yet*. Split: lines per tender sum exactly to total; refunds later allocate against tender(s). Avoid fake gateway confirmation. Support cancel/back without clearing cart. Atomic submit once; save with idempotency key to survive double-click/crash.

**When saved:** Create immutable order lines/snapshots, sequential business-day token, payment obligation/collections, fulfillment event, stock ingredient and packaging usage once, audit. On-screen success: order/token, amount, payment state and next action. Digital receipt/PDF if enabled. Kitchen verbally informed; **no KOT or kitchen station**.

**Shortcuts:** Manager maps action to key (F2 new, F3 hold, F4 recall, F5 customer, F6 discount, F7 pay etc. as examples). Prevent duplicate assignments and protected OS combinations; context-aware (e.g., do not trigger while typing), enforce role permissions on invocation, restore defaults and audit changes. Cashier cannot reassign global shortcuts.

## E. Customer records and ordering history [CRM]

Phone search normalizes local Pakistan numbers; duplicate detection with manager resolution and non-destructive merge policy. Customer has names, multiple phone entries where needed, labeled addresses, areas, landmarks, notes (avoid sensitive unnecessary detail), first/last order and order history. Ability to search by phone before bill, auto-fill address/fee policy and create repeat-order cart. Order history remains authoritative if customer name/address is later updated. Support walk-in and anonymous orders. Protect phone lists in exports. **Loyalty/rewards and automated marketing are future**.

## F. Manual preparation and order status [ORDER]

Proposed main path: Confirmed → Preparing → Ready → Out for Delivery → Delivered for delivery, and Confirmed → Preparing → Ready → Collected for takeaway. Dine-in can use Ready → Served → Completed. Each transition stores timestamp, actor and optional reason. Status buttons on Orders screen; no printer, kitchen queue, SMS or rider app. Configurable stage delay thresholds trigger in-app supervisor alerts; a delayed warning is informational and does not silently change status.

**Cancellation/void:** Before commit: remove draft. After commit: role/approval, reason, original amounts and explicit food disposition. Cooked/served stock is NOT automatically restored as fresh inventory. Refund is a separate tender movement/receivable reversal. Voided order and events remain in reports; no deleted historical row.

## G. Delivery, riders, trips and failed returns [DELIVERY]

Rider directory links employee names/contact/status; supervisor assigns available rider to an order or batch/trip. A trip has unique ID, rider, departure time, included order IDs, expected COD, handovers and close status. Avoid assigning one order simultaneously to two active trips. A rider may carry multiple orders; order status and payment state distinct.

**Out for Delivery:** dispatch timestamp and rider recorded. On delivered: mark delivery, optionally note COD collected by rider; actual drawer not increased until rider hands cash in. On return/fail: record reason (customer not available, rejected, address incorrect, rider issue, etc.), attempts, return time, inventory/packaging/food decision, payment/refund decision; allow supervised redispatch under explicit linked attempt. Never assume cooked food is saleable stock or auto-refund.

Manager (Supervisor/Owner) is the only management role, with identical permissions for both titles; Manager can administer and approve but cannot perform cashier tasks. See chapters 01 and 24.

## H. Inventory, purchasing, packaging and wastage [INVENTORY]

Inventory master CRUD supports name, code, ingredient/packaging/other type, base unit, stock threshold, cost method, reorder level, supplier associations, stockable flag and status. Supervisor can create arbitrary items inside supplier creation or inventory form. Requiring a supplier-product link is mandatory for supplier-specific purchase. Purchase dropdown filters and validates linkage. Manager can edit associations; historical deliveries reference their original supplier/item. For sold recipes, ingredient and packaging consumption posts once as a stock ledger movement.

**Stock receipts:** Source supplier, line item, quantity, unit, unit conversion, unit/extended cost, invoice/ref, partial/full payment, expected/received date. Decimal precision and dimension validation prevent unit error. Mandi units configurable (Mann, Pao, Bori, Dharri, Darjan, Peti/crate) with explicit per-item conversion; do not assume every crate contains same amount.

**Wastage:** damaged/burned/expired/spoiled food with mandatory reason, staff and estimated cost loss; create negative stock movement. Supplier returns from unsold inventory have separate credit/quantity and payable effects; cooked customer return is not automatically a stock increase.

**Physical stock count:** Freeze base snapshot or calculate movement-safe delta, count actual, show variance by item, require manager approval when threshold exceeded, post precise adjusting movement once. Include counted time, snapshot revision, counters, approver and signed results. Real-time stock warnings and reorder alerts are configurable. No requirement to block cashier at negative stock unless owner policy says so.

## I. Supplier CRUD and Khata [SUPPLIER]

**Create supplier:** name, primary phone, address(optional), contact, note, status, opening payable if approved and **supplied inventory items** (multi-select). Manager can type arbitrary new product name on the same screen, define type/unit and add to inventory master, then associate it. During purchase choose supplier first, then select only assigned items; server command validates association again. Supplier status: `No purchases` when no payable purchase; `No payments` when payable purchases exist and sum paid = zero; `Partially paid` when 0 < paid < due basis; `Paid` when purchases settled. Opening balances, debit/credit notes and repayments require derived ledger-aware status, not simple counters.

**Purchases:** partial cash/bank/credit payment; stock received + liability logged once; invoice/slip ref; reject exact duplicates or request override; due date and supplier statement. **Khata:** payable = approved opening amount + posted deliveries/charges - valid supplier returns/credits - applied payments. Show outstanding/overdue aging (0–30,31–60,61–90,90+) and chronological statement. Paying from active drawer creates exactly one drawer outflow; paying outside drawer does not affect cashier drawer. No supplier with history can be silently deleted; archive instead.

## J. Business day, expenses, cash and reconciliation [FINANCE]

**Cash movement taxonomy:** cash sale collection, opening float, expense pay-out, supplier payment from drawer, rider cash pay-in, customer refund, salary from drawer, adjustment and discretionary pay-in/pay-out (with approval). Every entry identifies source, purpose, business day/shift and reference. Do not double-count supplier/advance/expense as separate pay-outs for the same physical cash.

**Expense categories:** Manager full CRUD on category master (create/edit/rename, list, archive and delete unused). Add unlimited restaurant-specific categories (gas cylinders, electric bill, staff meal, petrol). No fixed uneditable category set. Category rename updates display without corrupting historical grouping; category deletion denied when referenced and deactivation offered.

**Expense posting:** category, amount, description, paid-to, payment source, date/business day, approval if threshold, receipt/file optional and tax/cost treatment if approved. Void/correct posted entry via reversing event; not destructive edit. Expense expense type distinct from supplier inventory purchase, payroll payment and refund for profit classification.

**Blind shift close:** cashier enters counted cash without seeing expected. `Expected drawer = opening float + actual cash collected into drawer + approved pay-ins - physical cash pay-outs - cash refunds/cash drops`; variance = counted - expected. Supervisor reviews discrepancy, signs reason, can proceed with next shift under approved nonblocking policy; outstanding rider COD never included until cash is actually handed in.

## K. Reports, owner intelligence and export [REPORT]

Filters: business day, chronological date interval, order mode, product/category/deal, cashier, shift, payment type, area, rider, supplier, ingredient, status, expense category and staff. Tables support sort/search/drill-down, chart and downloadable PDF, XLSX (multiple sheets), CSV. Report results are based on **posted ledger events and snapshots**, not an HTML approximation. Owner-level reports:

1. Executive summary: gross sales, discounts, refunds, net sales, taxes, delivery fees, order count, average order value, tenders and exceptions.
2. Sales by product/category/deal, bestseller units, margin data quality and modifier analysis.
3. Hour/day/week/period trends, peak hours, weekday mix and comparable periods with correct filters.
4. Delivery performance by area/rider/trip: accepted, preparing, dispatch, failed/returned, elapsed, lateness, cash settlement, shortages.
5. Customer mix: new/repeat, total value, repeat-order frequency, address/area penetration. Minimal necessary PII in exports.
6. Inventory consumption, packaging cost, reorder, negative stock, count variance, physical wastage, stock valuation and purchase price trends.
7. Supplier Khata: invoices, aging, overdue credit, spending, partial payments, returns and procurement cost.
8. Drawer and shifts: floats, payment mix, pay-ins/outs, expenses, cash variance, unpaid COD and X/Z audits.
9. Staff/payroll: accrued salary, advances, paid, remaining, department wages and dates.
10. Profitability: food cost vs net sales, gross margin by menu item/period, expenses and net profit **only when verified cost/accrual inputs complete**. Label incomplete/unreliable metrics rather than inventing money.
11. Exceptions and audit: voids, refunds, price override approvals, late orders, cash discrepancies, stock loss, failed sends and backup failures.
12. Export scheduling/delivery: close-day immutable Z-report and deep Excel workbook; approved email recipients, manual WhatsApp share, optional official automated WhatsApp, offline outbox and retries (chapter 25).

## L. Owner/supervisor settings [ADMIN]

Manager (Supervisor/Owner) is the only management role, with identical permissions for both titles; Manager can administer and approve but cannot perform cashier tasks. See chapters 01 and 24.

## M. First release vs later

**MUST for accepted production scope:** offline app, RBAC/PIN, business-day+shift, cashier billing, menu/deal CRUD, discount visibility, customer lookup/hold/recall, payments, delivery/trips/cash, stock and packaging, supplier-supplied items and Khata, expenses and custom categories, salary/advances, owner reports, PDF/XLSX export, email delivery with queued retry, basic backup/restore, tests and audit.

**RECOMMENDED/CONFIGURABLE:** manual WhatsApp sharing, supervisor expense posting permission, negative-stock blocking vs warning, certain report drill-downs, noncash payment verification details, supplier invoice aging and salary accrual policy.

**FUTURE pending explicit approval:** automatic WhatsApp Business Platform if not provisioned in first release, loyalty rewards/points, kitchen KOT/display, physical receipt printer/cash drawer hardware, delivery rider mobile app/GPS, cloud remote database, multi-terminal conflict resolution, multi-store/branch, full accounting/tax filing integrations.

## N. Minimum complete daily scenario

- Supervisor opens business day. Cashier PIN login and starts shift with Rs. 5,000 opening float.
- Cashier looks up returning customer's phone, selects prior address, adds a deal plus separate burger, selects published discount and checks out a COD delivery.
- BOM consumes chicken/bun/sauce plus correct delivery packaging **once**. Kitchen hears order verbally; cashier marks Preparing/Ready. Assigned rider takes order; customer receives it; rider cash is later handed in and counted exactly once.
- Supervisor adds new supplier, creates 'Charcoal' as a supplied item, purchases quantity partly on credit. Inventory receipt and supplier payable are created atomically; supplier gets Partially paid status or No payments if no amount was settled.
- Supervisor records a gas-cylinder petty cash expense using a newly created category. Drawer money decreases once, owner expense report classifies correctly.
- Supervisor creates cashier employee, PIN and salary, issues advance and partial salary payment; payroll ledger and cash source remain reconciled.
- Cashier submits blind cash count, supervisor reviews difference. Day is closed and locked, PDF/XLSX created, email queued and WhatsApp manual/automatic handled per configuration. Owner sees genuine net sales and warnings for uncosted profit figures.
- PC restarts: saved order, stock, supplier balances, PIN roles, financial history, queued emails and daily reports remain intact.
