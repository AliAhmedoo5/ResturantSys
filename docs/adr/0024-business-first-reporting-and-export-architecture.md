# Business-First Reporting & Export Architecture

## Context
Restaurant owners and business managers found CSV, Excel, and PDF reports difficult to read because the export engines prepended 30–40 rows of technical developer metadata (UTC timestamps, schema versions, sample counts, query parameters), printed raw internal debug strings (`[complete]`, `[estimated]`, `sourceType`), presented numbers in unformatted integer paisa, and lacked executive summaries or visual hierarchy.

## Decision
We established a business-first presentation standard across all Manager Analytics and End-of-Day Z-Close reports:
1. **Executive-First Presentation**: Every report opens with a 6-card Key Performance Indicator (KPI) grid (Net Sales, Order Count & AOV, Cash vs. Digital Collections, Gross Profit & Margin %, Food Cost % BOM, and Cash Discrepancy & Wastage).
2. **Metadata & Provenance Isolation**: All technical system provenance, UTC audit timestamps, checksum hashes, and query filters are isolated to a dedicated trailing sheet (`Audit & Metadata`) in Excel and an Appendix page in PDF.
3. **Clean CSV Standard**: CSV exports strictly begin on Row 1 with clean, human-readable column headers, omitting all multi-row metadata preambles to ensure instant compatibility with Excel, Google Sheets, and PowerBI.
4. **Native Currency & Dynamic Formulas**: All monetary cells store decimal Rupees (e.g., `12450.00`) with OpenXML currency formatting (`PKR #,##0.00`) and emit dual formula-and-value tags (`<f>SUM(...)</f><v>...</v>`), eliminating formula-breaking integer paisa or text concatenations.
5. **Hierarchical Categorization**: Item sales are grouped by Menu Category with bold subtotal rows before item details.
6. **Plain-Language Footnoting**: Data uncertainty, estimation badges, and sample coverage are communicated via asterisked business footnotes below tables instead of raw engineering enum strings.
7. **Visual Polish**: Professional Dark Slate (`#1E293B`) headers, Warm Amber (`#D97706`) accents, soft zebra striping (`#F8FAFC`), frozen header rows in Excel, and standardized A4 Landscape layout in PDF.

## Consequences
- Business owners can quickly evaluate restaurant performance from high-level KPI cards and category subtotals without parsing developer jargon.
- Spreadsheet users can sort, filter, and apply native formulas (`=SUM()`) directly without cleaning up corrupted header rows or text-formatted numbers.
- Full regulatory and audit provenance is strictly preserved without obstructing operational readability.
