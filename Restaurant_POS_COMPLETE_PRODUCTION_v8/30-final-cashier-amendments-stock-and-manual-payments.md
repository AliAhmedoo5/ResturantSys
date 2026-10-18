# 30 — FINAL AUTHORITATIVE BUSINESS DECISIONS: cashier amendments, perpetual stock, and manual tenders (v4)

**Status: CONFIRMED, 12 October 2026. Supersedes all contradictory sections of chapters 00–29, original 01–10 files and the frontend demo.**

## A. Roles remain strictly separated

Only `CASHIER` and `MANAGER` (Supervisor and Owner are the **same** management role). Cashier alone creates/edits/cancels order transactions and receives customer/rider payments. Manager alone configures products/deals/discounts, employees/PINs, supplier items, stock/counts, salaries, expense categories, reports, settings/shortcuts and business-day closure. Managers **do not** use cashier POS. All commands require server/service-side authorization even offline in SQLite app.

## B. Cashier may modify a confirmed order without Manager PIN

| Action | Cashier | Manager PIN | Mandatory journal |
|---|---|---|---|
| Increase/decrease quantities | Allow | **NO** | order revision and item/BOM delta |
| Add item/modifier/deal | Allow | **NO** | before/after revision and delta |
| Remove item or modifier | Allow | **NO** | reason, cashier ID, item, qty, timestamps, stock disposition |
| Cancel entire confirmed order | Allow | **NO** | reason, original snapshot, stage, payment and stock disposition |
| Change delivery details/mode while operationally possible | Allow | **NO** | before/after snapshots and fee/packaging changes |
| Record collected-money refund separately | Allow within validated refundable funds | **NO routine PIN** | refund and tender-specific cash/external evidence ledger |
| View all edits/cancellations/refunds | Manager | Not applicable | searchable supervisory reports |

1. Use `orders` stable identity; `order_revisions` and `order_revision_lines` append-only (never overwrite original snapshot).
2. Captures `cashier_id`, order ID, business day, old/new values, reason, timestamp, customer/request context, preparation status and adjustment ID.
3. Calculate new item, deal, discount, tax and delivery-fee totals deterministically. If paid and reduced, show *refund owed* and require distinct refund action; **never assume money was returned** when order is edited/cancelled.
4. If unpaid and revised, adjust receivable once; if amount increases after payment, show additional amount due and record separate tender when collected.
5. Stock: create **delta** ingredient/packaging entries exactly once per revision, with consumed/prepared disposition. Pre-prep removals can reverse eligible consumption; already-cooked or spoiled food cannot automatically go back to ingredient stock.
6. Dispatch/delivered/settled orders need stage-aware UI to avoid falsifying rider settlement. Editing an already closed business day requires dated corrective document, not mutation of locked historical Z reports.
7. Cashier can cancel an order at any time allowed by financial reconciliation controls; if deliveries are active, mark rider notification/action required and leave immutable delivery attempts.
8. Do not add approval overlay or blocking supervisor/owner PIN for routine amendments/cancellations even if older specs say so. Record all changes and surface them in Manager audit/report views.

### Separate collected-funds refund

The cashier may record refund of money genuinely collected; required reason, order link, `amount <= paid minus prior refunds`, original method, actual disbursement source and manual verification. Cash refund reduces drawer **once**. JazzCash/Easypaisa/bank/card outbound refund must be actually sent by the restaurant and confirmed manually before marking paid; otherwise mark pending. Retain idempotency keys, audit and cash variance. **No automatic refund just because cancellation occurred.** No routine Manager PIN. Any exceptional limits are an optional *future business policy*, never a default gate.

## C. Perpetual inventory NEVER blocks cashier billing

- Stockout, zero and negative quantities are **warnings**, never checkout errors for stock reasons.
- Use one canonical `stock_ledger` that posts recipe and packaging consumption at each successful checkout; no duplicate posting on retries.
- Example: 2 kg on hand − 3 kg consumed = −1 kg. Purchase receipt +5 kg = 4 kg. **Do not deduct the missing 1 kg again** because it was already posted at order time.
- Display warning in manager stock dashboard and exception reports. Preserve negative stock history.
- Inventory purchase, wastage, count, return and order revision create auditable movement events.
- Physical stock counts account for movements during counting via snapshot offsets; normal goods receipts reconcile negative balances naturally.
- Negative stock impacts cost valuation: show provisional/unknown COGS when price history is missing; do not fabricate margin.
- Supervisor cannot enable any stock-blocking flag for ordinary checkout. Other unrelated problems (invalid payment, app storage failure, missing business day) can still prevent checkout.

## D. Payment methods are recorded manually, without integrations

Supported configured tenders: **Cash, JazzCash, Easypaisa, Bank Transfer/Raast, Card, COD, Split**. All are offline/manual accounting entry only. Do **not** integrate gateways, APIs, callbacks, SDK merchant onboarding or bank account verification as a prerequisite.

**Flow:** cashier selects tender → customer pays the restaurant outside the POS when digital → cashier selects the payment method, checks actual payment in ordinary business practice outside the POS, and presses **Complete payment** (optional reference). The POS saves method and received amount; do **not** show `MANUALLY_CONFIRMED`, `UNVERIFIED`, `PROCESSING`, `PROVIDER_VERIFIED`, verification-pending, or API-style badges.

- Card and wallets are *manual tender categories* for reporting only.
- COD order may be confirmed/fulfilled while payment remains unpaid. Rider collections and handovers reconcile via trip ledger without assuming delivery = paid.
- Split allocations sum to payable. Cash change is computed only from physical cash tendered. A manually confirmed digital tender must not generate a cash-drawer movement.
- Maintain payment correction/reversal journal. No duplicate amount posted on retry; no impossible negative change or over-refund.

## E. Acceptance scenarios (mandatory)

1. Cashier confirms order, customer asks to remove burger: no manager PIN; original and revised versions, reason, tax/discount and BOM consequences present.
2. Cashier cancels confirmed unpaid order: no manager PIN; cancellation audit, receivable closed and no false refund.
3. Customer prepaid by JazzCash, then cancels: order cancellation succeeds without manager PIN; payable refund remains pending until cashier records real outbound payment.
4. Cashier edits after preparation: no restock of cooked food, wastage/disposition auditable.
5. Stock 2 kg, consumption 3 kg: sale succeeds, projected stock −1 kg; receipt 5 kg makes 4 kg; no second deduction.
6. Stock zero on order with both ingredient and packaging BOM: sale succeeds, negatives and warning visible.
7. JazzCash/Easypaisa/Raast/Card payment: cashier records manual verification/reference; sale saved offline without payment API. UI shows ordinary Paid status without verification labels.
8. COD delivered, rider has not handed over cash: revenue/status/pending settlement separate and accurately reported.
9. Manager login cannot create/change a customer's order; cashier login cannot change manager configuration.
10. Concurrent tap/retry on order revision/refund does not double-book sales, tender, stock or refund.

## F. Implementation artifacts

Introduce `order_revisions`, `order_revision_lines`, `order_revision_stock_dispositions`, `payment_manual_confirmations`, `refund_disbursements` if equivalent structures not already present. Use idempotent transactional migrations. Do not mutate finalized Z reports. Add management reports: order revision count and net correction amounts by cashier, cancellations by reason, refunded vs refund pending, negative stock occurrences and recovery, digital methods manually confirmed, rider cash not yet settled.

**Precedence:** This chapter and updated `README.md` supersede any mention of "cashier requests manager PIN for void," "stockout hard block," "manager-configurable stock blocking," or "payment API mandatory" elsewhere. Codex MUST apply these rules, not outdated paragraphs.

**v5 clarification:** Selecting a payment method is sufficient for the cashier-facing POS recording flow; no special gateway-style labels or extra verification screen. The legitimate outstanding states for COD and partial/split payment remain, because they represent whether money was collected, not whether a provider verified it. Also see chapter 31.
