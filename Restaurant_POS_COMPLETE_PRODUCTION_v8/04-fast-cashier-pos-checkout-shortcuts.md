**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 04 — High-speed cashier POS, billing, discounts, payments and shortcuts

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Absolute interaction priority

A trained cashier should complete a standard order on a 1366×768 Windows workstation **without vertical page scrolling or switching to a management page**. Normal workflow: select dining type/customer, tap/search item, optional discount, payment/confirm. Fixed cart, total and primary action remain visible. Use keyboard/numpad and mouse. Keep the default workspace distraction-free: no charts, owner metrics or irrelevant notifications.

## Layout [POS-01…08]

- Header ≤64px: operator, shift, business date, local/offline status, lock; not a scrolling navigation region.
- Product space ~62–65%, cart ~35–38% (minimum ~340px). Category chips, large product tiles, compact search + barcode-like quick code support if configured.
- Product click increments quantity immediately for straightforward items. Deals and required modifiers open a compact keyboard-accessible choice sheet only when necessary.
- Fixed cart: rows, `+/-`, edit options, remove, subtotal, discount, tax display, delivery fee, **large total**, **Checkout** and **Hold**. Long carts scroll within cart only, total and charge button remain pinned.
- Use `F2` new cart, `F3` hold, `F4` recall, `F5` customer lookup, `F6` discount, `F7` confirm, `Ctrl+K` search as suggested defaults, **not mandatory hardcoded bindings**.
- Avoid nested modal chains; keep overlay count to one. Return keyboard focus after closing.
- Touch targets ≥44–48px; searchable tabs; keyboard focus ring; screen usable at 100%/125% Windows scaling.
- Cashier view must be role- and feature-aware, with no supervisor settings or PIN values.

## Cart model [POS-09…17]

Each cart line holds product/variant/deal selection, modifiers, qty, human-readable instructions, unit price snapshot preview and applicable recipe components. A deal is one sale line composed of its chosen items and upgrades; never multiply both parent deal and child prices incorrectly. Store individual item pricing and composition snapshots at commit. Changing product availability while cart open triggers validation at checkout; show clear choices, never silently alter price.

Order modes: Delivery (address, area, phone, delivery fee and COD), Takeaway, Dine-in (table number, 3–5 tables configurable). Separate discount from delivery fee unless preset explicitly allows it. Supervisor can make a percentage or flat PKR preset with active dates, allowed modes, minimum spend, product/deal restrictions and stacking policy. Active eligible discounts **always appear to the cashier** and remain after restart. If discount becomes invalid before checkout, explain the reason and ask cashier to pick another, not silently discount wrong amount.

## Customer lookup and repeat [POS-18]

Phone input normalizes +92/03; exact lookup is immediate with suggestions for repeated customers. Selecting result populates name, address options, area, landmarks and order history. Repeat order copies prior choices to editable draft but **re-evaluates current catalog availability, current prices and applicable discounts**; never assert the old price remains valid. No exposure of customer phone/address in unrelated reports or external exports by default.

## Hold and recall [POS-19]

Hold stores draft and cart lines transactionally with owner/session, source workstation, creation time, optional expiry, customer context and retained deal choices. Recall has searchable list; locked editing prevents two active users editing same draft concurrently. Held carts are not paid orders, do not consume stock, do not allocate sale token and do not enter revenue. Abandoned holds can expire/require supervisor clean-up without losing audit metadata.

## Payments [POS-20…30]

Configurable Cash, Card, Bank/Raast, Easypaisa, JazzCash, COD and Split. Store payment channel, optional reference, cashier-confirmed status and evidence notes. All tenders are manual: the cashier selects the actual payment method and records the received amount (checking customer payment outside the application as ordinary cashier practice); the POS does not initiate or verify external transactions. **No payment provider API, gateway, webhook or bank integration is a prerequisite.** The system records the cashier action and method; it must not show API-style verification/processing states. Cash tendered must cover cash component; calculate change exactly, display in prominent type, never allow negative change. Split tender amount summed exactly to payable with safe paisa rounding; remaining amount must be zero before paid confirmation. Cash drawer movement only for actual cash collected/returned. COD is a receivable; dispatched/delivered order may still be unpaid.

Commit transaction contains order, lines, taxes/discounts, ordered time, actor, business day, payment allocation, inventory events, packaging events, order number/token and idempotency key. Repeat taps, app crash or navigation retry cannot duplicate order. Persist first and show success after commit. Disconnected devices cannot block SQLite-local billing. No receipt printer requirement; optional digital receipt generation can fail/retry independently after save.

## Shortcut manager [POS-31…36]

Manager can create global/role shortcut profiles and ordered quick-action toolbar. Actions from registry (`new_order`, `hold`, `recall`, `customer_lookup`, `product_search`, `apply_discount`, `checkout`, `cash_tender`, `orders`, `rider_dispatch`, `expense`, etc.). Validate duplicate bindings within a context, reserved OS combinations, unsupported contexts and modifiers; show conflicts before save; ability reset to defaults and test bindings. Never trigger while typing in input or PIN field. Disabled/unauthorized actions remain blocked from keyboard invocation. Labels or tooltips display active shortcut values. Map changes applied to new sessions/current appropriate context safely and audited.

## Validation / errors

- Active shift and open business day required to post cashier sale; drafts can be retained if shift ends, with ownership policy.
- Empty cart, nonpositive item qty, duplicate unsettled confirm, unavailable product, missing required deal choice, invalid discount, split under/overpayment and delivery address validation show local inline messages.
- If stock is zero/negative/insufficient, **always allow checkout** and post complete stock consumption exactly once. Record negative balances and alerts; later receiving stock adds to the negative balance, never deducts the same deficit again. No blocking low-stock feature flag.
- Never erase cart on failed payment/DB commit. User sees retry and same idempotency context.
- Menu price edits mid-order: before commit show price changes; after commit old order never changes.

## Acceptance

Create basic bill with ≤3 deliberate item/tender interactions after entry; scroll test at 1366×768; hold/recall after app restart; repeat customer with newly inactive item warns; cashier always sees active eligible supervisor discount; expired/noneligible discount hidden or disabled with reason; payment split validation and change math exact; duplicate submit creates one order and one stock posting; changed shortcuts work and respect PIN/modal input focus; COD delivered without being considered paid.

## v5 payment-screen simplification

No `unverified`, `processing`, `awaiting provider`, `manually confirmed` badge or API-status tag in cashier UI. After selecting Cash/JazzCash/Easypaisa/Bank-Raast/Card and confirming, show a normal paid sale. Optional transaction reference is informational. COD remains unpaid/collection-due, and split indicates remaining balance. Backend still writes cashier, timestamp, method and ledger entry; these are audit facts, not additional cashier verification steps.


## v6 Cashier payment and order locking

Complete cash tender rounds final cash-due remainder **once** to nearest whole rupee; digital stays exact integer paisa; signed cash rounding delta posted separately, see Chapter 32. Tax-inclusive pricing defaults to 0%; never add tax on top of configured shelf prices by default. Confirmed cashier revisions permitted Preparing/Ready/Out for Delivery until rider trip Settled; after settlement direct cart changes locked (refund/adjustment or new order instead), without routine Manager PIN.


## v7 — Cart → Customer → Payment → Commit (authoritative order-entry flow)

The cashier must first select menu items/deals, quantities and modifiers into an **uncommitted cart**. The primary action is **Continue — Customer**, NOT `Confirm Order` or an irreversible confirmation. Display a customer-details sheet/step next with order type. For delivery, require customer name, normalized phone, delivery area chosen from Manager-configured currently serviceable areas, address details and optionally landmark/instructions. On entering phone, match existing customer(s); cashier can select stored address or create another. Customer identity and selected address are linked to the order at the final save. For takeaway/dine-in, only relevant fields may be optional or skipped. If delivery area unavailable, prevent final delivery confirmation with visible guidance to change area or order mode; do not lose cart.

Next show simple manual payment methods/COD, full amount including area fee, and **Complete Order**. The *database order, business-day token, full recipe+packaging ledger debit, payment record and customer link* all commit in one atomic transaction at this final step. Before this stage, cart/customer details are mutable draft state and can be held/recalled; no daily token or inventory deduction is allocated. Once confirmed, v6 cashier amendment/no-PIN and rider-settlement-lock policies apply. Use a compact dedicated customer drawer or modal, not a long scrolling POS form. Returning customer saved details are suggested, never silently overwrite current order fields.
