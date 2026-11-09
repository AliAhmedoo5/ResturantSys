# Eight-Domain Executive Z-Report Standard

## Context
When closing a Business Day, the system generates an end-of-day Z-Report (in PDF and Excel formats) stored in the immutable reports directory and dispatched via the offline outbox. Previously, the report was serialized as a series of flat developer tables lacking domain grouping, delivery fulfillment SLA metrics, labor productivity indicators, operating expense classifications, and visual brand styling. When a domain had zero events (such as zero kitchen wastage), it produced ambiguous or blank tables.

## Decision
We established the Eight-Domain Executive Z-Report Standard for all Business Day close reports:
1. **Canonical Eight-Domain Structure**:
   - **Domain 1 (Executive Dashboard)**: Headline KPI scorecard (Net Sales, Counted Cash, Net Cash Variance, Digital/COD Collections, Overheads, Wastage Loss) with Business Day and manager provenance.
   - **Domain 2 (Cashier Shift Reconciliation)**: Detailed shift floats, collections, pay-outs, expected vs. counted cash, discrepancies, and audit statuses, alongside a full cash movement log.
   - **Domain 3 (Sales Channel & Tender Split)**: Orders, food sales, and delivery fees segmented by Dining Type (Dine-In, Takeaway, Delivery) and payment methods.
   - **Domain 4 (Delivery & Rider Fulfillment)**: Rider trips, dispatch-to-settlement durations, and pouch COD cash reconciliation.
   - **Domain 5 (Labor & Attendance Productivity)**: Verified staff attendance, net hours worked, and productivity ratios (sales/hr, orders/hr).
   - **Domain 6 (Kitchen Production & Stock Bridge)**: Ingredient BOM depletions, Mandi wholesale inward, and itemized kitchen wastage incidents.
   - **Domain 7 (Overheads, Payroll & Vendor Khata)**: Operating expenses categorized by funding source (`OWNER` vs `DRAWER`), staff payroll accruals, and supplier ledger settlements.
   - **Domain 8 (Overall Financial Position & Safe Handover)**: Comprehensive till cash reconciliation, master safe deposit verification, and manager sign-off seal.
2. **Zero-Activity Audit Badges**: Operational domains with zero recorded events explicitly render a clean audit confirmation badge (e.g., `Zero kitchen wastage recorded (Rs. 0.00 loss)`) rather than being omitted or rendering broken tables.
3. **Crunch Cartel Brand Theme**: Standardized high-contrast visual hierarchy utilizing Dark Slate (`#1E293B`) table headers, Warm Amber (`#D97706`) accents, soft background zebra striping (`#F8FAFC`), and explicit currency formatting (`Rs. #,##0.00`).
4. **Excel Worksheet Sanitization**: All OpenXML sheet names are strictly sanitized against invalid characters (`/`, `\`, `?`, `*`, `[`, `]`, `:`) and clamped to 31 characters to guarantee native Microsoft Excel compatibility.

## Consequences
- Business owners and managers receive an executive statement that mirrors the comprehensive financial and operational reality of the restaurant.
- Full mathematical reconciliation between register drawers, delivery pouches, kitchen consumption, and supplier debt is presented in a single, unalterable document.
- Zero-activity domains are honestly verified without ambiguity.
