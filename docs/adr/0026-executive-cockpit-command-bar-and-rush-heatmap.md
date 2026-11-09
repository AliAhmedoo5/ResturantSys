# Executive Cockpit, Two-Tier Command Bar & Rush Heatmap Matrix

## Context
Managers and business owners viewing `ManagerAnalyticsWorkspace` on 1366×768 laptop screens and POS touch displays faced severe vertical crowding: 9 form dropdowns and multi-line audit text consumed over 28% of the vertical viewport before any KPI card or chart was visible. Furthermore, `AnalyticsFamily.overview` presented flat, monochromatic cards and raw operational rows rather than processed commercial intelligence (margins, bottlenecks, and financial risk exposure), while the 24-hour peak order breakdown was rendered as an unwieldy 24-column horizontal-scrolling table.

## Decision
We established a responsive, executive-first workspace standard for the Manager Analytics portal:
1. **Executive Intelligence Cockpit**: `AnalyticsFamily.overview` is redesigned as a 4-pillar executive dashboard (Executive KPI Scorecard, Menu Margin Intelligence, Kitchen & Fulfillment Bottlenecks, and Risk & Leakage Radar) synthesizing high-level business health before presenting deep tabular ledgers.
2. **Two-Tier Command Bar**: The 9-dropdown header is replaced with:
   - **Tier 1 (View Pills)**: A horizontal segmented bar for the 4 primary daily operational families (`Overview`, `Sales`, `Cash & shifts`, `Order operations`) and a compact `More Reports` dropdown for the remaining 10 deep reports.
   - **Tier 2 (Presets & Responsive Filter Drawer)**: Date preset chips (`Live`, `Today`, `Yesterday`, `Last 7 Days`, `Last 30 Days`, `Custom`), an interactive audit provenance pill modal trigger, and a single `Filters` toggle opening a slide-over drawer for secondary criteria (Cashier, Shift, Dining Type, Payment Method, Rider, Supplier).
3. **7×24 Rush Heatmap Matrix**: The 24-column horizontal scroll table is replaced with a responsive $7 \times 24$ density matrix (Monday–Sunday × 00:00–23:00 in Asia/Karachi time) with a Cartel Yellow intensity gradient, cell tooltips (volume, net sales, ticket average), and tap-to-drilldown into contributing order tokens.
4. **Domain Accent Hierarchy & Proactive Balance Handling**: KPI cards feature domain-colored left-accent borders (`#FFC400` revenue/cash, `#10B981` orders/health, `#EF4444` risk/discrepancies, `#3B82F6` labor/delivery) and compact delta pills. Comparison mode is proactively disabled with an inline explanation when viewing snapshot-balance families.
5. **Responsive Fluidity**: Layout scales smoothly from 1366×768 laptops down to tablet widths using responsive grid wrapping (`LayoutBuilder`) and non-scrolling viewport boundaries.

## Consequences
- Reclaims ~180px of vertical space, ensuring all primary KPI scorecards and trend charts appear above the fold on 1366×768 displays.
- Business owners gain instantaneous visibility into profitability, peak kitchen rush windows, and cash risk without parsing raw transaction tables.
- Eliminates horizontal scrolling fatigue while preserving exact SQLite snapshot provenance and integer paisa precision.
