# 31 — Final mandatory recipe and simplified payments policy (v5)

**Confirmed 12 October 2026. THIS CHAPTER OVERRIDES conflicting statements in Chapters 00–30.**

## 1. Every sellable menu item requires a recipe (BOM)

A Manager (Supervisor/Owner, same permission role) must define the complete ingredient recipe when creating a menu item. The recipe defines ingredients, quantities, compatible measurement units, modifiers/variants and stock usage. The menu item cannot be **active, published, visible or sold** without a validated recipe.

- **Draft exception:** Manager may save an *inactive draft* while composing it, but cannot activate it or sell it without a valid BOM. This is for editing convenience, not a sale override.
- **Mandatory recipe gate is backend-enforced**, not just a disabled Flutter button.
- Every variant/size that changes ingredient consumption must have a defined recipe delta.
- Packaging BOM per order mode remains additive and configured; packaging inventory can be negative without halting sale.
- If the business explicitly configures a legitimate non-stock-bearing menu line (e.g., service fee), require a named non-stock classification and rationale. No accidental blank recipe.
- All recipe versions are immutable for historical order reconstruction. Editing creates a new version; older confirmed orders retain original snapshot.

## 2. Every sellable deal also requires a valid expanded recipe

A deal is not an exception. When Manager creates/edits a deal, it must include the complete composed BOM for **all included items and allowed choices**, quantities, modifiers, upgrades and extra packaging. Deal component item recipes must each be valid. Preview aggregate ingredient usage before activation. A missing recipe on **any selectable path** blocks publishing the deal until fixed.

**Deduction must happen once:** On successful cashier order commit, expand the actual selected deal to its constituent recipe components; write stock ledger entries once using stable order/revision IDs. Never deduct ingredient quantities from both a top-level deal BOM and its children again. For a removed/decreased component later, apply only the incremental stock correction with stage-aware cooked/wastage disposition.

## 3. Critical distinction: configuration vs available stock

| Condition | Result |
|---|---|
| Menu/deal recipe missing or invalid | Cannot activate/publish/sell configuration |
| Item recipe complete but ingredient quantity = 0 | Cashier sale continues; record negative stock + alert |
| Item recipe complete but stock is already negative | Cashier sale continues; more stock consumption recorded once |
| New stock arrives after negative balance | Add new receipt; balance automatically nets; **no catch-up second deduction** |

## 4. Cashier payment screen: just methods, no provider statuses

Methods: **Cash · JazzCash · Easypaisa · Bank/Raast · Card · COD · Split**. Cashier chooses the method, fills amount/change where applicable, optionally a reference, and presses **Complete payment**. No official APIs, SDKs, gateways, webhooks, external payment checks inside POS, or secondary provider confirmation.

**DO NOT DISPLAY:** `Unverified`, `Processing`, `Verification pending`, `Awaiting provider`, `Manual confirmation required`, `MANUALLY_CONFIRMED`, `PROVIDER_VERIFIED`, `API connected` or any equivalent payment badge suggesting gateway verification.

**Permitted business/accounting states only:** `Paid`, `Unpaid`, `Partially paid`, `Refunded`, `Refund due` where real financial balances require them. COD shows `Collection due` until the rider/customer pays; split shows remaining amount as appropriate. Ordinary saved electronic sale is displayed simply as **Paid** because cashier selected and recorded it. The POS itself cannot independently prove that an external transfer arrived—reporting and audits capture the cashier, method, amount, timestamp and optional reference.

Payment method selection is **not the same** as default marking COD paid. Preserve rider trip cash handovers and electronic payment/cash drawer separation. Refund must still reflect actual returned money, not merely an order cancellation.

## 5. Role effects

Only **Manager** creates/edits/activates recipes/menu/deals. Only **Cashier** enters checkout/takes customer payments. Manager cannot make bills or operate cashier sessions. Cashier cannot change recipe/BOM to get around recipe completeness. Manager can inspect product and payment audit data.

## 6. QA scenarios

1. Create Burger without recipe → inactive draft saved; cannot activate. Add Bun 1 pc, Patty 150g, Sauce 20g; now activation works.
2. Create Family Deal including Burger and Fries but Fries recipe missing → cannot activate even though Burger is complete.
3. Deal with alternative drink choices → all choices require valid product recipe or explicit non-stock classification; correct chosen option only is deducted.
4. Burger recipe requires 150g but inventory is 0g → bill succeeds, stock -150g, warning recorded; new delivery +1000g yields 850g.
5. Cashier completes JazzCash/Easypaisa/Raast/Card method payment → one step, shows `Paid`; no unverified/processing badges, no gateway calls.
6. Cashier confirms COD → keeps payment due; rider handover and collections reconcile separately.
7. Editing recipe after historical sales → past stock movements, food cost and original bill remain based on immutable prior recipe.
