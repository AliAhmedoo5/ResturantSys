**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 24 — Exhaustive role permissions matrix (v4)

**Authoritative:** exactly two application roles, **Cashier (C)** and **Supervisor/Owner = Manager (M)**. No separate Owner or Supervisor permission group. **M cannot perform cashier operations.** Every command enforces this in service layer, independent of routing and shortcuts. A separately authenticated manager may approve a cashier's request, but does not execute the cashier operation as themselves.

Notation: **Y** = allowed; **N** = denied; **P** = business-configured; **A** = may request action requiring Manager approval; **V** = view only.

| ID | Domain / Action | C | M | Implementation rule |
|---|---|:---:|:---:|---|
| AUTH-01 | PIN login and session lock | Y | Y | Active, unique credential |
| AUTH-02 | Create Cashier login | N | Y | PIN uniqueness and audit |
| AUTH-03 | Create another Manager login | N | Y | Same exact role, reauthentication |
| AUTH-04 | Reset/deactivate a staff PIN | N | Y | No PIN exposure |
| AUTH-05 | Configure auth, audit, backup policy | N | Y | High-risk confirmation |
| POS-01 | Create/edit an order cart | Y | N | M denied even via service |
| POS-02 | Add/remove item, modifiers and deals to cart | Y | N | Transaction is cashier-only |
| POS-03 | Hold, recall, abandon drafts | Y | N | Session/ownership rules |
| POS-04 | Customer phone lookup for billing and repeat order | Y | N | M may see management customer analytics only |
| POS-05 | Apply published discount to current bill | Y | N | Presets configured by M |
| POS-06 | Receive cash/card/wallet/split payment | Y | N | M cannot cashier checkout |
| POS-07 | Confirm bill/allocate daily token | Y | N | Shift open; atomic posting |
| POS-08 | Print/share customer receipt if later enabled | Y | N | No kitchen ticket feature |
| ORDER-01 | Update live prep/ready/out for delivery/delivered | Y | N | M oversight view only |
| ORDER-02 | Review any order and history | P | V | C own/assigned only |
| ORDER-03 | Edit/remove/change confirmed order items, modifiers, quantity | Y | N | No manager PIN; append revision/event + financial and inventory deltas |\n| ORDER-03B | Cancel confirmed order | Y | N | No manager PIN; mandatory reason, stage and stock disposition, audit |\n| ORDER-03C | Record a legitimate refund of collected funds | Y | N | No routine manager PIN; bounded by net paid/refundable amount; real tender movement and audit |
| ORDER-04 | Review order amendments/cancellations/refunds | N | Y | Post-facto oversight; no routine authorization step |
| DEL-01 | Assign rider/dispatch trip | P | N | C operational action |
| DEL-02 | Record failed delivery/redispatch | P | N | C operational action |
| DEL-03 | Receive rider COD cash at counter | P | N | C cashier shift event |
| DEL-04 | Review rider shortages/approve writeoff | N | Y | M managerial approval/adjustment |
| SHIFT-01 | Open own cashier shift and float | Y | N | Business day must be open |
| SHIFT-02 | Count and submit own blind closing drawer | Y | N | Hide expected until submission |
| SHIFT-03 | View/review shift reconciliation and variances | N | Y | M cannot submit C's count |
| DAY-01 | Open business day | N | Y | Manager workflow |
| DAY-02 | Close/lock business day, approve Z | N | Y | Manager workflow |
| MENU-01 | CRUD menu item/category/modifier | N | Y | Price/version audit |
| MENU-02 | CRUD deals and recipes/BOM | N | Y | Deactivate rather than delete referenced |
| MENU-03 | CRUD discount presets | N | Y | Eligible presets visible to cashier |
| STK-01 | CRUD raw ingredients and packaging | N | Y | Supplied item mappings |
| STK-02 | Stock purchases/receipts, transfers, wastage | N | Y | Append-only stock ledger |
| STK-03 | Physical counts and post adjustments | N | Y | Snapshot/reconciliation |
| SUP-01 | CRUD supplier and supplied catalog | N | Y | Arbitrary custom supplied items |
| SUP-02 | Record purchase on cash/credit | N | Y | Inventory and payable atomic |
| SUP-03 | Supplier payments/Khata and reversals | N | Y | Explicit payment source |
| CASH-01 | Pay in/out operational shift drawer | P | N | Cashier own shift; reason |
| CASH-02 | Create operational petty cash request | P | N | Configurable approval policy |
| CASH-03 | CRUD expense categories | N | Y | Archive if used |
| CASH-04 | Create/approve/void administrative expense | N | Y | Management ledger action |
| STAFF-01 | CRUD employee profile/department | N | Y | Archive linked history |
| STAFF-02 | Manage monthly salary, advances, ledger | N | Y | Reverse posted errors |
| STAFF-03 | Create Manager PIN/account | N | Y | Same Manager role, extra confirmation |
| REP-01 | Own shift summary | P | N | Only appropriate operational figures |
| REP-02 | All financial/profitability reports | N | Y | Filters/export/revisions |
| REP-03 | Generate/email/WhatsApp daily report | N | Y | Approved recipients and durable outbox |
| SET-01 | Shortcut/quick-action layout config | N | Y | C may invoke only cashier actions |
| SET-02 | Feature flags/general settings | N | Y | Do not erase in-flight/history |
| SEC-01 | View audit and security incidents | N | Y | Confidential |
| SEC-02 | Edit/delete audit rows | N | N | Impossible |
| FIN-01 | Silently delete posted ledger or historic order | N | N | Reverse/adjust with traceability |

## Navigation and independent execution

**Cashier application shell:** Cashier POS, Held Orders, Customer Lookup, Live Orders/Delivery, Rider Handover, Own Cash Shift/Count, limited own activity. No management shortcuts in this shell.

**Supervisor/Owner (Manager) shell:** Overview/Exceptions, Menu & Deals, Discounts, Inventory/Packaging, Suppliers & Khata, Expense Categories/Management Cash, Employees/PIN/Payroll, Shift Reconciliation, Business Day Close, Reporting/Exports, Report Distribution, Settings/Shortcut Builder, Security/Backup/Audit. **No POS checkout or cart.** Manager may inspect orders read-only to investigate and approve.

**Approval:** Ordinary confirmed-order edits, removals and cancellations **do not use an approval overlay**. Cashier performs and the system audits; Manager reviews after the fact. A distinct escalation flow, if later configured for exceptional financial cases, is not part of routine order editing/cancellation. Approval is not a role switch. Manager may reject and no posting occurs. Where dual-control between two distinct managers is required, specify a second Manager account; Supervisor/Owner label does not create a separate tier.

## Mandatory negative tests

- M cannot start cashier shift, sell products, confirm checkout, record live rider cash, hold order, edit cart, or trigger POS hotkey.
- C cannot use direct service, keyboard shortcut, deep link or hidden route to edit stock/menus/supplier/expense categories/roles.
- Manager creates another Manager with same privileges; no separate Owner screen/role appears.
- M can create, edit and archive expense category, menu, deal and supplier records; linked financial records remain immutable.
- Cashier confirmed-order amendment and cancellation proceed without manager PIN and record every change; any actual refund stays bounded and traceable.\n- An exceptional manager approval, where later configured, never changes cashier identity or duplicates posting.


## v7 additional role permissions

| Action | Cashier | Manager (Supervisor=Owner) | Rule |
|---|---|---|---|
| Enter items into draft cart | Yes | No | No token yet |
| Open customer-details step and select/create customer/address | Yes | No | Order operation |
| Select serviceable delivery area | Yes | No | Must be enabled/allowed at final commit |
| Override unavailable area or alter fee | No | No as part of cashier sale | Manager can adjust zone policy from settings; Cashier must reselect |
| Create, edit, enable/disable, archive delivery area | No | Yes | Audit, preserve historical snapshot |
| Upload/replace/reorder/delete menu item photos | No | Yes | Optional, secure offline gallery |
| Upload/replace/reorder/delete deal photos | No | Yes | Optional, recipe separately mandatory |
| Confirm order after details and payment | Yes | No | Atomic order+customer+token+stock+tender posting |
