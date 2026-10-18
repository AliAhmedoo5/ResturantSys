**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 29 — Comprehensive acceptance walkthrough, role-based scripts and release verification

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


**This is a hands-on test plan**, not a demo. Test against real Drift/SQLite persistent storage and deterministic fixture data. Run core scenarios offline, after restart, with expired sessions, after schema migration, and with deliberately failed I/O. Each issue must include steps to reproduce, expected vs actual, DB evidence and owner/supervisor acceptance.

## 1. One-hour role walkthrough for manager approval

Manager (Supervisor/Owner) is the only management role, with identical permissions for both titles; Manager can administer and approve but cannot perform cashier tasks. See chapters 01 and 24.

**Scenario 2: Supervisor catalog/stock (10 minutes).** Create categories Burgers, Deals; add Zinger Burger, Fries, Soda; create ingredient Chicken, Bun and wrapper; assign BOM; create Family Meal combo with choices and add-ons; publish 10% preset. Start cashier and verify new items and discount present. Archive deal: disappears from new cart while a prior sold order still reports original deal price.

**Scenario 3: Cashier fast billing (10 minutes).** Open business day and shift with Rs.5,000 float; phone-lookup existing customer, select address; add combo, change quantity, choose discount, place COD delivery. Hold a second order, lock/unlock and recall. Run exact cash takeaway. Repeat old order as *new* bill and confirm current prices. Basic checkout must fit 1366×768 with fixed cart and no routine vertical scrolling.

**Scenario 4: Rider and returns (5 minutes).** Assign two COD deliveries to same rider trip; mark one Delivered and one Failed; record return reason and food disposition. Post partial cash handover: cash drawer increases only by actual received, shortage remains; refund requires explicit authorized workflow and does not automatically put cooked ingredient stock back.

**Scenario 5: Supplier, stock and Khata (10 minutes).** Supervisor creates new supplier `Karachi Supplies`; inline creates `Charcoal` and `Paper Bags`, selects both; purchase filters to only those items. Buy 10kg charcoal Rs.6,000 with Rs.0 paid → supplier `No payments`. Pay Rs.2,000 from drawer → `Partially paid`, drawer decreases Rs.2,000; pay remaining Rs.4,000 from bank → `Paid`, no second drawer outflow. Try delete supplier: archive offered because ledger history exists. Perform physical stock count with one variance and adjustment approval.

Manager (Supervisor/Owner) is the only management role, with identical permissions for both titles; Manager can administer and approve but cannot perform cashier tasks. See chapters 01 and 24.

## 2. Role-specific destructive/action tests

| ID | Test | Expected |
|---|---|---|
| ROLE-001 | Cashier tries create supplier | Denied at service boundary, not only hidden button |
| ROLE-002 | Cashier tries delete expense category | Denied |
| ROLE-003 | Cashier tries edit menu product price | Denied |
| ROLE-004 | Cashier tries set discount preset | Denied; only apply published eligible |
| ROLE-005 | Supervisor creates expense category, edits and archives it | Allowed; historic expenses preserved |
| ROLE-006 | Supervisor creates menu product and combo deal | Allowed; cashier sees active product/deal immediately |
| ROLE-007 | Supervisor archives sold menu item | Allowed; historical sales correct |
| ROLE-008 | Supervisor creates cashier/manager PIN | Allowed only if globally unique |
| ROLE-009 | Supervisor creates/promotes Manager account | Denied |
| ROLE-010 | Manager configures F2/F3 etc. shortcuts | Allowed; conflicts rejected and recorded |
| ROLE-011 | Cashier runs restricted action by handcrafted command | Denied/audited |
| ROLE-012 | Supervisor changes company-wide email recipient without owner permission | Denied |
| ROLE-013 | Manager tries hard delete posted supplier transaction | Denied; reversal path available |
| ROLE-014 | Manager tries edit historic paid order in place | Denied; refund/rebill/adjust path |
| ROLE-015 | Archived staff PIN attempts authentication | Denied, prior audits preserved |

## 3. Checkout data and pricing tests

- Duplicate clicking Pay Confirm, switching rapidly between modes and killing app mid-save generates one or zero complete sale, never two.
- Tax-inclusive vs exclusive taxes, percentage/flat discounts, min spend, caps, stacking, deal upgrades, refunds and delivery fee tax treatment follow explicitly chosen policies. Test penny-level rounding using integer paisa.
- Held cart survives restart; if product price changed while held, operator sees proposed new total before continuing.
- Customer repeat order always creates new ID and current-line price, with archived menu conflicts surfaced.
- COD order saves as outstanding obligation; delivered fulfillment does not imply receipt of cash.
- Split tender sums exactly; cash change computed on actual retained amount, payment source constraints checked.
- No kitchen KOT, printer queue or hidden print attempt exists in happy-path or void-path.

## 4. Supplier/stock expense matrix

| Case | Stock | Supplier payable | Drawer cash | Report semantics |
|---|---|---|---|---|
| New item inline during supplier creation | Item exists with 0 stock | No change | No change | Catalog addition only |
| Supplier purchase Rs.4,000 all credit | +received units | +Rs.4,000 | 0 | Inventory acquisition not cash expense |
| Same purchase Rs.1,000 paid from drawer | +received units | +Rs.3,000 net | −Rs.1,000 once | Partial supplier settlement |
| Supplier paid remaining Rs.3,000 outside drawer | No change | 0 | 0 | Bank source, `Paid` |
| Supplier with unpaid purchase and Rs.0 paid | Stock still received | Positive payable | 0 | `No payments` |
| Receipt returned with vendor credit | −returnable units | −approved credit | 0 | Vendor credit/return separately |
| Cash expense Rs.800 fuel | No stock change | No change | −Rs.800 once | Expense fuel category |
| Stock wastage 2kg | −2kg | No change | 0 | Waste cost from inventory valuation |
| Physical count mismatch | +/− approved delta only | No change | 0 | Audited count variance |
| Kitchen food consumed in failed delivery | No automatic +stock | No automatic change | Depends on refund/handover | Waste disposition required |

## 5. Delivery/rider/payment matrix

- Rider trip with 3 COD orders: one Delivered+Collected, one Delivered+Rider Cash Pending, one Failed. Expected cash uses eligible actual collection events and recorded policy, not just `ordered_total`.
- Partial rider cash received twice sums exactly to expected; third replay with same command ID is no-op.
- Different operator cannot assign order to second concurrent active trip. Redispatch of Failed order creates new attempt event with link.
- Cashier shift close with rider handover pending flags exception according to policy but does not automatically count pending rider cash in drawer.
- Payment refunded by card should not create cash drawer outflow; refund tender/source consistent with policy.

## 6. Custom expense category CRUD tests

1. Supervisor creates category named `Gas Cylinders`, saves and reloads; category exists.
2. Create expense assigned to category; rename to `Cooking Gas`; historic expense remains linked and aggregates by stable category ID.
3. Attempt delete referenced category: hard-delete rejected with **Archive** action available; new expenses cannot pick archived category; existing history unchanged.
4. Create and delete an unused duplicate test category; no orphan records.
5. Category changes audited with before/after and actor; cashier not permitted to alter category.

## 7. Owner report acceptance catalog

- Trend dates grouped by **business day** with cutoff crossing midnight; filtering exactly matches drill-down and exported workbook totals.
- Net sales calculate discount, refund, tax/fees correctly under chosen accounting policy; customer payment and rider remittance separate.
- Sales by item/deal/category and discount redemption sum to eligible underlying detail with stable snapshots.
- Inventory beginning+receipts-consumption-waste-adjustment equals ending, with precise units and costing source.
- Supplier aging and `No payments` match each supplier ledger; payments from outside drawer do not change shift cash.
- Salary accrual and advances not double-charged; reporting discloses missing period data.
- When BOM cost missing, margin/net profit displays `insufficient cost data`, no invented figures or zero placeholders.
- Full export includes PDF and Excel and creates safe filenames; workbook opens in Windows Excel/LibreOffice independently of DB changes.
- Cash variance shows counted−expected with correct sign and stores submitted blind count separately.

## 8. Email / WhatsApp report acceptance catalog

| ID | Given/action | Expected |
|---|---|---|
| MSG-001 | Auto-email enabled, close day online | Z/PDF/XLSX generated, one queued/sent job per approved recipient |
| MSG-002 | Close while offline | Day closed; local report exists; jobs queued, sending retries later |
| MSG-003 | Restart after offline closure | Jobs and artifacts survive restart |
| MSG-004 | Click Close Day twice | One close + no duplicate automatic jobs |
| MSG-005 | Provider accepts send but callback delayed | State Accepted, not false Delivered |
| MSG-006 | Email provider times out after receiving request | Stable idempotency/ambiguous-delivery handling; avoid duplicate |
| MSG-007 | WhatsApp manual selected | Opens chat/share, operator attaches PDF; never marked auto delivered |
| MSG-008 | Automatic WhatsApp unconfigured | UI indicates requires official API setup; no silent fake send |
> Permission correction: Manager (Supervisor/Owner) has one unified management permission set, no cashier permissions; see 01 and 24.
| MSG-010 | PDF contains financial report | No PINs, API secrets, raw database paths, unneeded customer PII |
| MSG-011 | PDF renderer fails after close | Rebuild report intent; day stays closed and totals preserved |
| MSG-012 | Send failure | Logged in delivery history; retry does not close again |
| MSG-013 | Same business day past midnight | Report subject/attachment business date matches close snapshot |
| MSG-014 | PC powered off with jobs pending | Documentation/UI makes clear that local sending resumes when worker runs, unless cloud relay already received job |

## 9. Audit, security and backup tests

- Attempt privilege escalation and SQL injection via untrusted names/search/notes; parameterize queries and sanitize CSV spreadsheet injection (`=`, `+`, `-`, `@` strings).
- No four-to-eight-digit PIN stored, logged, displayed or included in report. Pin uniqueness robust against race, failed attempts persist across restart.
- Revoke/deactivate staff while session active; privileged new commands cease according to session-revocation policy.
- Backup under write load yields consistent SQLite checkpoint/snapshot; encrypted restore verified by checksums and controlled key handling.
- Apply old→new DB migration with orders, refunds, supplier payables, past salary payments and queued report sends; all balances and unique constraints verified.
- Simulate disk full, removable backup missing and expired API token: local billing remains reliable wherever storage itself is available; failures surface proper recovery.
- Audit immutability: any existing audit event can be read by authorized users but no UI/service route modifies or deletes it.

## 10. Exit criteria and delivery handover

- All modules exercised on target Windows hardware, keyboard and touchscreen if applicable.
- Developer provides executable installer, tested migrations, startup data paths, written backup restore procedure, role-admin handbook, operator POS cheat sheet, example owner reports, privacy and support notice, issue log, known limitations and reproducible tests.
- Owner approves unresolved business decisions from `22-decisions-and-assumptions.md` (tax, costing, negative-stock, refunds, cash variance, supplier advance, PIN recovery and report recipient policies) **before** real transactions.
- No demo seeded sales, sample PIN or exposed developer key in production installer.
- No inferred kitchen printing, rewards or remote rider tracking implemented as first-release functionality.
- All accepted end-of-day notification requirements match `25-business-day-report-email-whatsapp-delivery.md`, including graceful offline behavior and provider-dependent limits.


## v6 mandatory additions

Execute all ten Chapter 32 acceptance cases, including integer paisa rounding boundaries (49,50 paisa), split final balancing cash remainder, inclusive tax, non-recycled tokens, required separate Cashier wizard PIN, opposing modifier radio rules, revision+settlement lock race, nullable approved_by DB migration, and post-settlement correction by documented refund. No regression may require Manager PIN for ordinary pre-settlement edits or routine drawer movements.
