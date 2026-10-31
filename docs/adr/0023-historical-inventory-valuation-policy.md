# ADR-0023: Historical Inventory Valuation and Perpetual Negative Stock Policy (Moving WAC, Mandi Unit Snapshots, and COGS Separation)

- **Status**: Approved
- **Approver**: Financial Policy Board & Inventory Architecture Lead
- **Approval Date**: 2026-10-31
- **Governs**: Ticket #90 (closing #90), Specification #60
- **Implements**: Core valuation invariants prior to Ticket #91 implementation

---

## Context

Fast-food restaurant operations rely heavily on bulk perishable kitchen inventory (such as fresh chicken, beef patties, cooking oils, proprietary sauces, fresh produce) and takeout packaging (burger boxes, wrappers, cups, delivery bags). Managing and valuing this inventory in an offline-first desktop environment presents five fundamental operational and architectural realities:

1. **Impracticality of Physical FIFO and SQLite Row Explosion**:
   In commercial kitchen prep lines, cooks pour fresh sauce into squeeze bottles already containing previous batches, replenish fryers with cooking oil, and combine poultry batches in prep bins. Enforcing physical FIFO (First-In, First-Out) or Specific Identification is physically impossible for kitchen staff and architecturally disastrous in SQLite, where tracking microscopic individual FIFO consumption tranches across thousands of fast-food sales would trigger severe database row fragmentation and slow POS queries.

2. **Cashier Checkout Continuity and Soft Inventory Deduction (ADR-0002)**:
   Front-counter sales must never block, stall, or fail due to stock depletion. Under ADR-0002 (Soft Inventory Deduction), a cashier selling burgers during a lunch rush must complete orders smoothly even if the software inventory ledger indicates zero or negative stock. BOM ingredient consumption is posted immediately upon order confirmation.

3. **Timing Mismatch Between Physical Mandi Deliveries and Invoice Data Entry**:
   In Pakistani restaurant operations, fresh poultry and produce arrive from wholesale markets (*Sabzi Mandi* / wholesale vendors) in early morning hours before store opening. Line cooks immediately start marinating and cooking. The owner or purchasing manager often enters the vendor purchase invoice hours later in the afternoon or evening. During this operational lag, the system experiences **Perpetual Negative Stock**, where recipe consumption drives the on-hand quantity below zero prior to purchase invoice posting.

4. **Strict Immutability of Historical Sales COGS**:
   Historical sales transactions already snapshotted recipe BOM acquisition rates at the exact time of order confirmation (`order_items.bom_json` and `event_time`). Any changes to current inventory replacement costs or incoming vendor invoice prices must never retroactively recalculate or overwrite sealed past sales COGS.

5. **Pakistani Wholesale Mandi Units & Configuration Drift**:
   Wholesale commodities are purchased in traditional Pakistani volumetric and weight units (*Mann*, *Pao*, *Dharri*, *Bori*, *Darjan*, *Peti* / crates) while kitchen recipes consume in grams, milliliters, or individual pieces. If conversion ratios are altered in settings, past inventory receipts must remain completely immune to retroactive valuation drift.

Under [Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60) and [Ticket #90](https://github.com/AliAhmedoo5/ResturantSys/issues/90), this ADR establishes the definitive financial and inventory valuation policy governing Moving WAC, Perpetual Negative Stock, Sales COGS separation, Mandi unit snapshots, and historical coverage disclosures prior to implementing Ticket #91.

---

## Decision

### 1. Inventory Valuation Methodology: Moving Weighted Average Cost (WAC)
- **Methodology Selection**: Moving Weighted Average Cost (WAC) is adopted as the canonical inventory valuation policy across all ingredients and packaging items.
- **WAC Update Formula**:
  Upon the posting of each purchase receipt or procurement invoice, the new moving weighted average unit cost $\bar{C}_{\text{new}}$ is calculated as:
  $$\bar{C}_{\text{new}} = \frac{(Q_{\text{current}} \times \bar{C}_{\text{old}}) + (Q_{\text{purchase}} \times C_{\text{purchase}})}{Q_{\text{current}} + Q_{\text{purchase}}}$$
  Where:
  - $Q_{\text{current}}$ is the positive on-hand quantity prior to receipt.
  - $\bar{C}_{\text{old}}$ is the moving average unit cost prior to receipt.
  - $Q_{\text{purchase}}$ is the inbound quantity received.
  - $C_{\text{purchase}}$ is the unit cost of the inbound purchase.
- **Signed 64-Bit Integer Paisa Precision**:
  All financial amounts, line extensions, and inventory valuations are calculated and stored in signed 64-bit Integer Paisa (`100 paisa = PKR 1.00`), in accordance with ADR-0011 (Integer Paisa and Cash Rounding). Unit rates retain integer paisa precision; division uses integer floor truncation (`~/`) with half-up line total rounding to eliminate fractional paisa drift.

### 2. Perpetual Negative Stock Valuation Rule
- **Non-Blocking Checkout**: Cashier checkout never blocks on zero or negative stock. BOM consumption ledger rows post atomically upon order confirmation.
- **Negative Balance Asset Valuation**:
  - While an inventory line's on-hand quantity is negative ($Q < 0$), its balance-sheet inventory asset value is reported as **PKR 0.00** (or an accrued unbilled stock liability if liability reporting is requested). The system never reports negative asset values on the balance sheet.
  - The effective valuation unit cost remains pegged at the **Last Known Valid Unit Cost** ($\bar{C}_{\text{last}}$).
  - Valuation reports display an explicit quality transparency badge: `Estimated valuation: item in temporary negative balance`.
- **Delayed Receipt Reconciliation**:
  - When the delayed purchase invoice is posted (e.g., $+20\text{ kg}$ at Rs. 650.00/kg after stock dipped to $-5\text{ kg}$):
    1. The physical deficit of $5\text{ kg}$ is covered at the new invoice rate.
    2. The remaining $+15\text{ kg}$ establishes the positive on-hand asset balance at Rs. 650.00/kg ($15 \times 65,000 = 975,000\text{ paisa} = \text{PKR } 9,750.00$).
    3. No retroactive catch-up consumption or double-deduction is queued. The ledger reflects clean, non-blocking operational continuity.

### 3. Strict Separation: Acquisition-Rate Sales COGS vs. Inventory Valuation
- **Sales COGS Preserved**: Historical sales already snapshotted recipe BOM acquisition costs at the time of sale (`order_items.bom_json` and `event_time`). Past sales COGS is immutable and must **NEVER** be recalculated or overwritten when inventory unit costs change.
- **Inventory Quantity Bridge Reconciliation**:
  Historical inventory at cutoff $T_{\text{cutoff}}$ evaluates the quantity bridge:
  $$\text{Ending Qty} = \text{Opening Qty} + \text{Purchases} - \text{Sales BOM} - \text{Packaging} - \text{Wastage} \pm \text{Adjustments}$$
  $$\text{Valuation at } T_{\text{cutoff}} = \sum_{i} \left(\text{Ending Qty}_i \times \bar{C}_{i, T_{\text{cutoff}}}\right)$$
  - Operational inventory variance (shrinkage, unrecorded spillage, portion overages discovered during physical stock counts) is posted via signed physical count adjustments and distinct kitchen waste ledgers, completely decoupled from sales COGS.

### 4. Mandi Unit Conversion Snapshots
- Pakistani wholesale purchasing units must be converted to standard stock units (grams, milliliters, pieces) upon purchase invoice entry:
  - **Mann**: $40\text{ kg} = 40,000\text{ g}$
  - **Pao**: $250\text{ g}$
  - **Dharri**: $5\text{ kg} = 5,000\text{ g}$
  - **Bori**: $50\text{ kg} = 50,000\text{ g}$
  - **Darjan**: $12\text{ pcs}$
  - **Peti / Crate**: Item-specific piece or weight multiplier.
- **Snapshot Immutability**:
  The purchase invoice row permanently snapshots the exact conversion multiplier and base unit (`unit_multiplier`, `base_unit`) applied at the moment of invoice entry. Future configuration changes to unit definitions or packaging specs will never alter historical stock ledger quantities or purchase valuation.

### 5. Coverage and Unknown Cost Handling
- If an ingredient or packaging line lacks purchase cost evidence in early operational history, it is marked with `CostQuality.unknownCost`. The system will **never** silently default missing costs to zero (which would falsely inflate restaurant profits and misstate assets).
- Inventory valuation reports display an explicit coverage indicator:
  $$\text{Valuation Coverage} = \frac{\text{Active Lines with Verified Cost Evidence}}{\text{Total Active Lines in Scope}} \times 100\%$$
  Example display: `Valuation Coverage: 96% of active inventory lines`. Lines with unknown costs are highlighted for manager audit.

---

## Worked Acceptance Examples

### Example 1: Moving Weighted Average Cost Calculation
- **Opening Stock**:
  - $10\text{ kg}$ chicken at Rs. 600.00/kg ($60,000\text{ paisa/kg}$).
  - Total Opening Value: $\text{PKR } 6,000.00 = 600,000\text{ paisa}$.
- **Purchase Receipt**:
  - $20\text{ kg}$ chicken received at Rs. 660.00/kg ($66,000\text{ paisa/kg}$).
  - Total Purchase Invoice: $\text{PKR } 13,200.00 = 1,320,000\text{ paisa}$.
- **New On-Hand Quantity**:
  - $10\text{ kg} + 20\text{ kg} = 30\text{ kg}$.
- **New Moving WAC**:
  $$\bar{C}_{\text{new}} = \frac{600,000 + 1,320,000}{30} = \frac{1,920,000}{30} = 64,000\text{ paisa/kg} \quad (\text{Rs. } 640.00\text{/kg})$$
- **Total Asset Value**:
  - $30 \times 64,000 = 1,920,000\text{ paisa} = \text{PKR } 19,200.00$.

### Example 2: Perpetual Negative Stock & Late Mandi Purchase
- **Opening Stock**:
  - $2\text{ kg}$ beef patties at Rs. 800.00/kg ($80,000\text{ paisa/kg}$).
- **Rush Hour Sales**:
  - Lunch rush orders consume $5\text{ kg}$ of beef patties via BOM deductions.
  - Stock on hand dips to: $2\text{ kg} - 5\text{ kg} = -3\text{ kg}$.
  - Front-counter checkout continues without interruption or warning prompts.
- **Valuation During Negative Balance**:
  - On-hand asset value is reported as **PKR 0.00** (not $-\text{PKR } 2,400.00$).
  - Effective unit cost remains pegged at Last Known Valid Unit Cost: Rs. 800.00/kg.
  - Report displays badge: `Estimated valuation: item in temporary negative balance`.
- **Manager Enters Morning Mandi Purchase**:
  - Later in the day, the manager posts the morning Mandi invoice: $+15\text{ kg}$ at Rs. 850.00/kg ($85,000\text{ paisa/kg}$).
- **Reconciliation**:
  - Net on-hand stock reconciles cleanly to: $-3\text{ kg} + 15\text{ kg} = +12\text{ kg}$.
  - The deficit ($3\text{ kg}$) is absorbed at the incoming rate; the remaining positive on-hand quantity ($12\text{ kg}$) is valued at the new rate:
    $$\text{Asset Valuation} = 12 \times 85,000 = 1,020,000\text{ paisa} = \text{PKR } 10,200.00$$
  - No retroactive catch-up consumption is queued; no double-deduction occurs.

### Example 3: Sales COGS Immutability vs Inventory Valuation
- **Sale Time**:
  - Order #1005 sells 2 burgers, consuming $400\text{ g}$ of beef when the recorded unit cost is Rs. 800.00/kg (80 paisa/g).
  - Food COGS snapshotted in `order_items.bom_json`:
    $$\text{Food COGS} = 400 \times 80 = 32,000\text{ paisa} = \text{PKR } 320.00$$
- **Subsequent Purchase**:
  - Two days later, a bulk purchase arrives at Rs. 880.00/kg, updating the Moving WAC to Rs. 880.00/kg.
- **Audit Verification**:
  - Order #1005 Food COGS remains immutable at **PKR 320.00**.
  - Historical gross profit for that day remains completely unchanged.
  - Ending inventory on hand evaluates at the new Moving WAC rate of Rs. 880.00/kg.

### Example 4: Mandi Unit Snapshot Reconciled
- **Purchase Entry**:
  - Invoice recorded: $2\text{ Manns}$ of All-Purpose Flour at Rs. 4,800.00/Mann.
- **Conversion Snapshot**:
  - Multiplier snapshotted: $1\text{ Mann} = 40\text{ kg} = 40,000\text{ g}$.
  - Total base quantity: $2 \times 40,000\text{ g} = 80,000\text{ g}$ ($80\text{ kg}$).
  - Unit cost snapshotted:
    $$\frac{4,800.00}{40\text{ kg}} = \text{Rs. } 120.00\text{/kg} = 12,000\text{ paisa/kg} = 12\text{ paisa/g}$$
  - Stock ledger logs $+80,000\text{ g}$ at $12\text{ paisa/g}$.
- **Subsequent Configuration Change**:
  - If a manager later updates supplier packaging definitions (e.g., redefining a custom Mann or Peti), the historical invoice row retains its original $40\text{ kg/Mann}$ multiplier snapshot. Historical ledger integrity is preserved.

---

## Consequences

### Positive
- **Uninterrupted Operations**: Cashiers can sell continuously during lunch and dinner rushes without inventory soft-deductions ever halting checkout.
- **High Performance in SQLite**: Moving WAC requires storing only the running quantity and average unit cost per ingredient, eliminating the database bloat and query latency of physical FIFO lot splits.
- **Audit Defensibility**: Clear separation between immutable sales COGS and inventory asset valuation prevents retroactive rewriting of past financial reports and tax filings.
- **Localized Pakistani Procurement Support**: First-class support for Mandi purchasing units (*Mann*, *Dharri*, *Pao*, etc.) with row-level conversion snapshots protects against unit configuration drift.
- **Zero Financial Hallucination**: Unbilled stock liabilities and negative balances are badged transparently, and unknown costs are explicitly reported rather than masked as zero-cost inventory.

### Trade-offs
- Moving WAC blends cost fluctuations, slightly smoothing out rapid daily price volatility compared to exact specific lot tracking.
- Temporary negative balances require pegging unit costs to the Last Known Valid Unit Cost until manager invoice reconciliation is performed.
