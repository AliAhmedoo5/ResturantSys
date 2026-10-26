# Comprehensive Manager Portal analytics

Status: implementation specification, 26 October 2026.
User scope: live and historical data, analytics, calculations and statistics across every aspect of the recorded business. All four public test boundaries below were confirmed by the user.

## Authority and scope

Implement the comprehensive reporting surface defined by master chapters `12-reports-owner-analytics-exports.md` and `21-analytics-measure-definitions.md`, respecting later chapters and ADRs. Use the existing SQLite/controller architecture (ADR-0008), Manager authorization (ADR-0009), Business Days (ADR-0003), Integer Paisa (ADR-0011), and separate COD collection/delivery (ADR-0016).

The delivered dashboard covers every persisted operational domain. Do not invent missing history or introduce an entire payroll/accounting subsystem to make a chart appear populated. Each report family must exist, with usable metrics from recorded facts and explicit missing-data explanations for unsupported calculations. Supporting new financial posting modules is separate work; it must not be disguised as completed analytics. This specification does not supersede the wider production requirements in chapter 12.

## Experience

- Add Dashboard to the Manager Portal. Keep the existing staff/settings/reports workflows accessible and preserve their initial behavior for compatibility.
- Dashboard contains Overview and a report explorer with the 13 families below, live mode, Business Day/date-range selection, preceding-period comparison, relevant filters, KPI cards, a labeled sales trend with table alternative, sortable/paged detail rows, and source detail.
- Live means the local installation's committed SQLite facts, refreshed automatically while visible (30 seconds) and manually, with last-successful-refresh time. It does not imply cross-device/cloud synchronization. Prevent overlapping requests, dispose timers/listeners, and discard stale responses after filters change.
- Historical date ranges select Business Days by their opening business date in Asia/Karachi, with an exclusive upper bound. Orders/shifts/trips are selected by their Business Day FK even after midnight. Timestamp-only procurement/waste/Khata events use the union of selected actual Business Day intervals; never an arbitrary five-minute extension. State the time basis on screen and exports.
- A live report includes the active Business Day; when no day is open, clearly show that condition and allow history. Zero activity, missing input, load failure, no matches, and unavailable datasets are distinct states.
- Live comparisons must use equivalent elapsed coverage or explicitly withhold percentage comparison until comparable. Historical comparisons use an equal preceding Business Day date window. A zero baseline yields no percentage; show the absolute difference. Never compare an incomplete live day as though it were a complete day.
- Filters apply only to meaningful datasets; show each section's scope. No silently ignored filter and no item/payment join multiplying order totals. Start with date, cashier, shift, Dining Type and payment method for order-based reports; extend domain-specific filters only when backed by source facts. Global totals must not appear filtered when only order reports were filtered.
- Use the existing dark theme and design tokens, readable figures and semantic status text, keyboard-accessible controls, horizontal scrolling for wide tables and responsive KPI layout. Report navigation must not overflow 1366x768 or narrow layouts.

## Report catalog and minimum useful coverage

| Family | Required recorded-data analytics | Explicit missing inputs |
| --- | --- | --- |
| Sales | Recorded order value, item subtotal, discounts, tax carve-out, fees, rounding, eligible order count, average ticket; daily/hourly trends; Dining Type/cashier/shift/payment breakdown | Recognized revenue requires a named recognition policy distinct from recorded value |
| Order operations | Committed counts by payment and token state; cancellation/revision counts, reasons and price deltas; refund exposure; token identity | Prep/ready percentiles require persisted lifecycle times; in-memory holds cannot become historical records |
| Delivery | Orders/fees by area; trips, loads, delivered/returned outcomes, valid travel times with coverage; Collection Due and unsettled trip exposure | Expected COD is not proof the rider collected customer cash; failure reasons/reattempt attribution only where recorded |
| Customers | Known vs guest coverage, distinct known customers, repeat-customer rate, average ticket, order history and areas | Guest identities excluded; normalized phone is a disclosed proxy, not guaranteed person identity |
| Menu/deals | Quantity and recorded line value by item/deal, modifiers/choices where snapshotted, popular/slow/zero sellers, discount use | Item-level net sales needs explicit order-discount/tax/fee allocation; current BOM/cost must not rewrite old margins |
| Inventory | Current stock/threshold/negative alerts, movement timeline, covered as-of balances, BOM quantity snapshots, waste | Generic movement causes, pre-v14 history, physical counts and historical cost layers are incomplete |
| Procurement | Purchase quantities/base units, total recorded spend, per-ingredient unit-price trends, purchase frequency | Supplier performance and supplier association unavailable where not recorded |
| Supplier Khata | Opening/current payable, credit purchases, drawer/external payments, payment activity and source rows | Historical opening edits/deletions limit as-of reconstruction; no invoice due dates or allocations means no overdue claim |
| Cash/shifts | Float, receipts, refunds, movements by category, expected/counted/variance, unresolved discrepancies, X/Z provenance | Missing blind count means unknown variance; collections by actual receipt time are limited by legacy payment timestamps |
| Expenses | Recorded PAY_OUT by category/source and source records, cash movement trends | All PAY_OUT is not operating expense: exclude or mark supplier settlements, refunds, drops and advances; no unsupported accrual totals |
| Staff/payroll | Staff/department/job-role counts, active/login state, cashier order activity and shifts | No salary/accrual/advance/attendance ledger; salary due, labor cost and productivity per labor hour unavailable |
| Profitability | Recorded sales components, waste cost, purchase spend and costing-coverage explanations | Purchase spend is not COGS. Actual historical gross/net profit unavailable without event-time costs/expense and labor allocation; never display false zero profit |
| Control/audit | Order revisions/reasons, token audit, rounding, report runs/export/outbox health and delivery audit; source provenance | Broad login/security/configuration audit and historical backup success cannot be inferred from current settings |

Every family has a source table or an explicit missing-source statement. Every KPI explains formula, unit, cohort/time basis and quality. Every available detail row carries a stable source type/ID; sensitive fields (PIN/hash, credentials, raw customer addresses/phones) must not enter the reporting model or exports. Customer identifiers are masked.

## Calculation contract

1. Convert each legacy REAL rupee amount once through `PaisaEngine.rupeesToPaisa`; prefer authoritative non-null integer-paisa fields. Sum integers, format only at UI/export boundaries. Disclose legacy precision rather than claiming the database is wholly migrated.
2. Recorded order value = sum current valid committed `grand_total`, excluding VOIDED/CANCELLED/REFUNDED, explicitly including Collection Due. It is not collected payments or tax-exclusive recognized revenue. Show subtotal, discount, tax, delivery fee and rounding independently.
3. Average ticket = recorded eligible order value / eligible count; show denominator. Percentages and time averages require a nonzero valid sample. Rate calculations are unrounded until display.
4. Collected tender = sum amount tendered minus change, including explicit negative refund payment rows. Count each payment once. Report by the order's Business Day cohort for legacy payments; do not claim this is actual cash-flow event date.
5. Collection Due = current eligible `COLLECTION_DUE` order total; distinguish selected-cohort due from all-outstanding liabilities. Delivered does not imply collected.
6. Expected drawer = float + positive customer cash receipts + PAY_IN - PAY_OUT, following the existing controller's rider-settlement representation. Cash refunds already reduce via PAY_OUT; never subtract twice. Counted variance is unavailable for uncounted shifts; show counted coverage and separate open shifts.
7. Revision/cancel rates count distinct orders for the selected order cohort, not number of revisions. Show event count separately. Refunds remain distinct from cancellation/refund-pending exposure.
8. Repeat customer rate = distinct known normalized phone identities with >=2 eligible selected orders / known identities with >=1. Unknown/guest excluded; do not export full phones.
9. Travel = valid per-order delivered timestamp minus containing trip dispatch; report sample count and exclusions. Returned does not automatically imply final failure if later redelivered; label returned-attempt rate unless final outcome is provable.
10. Inventory as-of uses recorded movement balance evidence only within history coverage. Missing pre-upgrade balances are unknown. Never sum grams, liters and counts into one stock quantity. Keep current stock visibly current even in a historical report.
11. Recorded waste cost uses stored event cost_loss. Procurement spending and supplier payable/payment are separate measures; a credit purchase is not a cash expense. Existing unlinked purchase/credit records must not be blindly summed as one spend total.
12. Quality values: Complete, Estimated, Missing data, Not applicable. Missing data has null value, a reason and coverage where measurable. Partial coverage cannot silently become a complete total.
13. Closed report snapshots retain their stored hash/revision. Distinguish an exploratory query over current records from an immutable sealed Z-report; corrections never overwrite stored report snapshots. Do not silently reuse misleading legacy `netSales` labels or broaden this feature into a rewrite of Z-report calculations.

## Module and public API contract

New module: `lib/core/analytics/` (domain models, query service and export service); view: `lib/widgets/supervisor/manager_analytics_workspace.dart`. Widgets contain no SQL or financial calculations. Keep dependencies small and reuse existing packages; no ORM rewrite, cloud service or framework build tools locally.

Shared models in `analytics_models.dart`:

- `enum AnalyticsFamily { overview, sales, orders, delivery, customers, menu, inventory, procurement, suppliers, cash, expenses, staff, profitability, audit }`
- `enum AnalyticsUnit { count, paisa, percent, decimal, minutes }`
- `enum AnalyticsQuality { complete, estimated, missing, notApplicable }`
- `AnalyticsMetric({required String id, required String label, num? value, required AnalyticsUnit unit, required String explanation, AnalyticsQuality quality = AnalyticsQuality.complete, int? sampleCount, int? populationCount, double? changePercent, num? changeAbsolute})`. Absolute change uses the metric's unit and retains a comparable historical current-minus-prior difference when the prior value is zero; percentage remains unavailable for a zero baseline. Both comparisons are withheld for live/open coverage without an equivalent elapsed baseline.
- `AnalyticsColumn({required String key, required String label, AnalyticsUnit? unit})`.
- `AnalyticsRow({required String id, required Map<String, Object?> cells, required String sourceType, String? sourceId})`.
- `AnalyticsSection({required AnalyticsFamily family, required String title, List<AnalyticsMetric> metrics = const [], List<AnalyticsColumn> columns = const [], List<AnalyticsRow> rows = const [], List<String> notes = const []})`.
- `AnalyticsQuery({required DateTime startDate, required DateTime endDateExclusive, bool live = false, int? cashierId, int? shiftId, String? diningType, String? paymentMethod})`, with copyWith. Dates are local Business Day dates, validated start < end. Add validated equality/signature for refresh handling as appropriate.
- `AnalyticsSnapshot({required AnalyticsQuery query, required DateTime generatedAt, required List<AnalyticsSection> sections, required List<int> businessDayIds, List<String> notes = const []})`, with `section(AnalyticsFamily)` lookup. All collections immutable; source rows contain only safe projection fields.
- `AnalyticsService({required Database database, required AuthService authService})` exposes `Future<AnalyticsSnapshot> load(AnalyticsQuery query)`. Service must require an active, enabled Manager session at each load, and use a consistent read transaction. Shared financial query results must not mix commits.
- `AnalyticsExportService` exposes exports from the existing immutable `AnalyticsSnapshot` rather than recomputing SQL. CSV for a selected section, XLSX workbook for all sections, PDF summary with details; files persist to a selected local directory with cancellation/progress in UI where needed. Keep APIs small and coordinate exact signature before view wiring.
- Workspace accepts the service and an optional injected clock/refresh duration for public behavior tests. Integration creates it only when both database and auth dependencies exist; otherwise show an honest unavailable state without breaking existing portal tests.

Sales rows provide daily totals with `business_date`, `orders`, `recorded_value_paisa`; table and chart use those same rows. Additional dimensional details may be separate rows/sections if clearly labeled and not incorrectly summed together.

## Exports

- CSV, XLSX and PDF all consume the exact visible query snapshot, selected filters and family. Numeric money remains numeric with correct units in spreadsheets; PDF/UI format paisa as PKR.
- Include generated time UTC/local, Asia/Karachi, selected Business Day range/IDs, filters, formulas/report version, quality notes, source IDs, currency and report author ID (no PIN/hash).
- Spreadsheet formula-injection defenses apply to untrusted text, including strings beginning with =, +, -, @, tab or CR. Preserve numeric negatives as numbers. Escape CSV quotes/newlines correctly.
- No automatic external transmission. Existing report delivery configuration is separate from dashboard exports. Export errors are recoverable and do not freeze or mutate billing.

## Confirmed public test boundaries

1. Analytics query/calculation service: synthetic SQLite fixtures assert independently worked financial totals, COD/refund/split-tender and drawer reconciliation, historical boundaries, joins/filters, authorization, zero/missing/coverage and source IDs.
2. Data-capture/migration services: guard preservation of existing history when changes are necessary. This increment is read-only analytics; no migration or new posting workflow is required merely to suppress a missing-data notice. Exercise old/incomplete evidence through public query behavior.
3. Manager Portal screens: navigation/access, live refresh/disposal and stale results, date/report/filter changes, chart table alternative, source detail, empty/error/narrow-window states.
4. Exports: same-snapshot totals/filters, all report families, numeric units, formula-injection defenses, customer masking and quality metadata.

All framework analysis/tests/builds run only in GitHub Actions. Use red -> green vertical slices, retain run links, and run the existing CI suite before declaring completion. No local flutter/dart framework processes.

## Implementation task graph

| Ticket | Scope | Depends on |
| --- | --- | --- |
| A | Immutable reporting models and authorized analytics query service covering all 13 families, comparisons, quality/source evidence and focused calculation tests | Specification |
| B | Manager Portal dashboard/explorer, live/history/filter/chart/detail behavior and widget tests against shared contract | Specification; integrates A |
| C | Snapshot-based CSV/XLSX/PDF export with metadata and safe values; export tests; workspace buttons | Shared models from A's first passing slice and B's export-action seam (available); complete query/UI integration remains D |
| D | Integrated financial/UX verification, remote regression CI, two-axis code review and fixes; review-ready PR | A, B, C |

Implementation branches merge into one `codex/manager-analytics` integration branch. Each implementation ticket uses an isolated worktree. GitHub issues track the graph; final PR references all tickets. Keep unrelated `docs/manual-manager-portal-testing.md` untouched.
