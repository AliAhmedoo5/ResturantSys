# ADR-0021: Line-Level Sales and Cost Allocation Policy (Menu Items, Deals, Modifiers, Discounts, Taxes, and Margins)

- **Status**: Approved
- **Approver**: Financial Policy Board & System Architecture Lead
- **Approval Date**: 2026-10-30
- **Governs**: Ticket #87 (closing #87), Specification #60
- **Implements**: Core allocation invariants prior to Ticket #88 implementation

## Context
Restaurant analytics and menu engineering require defensible line-level profitability, net sales, food cost, and contribution margin metrics. In daily fast-food operations, orders consist of diverse menu items, deal bundles, modifier add-ons, order-level discounts (percentage discounts, pre-approved coupons, manual supervisor overrides), provincial sales taxes, delivery surcharges, and order revisions.

Historically, naive POS reporting suffered from five core defects:
1. **Unallocated Discounts & Inflated Item Margins**: Order-level discounts were subtracted only from global order totals while individual item lines were shown at full gross catalog prices. This severely overstated item profitability and distorted menu mix decisions.
2. **Floating-Point Leakage & Invented Money**: Naive floating-point division of discounts resulted in fractional paisa rounding errors where the sum of line items did not equal the customer receipt total, violating ADR-0011 (Integer Paisa and Cash Rounding).
3. **Deal Black-Box Invisibility**: Combo meals and deals were treated either as single monolithic lines without ingredient costing, or constituent items were assigned arbitrary costs without reconciled revenue shares.
4. **Conflating Standard BOM Cost with Global Acquisition Spend**: Systems either claimed global Cost of Goods Sold (COGS) was completely absent, or incorrectly attempted to reprice historical sales by fluctuating current inventory unit rates, rewriting past profits.
5. **Silent Retroactive Backfilling**: Upgrades silently guessed or fabricated discount splits on legacy orders that were closed before line-allocation ledgers existed, corrupting sealed report auditability.

Under [Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60) and [Ticket #87](https://github.com/AliAhmedoo5/ResturantSys/issues/87), this document establishes the approved human policy governing line-level sales, discount allocation, tax carve-outs, deal expansion, revision handling, cost reconciliation, and legacy coverage prior to implementing [Ticket #88](https://github.com/AliAhmedoo5/ResturantSys/issues/88).

---

## Decision

### 1. Integer Paisa Arithmetic & Zero-Leak Rounding Residual Policy
- All sales, discounts, taxes, fees, and costs are calculated and stored in **signed 64-bit Integer Paisa** (`100 paisa = PKR 1.00`).
- Line-level allocations must reconcile exactly to order-level totals without generating or losing a single paisa:
  $$\sum_{i=1}^{n} \text{line\_allocated\_discount\_paisa}_i = \text{order\_discount\_paisa}$$
  $$\sum_{i=1}^{n} \text{line\_net\_sales\_paisa}_i = \text{order\_net\_sales\_paisa} = \text{order\_subtotal\_paisa} - \text{order\_discount\_paisa}$$
- **Proportional Allocation Formula**:
  For an order with gross subtotal $S = \sum_{i=1}^n g_i$ (where $g_i$ is line $i$'s gross value in paisa) and total order discount $D$ in paisa:
  $$\text{raw\_discount}_i = \frac{g_i}{S} \times D$$
  $$\text{base\_discount}_i = \lfloor \text{raw\_discount}_i \rfloor$$
- **Rounding Residual Distribution**:
  The integer floor division produces a non-negative rounding residual:
  $$\Delta = D - \sum_{i=1}^n \text{base\_discount}_i \quad (0 \le \Delta < n)$$
  The residual $\Delta$ paisa is distributed by adding exactly 1 paisa to the lines with the highest gross subtotal $g_i$. If multiple lines have identical gross subtotals, ties are broken deterministically by lowest line item ID / cart sequence index.
- Net sales for line $i$ is defined as:
  $$\text{line\_net\_sales\_paisa}_i = g_i - \text{final\_discount}_i$$

### 2. Tax Carve-Out and Surcharge Allocation
- Under ADR-0017 (0% Tax-Inclusive Pricing Default and Carve-Out), menu prices default to tax-inclusive.
- When an applicable sales tax rate ($R_{\text{bps}}$ in basis points) is enabled:
  $$\text{order\_tax\_paisa} = \left\lfloor \frac{\text{order\_net\_sales\_paisa} \times R_{\text{bps}}}{10000 + R_{\text{bps}}} + 0.5 \right\rfloor$$
- Line-level tax is carved out proportionally from taxable line net sales using the same integer floor plus largest-line residual algorithm.
- Non-food fees (such as delivery surcharges or platform fees) are attributed to dedicated service fee line types and are strictly excluded from food line-item margins.

### 3. Deal and Combo Component Expansion
- A Deal is recorded at checkout with a package selling price, an assigned deal ID, and a snapshotted list of selected menu items and choices (`deal_choices_json`).
- In high-level sales summaries, Deals may be displayed as a distinct package category.
- For menu engineering, ingredient consumption, and line margin reporting, the Deal package price is expanded across its constituent component items based on their standalone catalog regular menu prices ($p_1, p_2, \dots, p_k$):
  $$\text{component\_gross\_share}_j = \left\lfloor \frac{p_j}{\sum_{m=1}^k p_m} \times \text{deal\_price\_paisa} \right\rfloor$$
- Any integer rounding residual from the package expansion is allocated to the component with the highest standalone menu price $p_j$.
- If an order-level discount is also applied to an order containing a Deal, the Deal line first receives its allocated discount, and the resulting deal net sales is expanded across its components.
- Each expanded component item is linked to its recipe Bill of Materials (BOM) to compute accurate item contribution margins:
  $$\text{component\_contribution\_margin\_paisa} = \text{component\_net\_sales\_paisa} - \text{component\_bom\_cost\_paisa}$$

### 4. Modifiers and Add-On Pricing and Costing
- Modifiers (extra cheese, double patty, special sauce) are permanently attached to their parent line item in `order_items` via `modifiers_json`.
- The price of a paid modifier is included in the line item's gross price $g_i$.
- Modifier ingredient quantities are snapshotted into the line item's BOM (`bom_json`), ensuring modifier costs flow directly into the line's standard food cost.

### 5. Order Revisions, Item Voids, and Returns
- Per ADR-0010 (Cashier Order Revision and Trip Lock), post-print revisions and cancellations are append-only and never overwrite existing database rows.
- When an item is voided or returned during an authorized revision:
  1. Unmodified items preserve their original locked allocations.
  2. The removed item receives an explicit **Contra-Allocation Line** that negates its gross sales, allocated discount, carved-out tax, and recipe BOM cost:
     $$\Delta \text{gross} = -g_{\text{void}}, \quad \Delta \text{discount} = -d_{\text{void}}, \quad \Delta \text{net} = -(g_{\text{void}} - d_{\text{void}})$$
  3. Any newly added item receives an independent line allocation computed from the incremental revision delta.
  4. If an entire order is voided or refunded, all line allocations are fully reversed via contra-entries.

### 6. Standard BOM Recipe Cost vs. Global Acquisition Spend Reconciliation
- **Line Standard Food Cost**: Computed using the immutable ingredient quantities snapshotted in `order_items.bom_json` and standard ingredient unit costs recorded in `ingredient_cost_history` at the time of sale.
- **Global Acquisition COGS**: The actual expenditure on raw materials recorded in `mandi_procurements` and `vendor_transactions` (type `PURCHASE_CREDIT`).
- **Policy on Reconciliation**:
  - The system recognizes both metrics as legitimate, complementary views of restaurant economics.
  - Standard BOM Cost measures theoretical menu kitchen performance based on portion control standards.
  - Global Acquisition Spend measures actual cash and credit commitments to suppliers.
  - The variance between total standard BOM cost and total purchase spend is explicitly categorized in reporting as **Operational Inventory Variance** (comprising price variance, kitchen wastage from `kitchen_wastage`, portion overages, and shrinkage discovered during physical stock counts).
  - Reports must never claim that global COGS is missing; nor may they replace historical sale-time recipe costs with subsequent supplier delivery prices.

### 7. Legacy Unallocated Orders and Historical Coverage Disclosure
- Historical orders created prior to the deployment of line-level discount and tax allocation tables possess valid order-level totals (`subtotal`, `discount_amount`, `grand_total`) and unallocated item quantities, but lack per-line discount allocations.
- In accordance with ADR-0001 (Standalone SQLite Storage) and ADR-0008 (In-Place SQLite Evolution):
  - **No Retroactive Estimation**: The system will **never** guess or backfill hypothetical line discounts onto legacy closed orders.
  - **Explicit Coverage Disclosure**: All line-level sales and margin reports MUST state the exact coverage ratio:
    $$\text{Allocation Coverage} = \frac{\text{Orders with Verified Line Allocations}}{\text{Total Orders in Selected Period}}$$
  - **Legacy Unallocated Bucket**: On reports spanning historical legacy periods, aggregate order discounts from unallocated orders are presented in a dedicated summary row: `"Legacy Unallocated Order Discounts"`. This guarantees that global net sales always reconcile exactly with order receipts without falsifying item-level historical performance.

---

## Worked Acceptance Examples

### Example 1: Multi-Item Order with 15% Discount and Rounding Residual
- **Order #2001**:
  - Item 1: Beef Burger (Gross PKR 650.00 = 65,000 paisa)
  - Item 2: Loaded Fries (Gross PKR 350.00 = 35,000 paisa)
  - Item 3: Soft Drink (Gross PKR 120.00 = 12,000 paisa)
  - Order Gross Subtotal = $65,000 + 35,000 + 12,000 = 112,000\text{ paisa}$ (PKR 1,120.00).
  - 15% Student Discount applied:
    $$\text{Discount} = \lfloor 112,000 \times 0.15 \rfloor = 16,800\text{ paisa (PKR 168.00)}$$
- **Proportional Allocation**:
  - Item 1 (Burger):
    $$\text{raw}_1 = \frac{65,000}{112,000} \times 16,800 = 9,750.00 \implies \text{base}_1 = 9,750\text{ paisa}$$
  - Item 2 (Fries):
    $$\text{raw}_2 = \frac{35,000}{112,000} \times 16,800 = 5,250.00 \implies \text{base}_2 = 5,250\text{ paisa}$$
  - Item 3 (Drink):
    $$\text{raw}_3 = \frac{12,000}{112,000} \times 16,800 = 1,800.00 \implies \text{base}_3 = 1,800\text{ paisa}$$
  - Sum of base discounts = $9,750 + 5,250 + 1,800 = 16,800\text{ paisa}$. Residual $\Delta = 0\text{ paisa}$.
- **Net Sales Reconciliation**:
  - Burger Net Sales = $65,000 - 9,750 = 55,250\text{ paisa}$ (PKR 552.50).
  - Fries Net Sales = $35,000 - 5,250 = 29,750\text{ paisa}$ (PKR 297.50).
  - Drink Net Sales = $12,000 - 1,800 = 10,200\text{ paisa}$ (PKR 102.00).
  - Total Line Net Sales = $55,250 + 29,750 + 10,200 = 95,200\text{ paisa}$ (PKR 952.00).
  - Order Net Total = $112,000 - 16,800 = 95,200\text{ paisa}$ (Exact 100% reconciliation).

### Example 2: Flat PKR 100 Discount Generating Non-Zero Rounding Residual
- **Order #2002**:
  - Item 1: Club Sandwich (Gross PKR 450.00 = 45,000 paisa)
  - Item 2: Mineral Water (Gross PKR 70.00 = 7,000 paisa)
  - Item 3: Fresh Juice (Gross PKR 250.00 = 25,000 paisa)
  - Gross Subtotal = $45,000 + 7,000 + 25,000 = 77,000\text{ paisa}$ (PKR 770.00).
  - Flat Voucher Discount = PKR 100.00 = 10,000 paisa.
- **Proportional Allocation**:
  - Item 1: $\frac{45,000}{77,000} \times 10,000 = 5,844.1558 \implies \text{base}_1 = 5,844\text{ paisa}$.
  - Item 2: $\frac{7,000}{77,000} \times 10,000 = 909.0909 \implies \text{base}_2 = 909\text{ paisa}$.
  - Item 3: $\frac{25,000}{77,000} \times 10,000 = 3,246.7532 \implies \text{base}_3 = 3,246\text{ paisa}$.
  - Sum of base discounts = $5,844 + 909 + 3,246 = 9,999\text{ paisa}$.
  - Rounding Residual $\Delta = 10,000 - 9,999 = 1\text{ paisa}$.
- **Residual Assignment**:
  - Item 1 has the largest gross subtotal (45,000 paisa).
  - Item 1 receives $+1\text{ paisa} \implies \text{final\_discount}_1 = 5,845\text{ paisa}$ (PKR 58.45).
  - Item 2 final discount = 909 paisa (PKR 9.09).
  - Item 3 final discount = 3,246 paisa (PKR 32.46).
  - Sum of final discounts = $5,845 + 909 + 3,246 = 10,000\text{ paisa}$ (PKR 100.00).
- **Net Sales**:
  - Item 1: $45,000 - 5,845 = 39,155\text{ paisa}$ (PKR 391.55).
  - Item 2: $7,000 - 909 = 6,091\text{ paisa}$ (PKR 60.91).
  - Item 3: $25,000 - 3,246 = 21,754\text{ paisa}$ (PKR 217.54).
  - Sum of net sales = $39,155 + 6,091 + 21,754 = 67,000\text{ paisa}$ (PKR 670.00).
  - Exactly equals Order Total: $77,000 - 10,000 = 67,000\text{ paisa}$. Zero paisa leaked.

### Example 3: Deal Expansion with 3 Components and Recipe BOM Costing
- **Order #2003**: Customer orders "Zinger Combo Deal" for PKR 850.00 (85,000 paisa).
  - Combo components:
    - Component A: Zinger Burger (Standalone catalog price = PKR 550.00 = 55,000 paisa; Recipe BOM cost = PKR 220.00 = 22,000 paisa).
    - Component B: Regular Fries (Standalone catalog price = PKR 250.00 = 25,000 paisa; Recipe BOM cost = PKR 70.00 = 7,000 paisa).
    - Component C: Drink (Standalone catalog price = PKR 150.00 = 15,000 paisa; Recipe BOM cost = PKR 45.00 = 4,500 paisa).
  - Sum of standalone prices = $55,000 + 25,000 + 15,000 = 95,000\text{ paisa}$ (PKR 950.00).
- **Deal Expansion Allocation** (Deal Selling Price = 85,000 paisa):
  - Component A: $\frac{55,000}{95,000} \times 85,000 = 49,210.52 \implies \text{base}_A = 49,210\text{ paisa}$.
  - Component B: $\frac{25,000}{95,000} \times 85,000 = 22,368.42 \implies \text{base}_B = 22,368\text{ paisa}$.
  - Component C: $\frac{15,000}{95,000} \times 85,000 = 13,421.05 \implies \text{base}_C = 13,421\text{ paisa}$.
  - Base sum = $49,210 + 22,368 + 13,421 = 84,999\text{ paisa}$.
  - Residual $\Delta = 85,000 - 84,999 = 1\text{ paisa}$, assigned to Component A (highest standalone price).
  - Final Expanded Net Sales:
    - Component A (Zinger): 49,211 paisa (PKR 492.11).
    - Component B (Fries): 22,368 paisa (PKR 223.68).
    - Component C (Drink): 13,421 paisa (PKR 134.21).
    - Sum = 85,000 paisa (PKR 850.00).
- **Component Contribution Margins**:
  - Component A Margin: $49,211 - 22,000 = 27,211\text{ paisa}$ (PKR 272.11, 55.29%).
  - Component B Margin: $22,368 - 7,000 = 15,368\text{ paisa}$ (PKR 153.68, 68.71%).
  - Component C Margin: $13,421 - 4,500 = 8,921\text{ paisa}$ (PKR 89.21, 66.47%).
  - Overall Deal Margin: $85,000 - 33,500 = 51,500\text{ paisa}$ (PKR 515.00, 60.59%).

### Example 4: Order Revision with Void and Contra-Allocation
- **Order #2004**:
  - Originally ordered: 2 Pizzas @ PKR 1,000 = 200,000 paisa, with a PKR 20,000 discount (Net = 180,000 paisa, 90,000 paisa each).
  - During kitchen preparation, customer changes mind and cancels 1 Pizza.
  - Cashier performs authorized Order Revision (ADR-0010):
    - Locked original line item remains unchanged.
    - An append-only delta line is recorded:
      - Quantity: -1
      - Gross Delta: -100,000 paisa
      - Contra-Discount: -10,000 paisa
      - Net Sales Delta: -90,000 paisa
      - Contra-BOM Recipe Cost: -40,000 paisa
    - Revised Order Net Total: $180,000 - 90,000 = 90,000\text{ paisa}$.
  - Audit trail retains both the original allocation and the contra-allocation; net reporting matches the actual final delivery.

---

## Consequences

### Positive
- Eliminates distorted item profitability by attributing discounts and carve-out taxes down to each line item with exact mathematical precision.
- Enforces Integer Paisa consistency, eliminating floating-point reconciliation errors across orders and line items.
- Enables deep menu engineering on combo meals and deals through transparent component expansion.
- Preserves the integrity of closed legacy orders and sealed Z-Reports by using explicit coverage disclosure rather than fabricated history.
- Reconciles standard recipe BOM food costs with global acquisition expenditures through an explicit operational variance bridge.

### Trade-offs
- Reporting queries must aggregate allocated line amounts and handle legacy unallocated rows in separate summary groups.
- Deal expansion requires catalog items to maintain valid standalone menu prices for weight calculations.
