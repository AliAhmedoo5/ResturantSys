**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 19 — Automated tests, user acceptance and release criteria

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Test pyramid

- **Unit:** money/tax/rounding, catalog/deal expansion, recipe/packaging, unit conversion, supplier status, cash expected/variance, salary/advance math, report formula, role permission, shortcut context.
- **Repository/transaction:** real in-memory or temporary SQLite + Drift migration; foreign keys, order atomicity/idempotency, cross-ledger postings, concurrent stale versions and recovery.
- **Widget:** cashier at 1366×768; PIN entry; deals/modal focus; customer lookup; supplier item creation; expense category CRUD; staff PIN unique validation; report filter; error states.
- **Integration/E2E:** start from fresh onboarding through opening shifts, sales, dispatch, supplier purchase, stock count, expenses, cash close, Z-report, backup/restore and app restart.
- **Mutation/property tests:** retry every posted command twice; `sum(posted ledger)` invariants after randomized sequences; partial payments and reversals; valuation and unit conversion precision.

## Test data fixture

Create realistic PKR test dataset: 5 categories, 35 products, 6 deals, 30 stock SKUs (ingredients and packaging), 4 supplier mappings (including custom supply item), 10 staff across roles, 100 customers with area/address, 500 orders across multiple business days, 20 rider trips, 20 expense categories, 40 purchases, partial Khata payments, salary advances, 3 stock count sessions and deliberate bad-event attempts. In production install, never seed sample sales.

## Critical acceptance scenario catalog

| ID | Given / action | Expected result |
|---|---|---|
| AUTH-001 | Owner onboarding from fresh DB | Manager PIN and secure key created; no vendor default PIN, no duplicate owner wizard |
| AUTH-002 | Supervisor creates cashier then same PIN for another supervisor | Unique collision blocked; no identity leaked; old user unaffected |
| AUTH-003 | Supervisor tries to promote a cashier to Owner | Denied in UI and service layer; auditable attempt |
| AUTH-004 | Five incorrect login attempts, app restarted | Persisted rate limit/throttle remains enforced |
| POS-001 | Add ordinary burger item by tile click | Cart updates immediately, no modal or page scroll |
| POS-002 | Open delivery and search phone in +92 form | Existing 03… customer recognized; select address |
| POS-003 | Hold with configured deal choices then restart | Held draft persists and recalls, no paid order/stock deduction/token |
| POS-004 | Copy repeat customer's old order whose deal is archived | Warning and replacement choice; never silently charges old amount |
| POS-005 | Supervisor enables new active 10% preset | Visible in cashier without relogin; rule and min spend enforced |
| POS-006 | Invalid discount, split payment or under-tender | Service rejects; cart stays intact; actionable message |
| POS-007 | Rapidly click Confirm 3 times or restart mid-commit | Exactly one order, token and inventory posting set |
| POS-008 | Remap F3 to new action; type in search field | Shortcut works only outside input; no action while typing |
| POS-009 | Checkout under configured soft-stock mode at zero | Order posted, negative stock warning/event retained |
| DEAL-001 | Create build-your-own deal with required drink selection | Missing drink blocks add; valid choice uses one parent price plus upgrades |
| DEAL-002 | Deactivate deal used in historic sale | Hidden in new POS; historic sale and reports unchanged |
| STK-001 | New supplier defines `Charcoal` custom stock item | Item created with type/unit; linked to supplier and selectable for purchase |
| STK-002 | Purchase item not supplied by selected supplier | Rejected in UI and service, with mapping-edit path |
| STK-003 | Purchase 2.5kg, recipe uses 150g | Stock movement/base units correct with decimal precision |
| STK-004 | Count opened; purchase posted; count submitted | No stale balance overwrite; snapshot recalculation or recount |
| STK-005 | Failed cooked delivery cancelled | No automatic ingredient restock; waste/refund decision recorded |
| SUP-001 | Supplier purchases exist, zero paid | Status `No payments`; credit ledger still shows amount owed |
| SUP-002 | Supplier invoice Rs.8,000, pays Rs.3,000 cash | Payable Rs.5,000; one drawer cash out; `Partially paid` |
| SUP-003 | Pay remaining Rs.5,000 from bank | `Paid`; no additional drawer movement |
| SUP-004 | Supplier with payable is deleted | Hard-delete rejected; archive allowed and payable reportable |
| EXP-001 | Supervisor creates, renames unused expense category | New name available for new expenses; audited |
| EXP-002 | Category referenced by posted expense is deleted | Hard-delete denied; archive supported, history intact |
| EXP-003 | Create Rs.500 cash expense then retry same request | One expense and one Rs.500 cash-out only |
| CASH-001 | Shift starts float Rs.5,000 and cash sale Rs.1,000 with Rs.200 change | Closing expected Rs.5,800 prior other movements |
| CASH-002 | Cashier blind closes shift | Expected cash not visible before submit; variance afterward |
| CASH-003 | Short shift Rs.300, next staff arrives | Review flag persists; authorized next shift can open |
| DEL-001 | Mark COD order Delivered with no payment | Order Delivered but Unpaid; no rider cash received yet |
| DEL-002 | Rider trip has 1 prepaid and 1 COD order | Expected handover includes COD only |
| DEL-003 | Rider pays part of expected handover | Remaining shortage/liability tracked; drawer receives only actual |
| DEL-004 | Failed delivery reattempt next business day | One original sale, attempt lineage, no duplicate sale ingredients |
| PAY-001 | Salary accrual + cash advance + bank salary payout | Liability/recoverable correct, drawer only decreases for cash advance |
| PAY-002 | Salaried employee with ledger history deleted | Hard delete rejected; archived and still traceable |
| ORD-001 | Void order after cooking | Refund and waste handled explicitly, stock not blindly restored |
| ORD-002 | Attempt repeat refund against already refunded amount | Rejected; no duplicate cash refund |
| REP-001 | Sales report custom business date across midnight | Attribution by business day, not calendar date |
| REP-002 | Supplier credit inventory purchase in profit view | Recognizes inventory/payable, not cash expense or automatic COGS |
| REP-003 | Recipe cost unknown | Profit report displays missing coverage, not invented profit |
| REP-004 | Export report with selected filters | Row/detail totals match on-screen results, no PIN/secret leakage |
| BKP-001 | Backup during active WAL write | Verified consistent restoration, no broken DB |
| BKP-002 | Simulate corrupted backup | Restore blocked, original live DB untouched |
| BKP-003 | App upgrade with old data | Forward migration and totals retain original balances |
| SEC-001 | Cashier invokes supervisor command through shortcut/repository | Permission denied, audit metadata captured |

## Performance and cashier usability

On target Windows PC: ten test orders (basic, repeat, deal, dine-in, delivery COD, discount, split, held, rider assignment, canceled), no full-page vertical scrolling during typical cashier billing at 1366×768 and 125% scaling; essential actions reachable by keyboard; demonstrate basic order within 15–30 seconds after cashier familiarization (provisional target, validate with staff). Confirm accessible focus for category/menu grid and modal. Test 100 products and 12 cart lines.

## Release signoff checklist

- [ ] Every domain requirement has at least one automated acceptance test; tests run in CI on Windows runner.
- [ ] No plaintext PIN or unredacted secrets in DB/logs; role escalation blocked and unique PIN guaranteed.
- [ ] Decimal money and unit math independently checked with fixtures.
- [ ] All posted operations have idempotency / reversal behavior and crash simulation.
- [ ] Closing cash, supplier credit, rider remittance, payroll and stock totals reconcile to ledger.
- [ ] No kitchen tickets, kitchen print or kitchen dashboard accidentally enabled.
- [ ] Customer loyalty/rewards absent from initial active flows.
- [ ] Stock/purchase/expense/staff/menu/deal CRUD and archival work across app restart.
- [ ] Export CSV/Excel/PDF opened in Windows applications; totals correct.
- [ ] Encrypted/verifiable backup created and successfully restored on test hardware.
- [ ] Production install includes secure first-run onboarding, privacy/error notices, backup destination and operational user guide.

## Report delivery and expanded role QA references

See `29-comprehensive-qa-and-real-restaurant-walkthrough.md` and `25-business-day-report-email-whatsapp-delivery.md`. Release-blocking tests: offline day close with PDF/XLSX and queued email; restart then single delivery; wrong recipient denial; source file missing and retry; duplicate close click; ambiguous provider accepted state; no PIN/API key leak; message failure doesn't reopen day; supervisor can edit/delete unused expense categories but not Manager account; supervisor can CRUD menu/deals; cashier can't alter global shortcuts; supplier custom supplied-item auto-filter persisted.

## v5 regression acceptance

- Manager creates an inventory-using menu item without a recipe: can save inactive draft but activation and cashier visibility are blocked, with an explanatory error.
- Manager completes ingredient, base-unit and quantity rows then activates item: cashier can sell it and all ingredient quantities are deducted exactly once even if stock is negative.
- Manager builds combo with a missing-recipe component/selection: cannot activate. Once every choice path is recipe-complete, preview expands components and final sale deducts each included ingredient exactly once.
- Cashier chooses JazzCash, Easypaisa, Bank/Raast or Card: only method selection, optional reference and Complete payment; no Unverified, Processing, gateway verification UI or official API dependency; paid entry and audit saved.
- Cashier chooses COD: unpaid/collection due is preserved; this is a receivable status, not gateway verification.


## v7 acceptance tests — customer workflow, areas, pictures

1. Cashier adds three items and clicks Continue — Customer; no order/token/stock movement exists yet. Enter delivery name/phone/area/address; payment and final commit atomically link customer and immutable address and delivery-fee snapshot.
2. Existing caller number lookup lists saved addresses; choosing address fills known area and house; no accidental duplicate person is created.
3. Delivery requires enabled serviceable zone; Manager deactivates zone mid-flow; Cashier final save fails with recoverable area-selection message without losing cart.
4. Manager creates new serviceable area with fee 250 PKR, cashier selects it, checkout total adds 25,000 paisa; past orders remain at their former fee if Manager later edits zone.
5. Manager archives historical service area; it disappears from new orders but previous orders, reports and references survive.
6. Manager creates recipe-complete menu item with no image; publication and sale succeed, cart is fast and fallback works.
7. Manager uploads 3 valid product images and chooses primary; thumbnails persist after restart and appear on cashier tile. Replace/delete operations preserve order/BOM data.
8. Deal can have multiple optional images; missing pictures never prevent deal activation if each recipe is valid.
9. Oversized/invalid image rejected before database write; EXIF sensitive location stripped; disabled filenames/paths cannot escape app media directory.
10. Offline POS boots and loads cached menu pictures without external API; image failures do not block order entry.
11. Security: Cashier cannot manage delivery zones/photos, Manager cannot enter or finalize a sale.
12. No double token/stock posting on pressing Continue multiple times or retrying final save.
