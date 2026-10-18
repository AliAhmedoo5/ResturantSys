# 32 — FINAL ENGINEERING DECISIONS: post-confirmation lock, cash rounding, tax defaults, tokens, onboarding, modifiers (v6)

**Authoritative as of 12 October 2026. This chapter resolves the six detailed implementation decisions presented after v5 and takes precedence wherever older documents contradict it.** The product still has exactly two login roles: Cashier and Manager (Supervisor = Owner). Manager does not bill customers. Cashier actions listed here require NO manager PIN and remain fully audited.

## 32.1 Confirmed order revisions and rider trip settlement lock

- **Cashier may amend or cancel a confirmed order** in `Confirmed`, `Preparing`, `Ready`, and `Out for Delivery` while its linked rider trip has **not** reached `Settled`. Changing an out-for-delivery order must prominently flag the rider/dispatch reconciliation and record a communication/action-required event. Save revision `before` and `after` snapshots, cashier, timestamp, reason, price/tax/discount/fee deltas and stock disposition. No manager PIN.
- **If the associated rider trip is `Settled`, direct cart/line edits are locked**, regardless of the displayed order status. A correction to money previously collected is a separate **Refund/Adjustment** document with explicit actual disbursement, actor, reason, and settlement/audit links. Do not rewrite the prior trip handover or finalized order revisions.
- **For additions after settlement**, create a *new order* rather than editing settled lines. A refund must never have a positive extra-sale amount or create new item quantities. An already closed/locked business day also forbids in-place order changes; date later corrective documents in the current open business day.
- A rider trip that is returned but **not yet settled** is still editable subject to other order/business-day locks. Status and trip settlement are distinct. Avoid depending on literal status names alone: enforce a persisted `settled_at_utc` / settlement posting lock checked transactionally.
- If there is **no rider trip**, settlement-lock condition is false; business-day closure and other financial locks still apply.
- Cancellation of a paid order does not itself mean money was refunded. Log refund due/pending versus cash/online refund actually performed. Stock returns require unprepared vs already-cooked disposition.

**Atomic edit transaction:** verify cashier session, business day still editable and no settled trip; compare order revision number; insert `order_revisions` + `order_revision_lines`; insert price/tender receivable/stock deltas and audit; advance `orders.current_revision`; commit once with idempotency key. A failed comparison must reload, not overwrite.

## 32.2 Schema: durable revisions and nullable drawer approver

Add **real Drift/SQLite migrations**, not only Dart model classes. At minimum:

```sql
CREATE TABLE order_revisions (
  id TEXT PRIMARY KEY,
  order_id TEXT NOT NULL REFERENCES orders(id),
  revision_no INTEGER NOT NULL CHECK (revision_no >= 1),
  prior_revision_id TEXT REFERENCES order_revisions(id),
  action TEXT NOT NULL CHECK (action IN ('ADD','CHANGE','REMOVE','CANCEL','CORRECTION')),
  reason TEXT NOT NULL,
  cashier_id TEXT NOT NULL REFERENCES staff(id),
  business_day_id TEXT NOT NULL REFERENCES business_days(id),
  created_at_utc TEXT NOT NULL,
  old_total_paisa INTEGER NOT NULL,
  new_total_paisa INTEGER NOT NULL,
  money_delta_paisa INTEGER NOT NULL,
  prior_snapshot_json TEXT NOT NULL,
  new_snapshot_json TEXT NOT NULL,
  command_id TEXT NOT NULL UNIQUE,
  UNIQUE(order_id, revision_no)
);
CREATE TABLE order_revision_lines (
  id TEXT PRIMARY KEY,
  revision_id TEXT NOT NULL REFERENCES order_revisions(id),
  original_order_line_id TEXT,
  item_id TEXT,
  action TEXT NOT NULL,
  old_qty_decimal TEXT NOT NULL,
  new_qty_decimal TEXT NOT NULL,
  line_price_delta_paisa INTEGER NOT NULL,
  bom_disposition TEXT NOT NULL,
  ingredient_delta_snapshot_json TEXT NOT NULL
);
```

Existing `cash_movements.approved_by` **MUST be nullable** (`TEXT NULL REFERENCES staff(id)`). Routine cashier shift `PAY_IN` and `PAY_OUT` events do not need manager approval. `approved_by=NULL` means not manager-approved/approval not applicable, **not** missing an audit actor. Always require `actor/cashier_id`, movement type, positive amount, reason/source and idempotency key. Only special manager-authorized adjustments, if separately introduced, populate `approved_by`; do not make ordinary expense/drawer pay-in/out depend on it. For an existing SQLite NOT NULL column, perform a safe table-rebuild migration preserving records, foreign keys and indexes (SQLite cannot directly DROP NOT NULL). Test old-db upgrades.

`orders` must carry persisted `current_revision` and lock/version state. Optional `settled_at_utc` may be denormalized only if linked to authoritative settled trip posting. Ensure transaction checks for concurrent trip settlement and revision attempts; one must win and the other retry/fail cleanly.

## 32.3 Integer paisa and cash-only rounding policy

All calculation amounts remain **signed 64-bit integer paisa** (`Rs.1=100 paisa`). **Round physical cash due to the nearest whole rupee (100 paisa)** using mathematical **half-up for nonnegative amounts**; e.g., positive residue 50 paisa goes up. This is a *business display/tender rounding*, not a rounding of item price, tax calculations or digital tenders. Default rounding increment is exactly `100 paisa`, not Rs.5 or Rs.10; a configurable denomination policy can be added later as an explicit separate decision.

```text
round_cash_paisa(cash_due_exact_paisa) =
    floor((cash_due_exact_paisa + 50) / 100) * 100     // only cash_due >= 0
cash_rounding_paisa = rounded_cash_due_paisa - cash_due_exact_paisa
```

- For **cash-only**, exact order due 61,625 paisa (Rs.616.25) → cash due 61,600 (Rs.616), `cash_rounding_paisa = -25`.
- 61,650 → cash due 61,700 (Rs.617), rounding `+50`; 61,649 → 61,600 (`-49`).
- **Digital only** (JazzCash, Easypaisa, Card, Bank/Raast) retains 61,625 paisa exactly; `cash_rounding_paisa=0`.
- **Split tender:** first subtract *exact* valid noncash components from the exact remaining invoice; round the **final balancing cash portion exactly once**. Example Rs.616.25 total − Rs.200.00 wallet = Rs.416.25 cash exact → Rs.416 cash actual, delta −25 paisa; the wallet remains Rs.200.00. Digital Rs.200.25 → cash Rs.416.00, delta 0. Do not repeatedly round separate installments or round the entire order before allocating digital tender. Require the cash leg to be the final balancing payment for this initial version.
- Cash tendered and change are calculated against **rounded physical cash due**; change is whole-rupee. Prohibit cash underpayment; keep digital amounts untouched. Persist exact total, cash-rounding delta and finalized payable as separate values.
- On **COD cash collection** at delivery, apply the same rounding exactly once when the due balance is actually paid in cash, not at order confirmation if payment channel is still uncertain. Rider expected cash and handovers use that cash due amount. COD digital collection remains exact.
- `cash_rounding_paisa` must be stored as a signed integer on the finalized financial document/tender close (and reflected in a `ROUNDING_GAIN_LOSS` ledger account); do not bury it inside a menu item price, tax, discount, or net sale revenue. Ensure shift expected cash, day Z, refunds and analytics reconcile with the effective collected amounts. During refunds, reverse/allocate previous rounding explicitly rather than rerounding historical item totals.
- Never use floating point for 15%, prorated deal allocation, unit conversions involving money or tax: use integer arithmetic or checked fixed-decimal rational computation with a documented deterministic residue allocation to line IDs.

## 32.4 Tax defaults: predictable shelf prices, not legal assumptions

New restaurant setup defaults: `tax_pricing = TAX_INCLUSIVE`; `tax_rate_bps = 0` (0%) **until Manager configures a verified applicable rate and rules**. Show exactly the catalog price as the customer-facing item price. Never automatically add a tax percentage on top of a displayed item price under the default.

- **Inclusive rate example only:** manager sets 13% for a legally applicable category. Item display price Rs.500 stays Rs.500. Included tax is calculated from price using rational inverse formula, e.g. `tax_included = rounded_paisa(50000 * 1300 / 11300)`; taxable base = displayed price − included tax. Do not treat 13% as a legislated universal default.
- Different items, delivery fee and payment method may have different legally applicable treatment. Manager must configure these according to current advice from an accountant/tax advisor, including any required tax-inclusive/exclusive differentiation. Tax at checkout cannot silently change catalog total.
- Keep price/tax snapshots and tax-code revisions for historical receipts/reporting. Discount allocation and percentage rounding must use exact money arithmetic. Tax reporting requires final approved policy before go-live.

## 32.5 Daily tokens are consumed once and never recycled

- A confirmed order receives its business-day-local token via an **atomic persisted counter** in the checkout SQLite transaction. UNIQUE `(business_day_id, token_number)`.
- On a successful commit, token is permanently used even if the order is later canceled, edited, refunded or returned. Token #14 canceled → next is **#15**. Do not renumber orders or fill gaps from cancellations.
- Unconfirmed/held drafts **do not** receive tokens. A failed/rolled-back confirmation transaction has no committed token/order and may retry safely. Never allocate an order token outside the atomic commit. Business day change resets the separate day's sequence only.
- Duplicate click/retry with same idempotency key returns the same committed order and same token; never creates another order.

## 32.6 First-run setup cannot strand the restaurant without a Cashier

Initial setup wizard, in order:
1. Restaurant identity, local storage/backup location and business currency (PKR), with initial tax-inclusive/0% default clearly shown.
2. Create **first Manager (Supervisor/Owner)** PIN; unique 4–8 digits, securely hashed, and manager-only configuration access. Manager can never perform cashier billing.
3. **REQUIRED: Create primary Cashier account and unique 4-digit PIN**, different from Manager. Explicit heading: **“Create your primary Cashier counter profile and 4-digit PIN.”** Cashier may use later approved 4–8 digit PIN policy, but wizard defaults/asks exactly 4 digits for the primary cashier. The wizard cannot finalize without one enabled Cashier.
4. Create/defer restaurant menu setup; no saleable items without mandatory validated recipes. Explain the prerequisite rather than seeding fake recipe-less saleable products. Offer a reviewed import or a guided first recipe.
5. Manager opens the first **business day** (or the wizard provides a Manager-authorized Open Day action). Then a guided **Switch to Cashier** button opens cashier PIN login; cashier opens shift and opening float; only then is billing enabled. Show the checklist until ready, without logging a Manager into a Cashier session.

If the database is restored or Cashier is later deactivated, manager startup dashboard must show **“No active cashier — create one”** rather than misleading checkout. Ensure PIN uniqueness, role separation and recovery process.

## 32.7 Mutually exclusive modifiers and deterministic recipe calculation

- `modifier_groups` need explicit `selection_mode` = `SINGLE` (radio) or `MULTI`, `min_selected`, `max_selected`, `required`, and sort order. `modifier_options` belong to groups; optional explicit conflict-pairs may cover cross-group conflicts.
- Define **Sauce preference** (`SINGLE`, exactly one): `Normal Mayo` (base recipe 20g), `No Mayo` (target 0g), `Extra Mayo` (target base+30g = 50g, optional +Rs.30). UI auto-replaces the previous choice in that group. **No Mayo and Extra Mayo can never coexist**.
- Define recipe modifier semantics in terms of **target net ingredient consumption or delta from a known base**, never ambiguous combinations of “remove” and “add” with different ordering. Base recipe 20g + No Mayo delta −20g ⇒ 0g; Extra Mayo delta +30g ⇒ 50g.
- Additional unrelated modifiers (e.g. cheese and spice level) may be separate groups, with MULTI selection only when physically combinable. Enforce exclusivity both in UI and domain validators; reject invalid legacy/imported modifier combinations at sale commit.
- Deal choice modifiers and variants must obey identical group/conflict constraints, and all allowed selectable paths must have a complete validated recipe. Snapshot selected modifiers, price and BOM delta per order revision.

## 32.8 Acceptance tests (mandatory)

1. Edit Preparing, Ready, Out for Delivery orders as cashier: no manager PIN, logs revisions and stock/payment differences; rider communication flag on dispatched orders.
2. Set linked rider trip Settled: direct item/quantity/price edits rejected even if order remains Out for Delivery; new sale requires new order; refund correction creates separate document. Manager cannot edit cashier order.
3. Create revisions with same idempotency key twice: one revision only; concurrently settle trip and edit order: exactly one conflicting action succeeds deterministically.
4. Cash movement PAY_IN/PAY_OUT by cashier with `approved_by=NULL` persists, reason/cashier/time mandatory; migration from legacy NOT NULL schema preserves events.
5. Rs.725 with 15% discount → Rs.616.25 exact; cash sale Rs.616 and rounding −25 paisa; digital sale Rs.616.25, delta zero; split residual rounding exactly once; no fractional cash change.
6. Initial tax inclusive 0% item price Rs.500 → bill Rs.500 exactly. Configured 13% inclusive remains Rs.500 and included tax is broken out, not added on top.
7. Confirm token #14 then cancel → next order #15; held carts tokenless; retry same confirmation returns same token; new business day starts #01.
8. Fresh installation cannot finish without Manager and Cashier (distinct PINs); guided day open and cashier shift open lead to first bill; Manager checkout denied.
9. No Mayo selected then Extra Mayo → No Mayo auto-deselected; base sauce 20g plus Extra Mayo 30g posts 50g. Contradictory imported modifiers fail validation.
10. Post-order stock at zero/negative is allowed and subsequent receipts net without double consumption; every sellable menu and deal still requires a valid BOM.

## 32.9 Still needing owner/accountant configuration

These policies close the enumerated implementation ambiguities, but **do not mean the whole ERP has no unresolved decisions**. Actual applicable Pakistan/provincial tax rates and registrations, refund funding policy, negative-stock valuation method, cash discrepancy thresholds, depreciation/general accounting treatment, payment recipient details, and supplier-pack conversion settings must still be finalized before go-live. No claim of universal tax law is made here.
