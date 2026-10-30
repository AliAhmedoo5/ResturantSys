# Manager domain filters

Open **Report filters & Hold aging** in Manager analytics. Select readable names
backed by stable IDs; the ID is displayed beside the current picker name. Choose
**All** or remove an active chip to clear one dimension. **Reset domain filters**
clears domain and funding-stream selections, keeping the selected period and Hold
threshold. **Clear** clears the full filter panel. Refresh produces a new
immutable snapshot; an already generated export retains its original selection.

| Selection | Applicable report evidence | Limits |
| --- | --- | --- |
| Menu Item, menu category, Deal | Order cohorts in Sales, Order operations, Delivery, Customers and Profitability; matching sold lines in Menu | Order values remain whole matching Orders, not allocated item revenue. Multiple menu predicates must match the same sold line. Deal components are not inferred from today's recipe. |
| Pre-Approved Discount | Orders retaining that discount ID | Unknown historical IDs cannot match. |
| Delivery Area | Orders retaining that area ID | Source rows retain recorded area names when available. |
| Rider | Orders with a retained attempt by that rider | A rider assignment is not customer collection evidence. Whole trips retain their stated scope. |
| Known / guest customer identity | Same Order cohort and Customer details | Known means a usable normalized phone identity; guest means none. Shared numbers and installation history limits remain. These are not lifetime loyalty segments. |
| Supplier | Vendor Khata and recorded supplier credit acquisition evidence | Mandi has no supplier link and is excluded from supplier-selected acquisition views. Supplier payments cannot be allocated to ingredients without evidence. |
| Expense category | Expense postings and linked finance payment events | Whole drawer outflows remain separate physical evidence. They are not expense postings and do not enter expense totals twice. |
| Department | Current staff directory | Current directory classification is not historical department allocation. Historical payroll and current payable balances remain outside this predicate. |
| Raw Ingredient | Inventory bridges, movements and acquisition evidence | Quantities retain their base units. Different ingredient/unit quantities cannot be summed as one quantity. |
| Acquisition evidence | Mandi or supplier credit acquisition rows | These are separate evidence views. No combined acquisition total or deduplication is claimed without retained links. |
| Funding stream | Actual money-flow views | Whole-Shift drawer reconciliation remains whole. No allocation of Opening Float to Order dimensions is implied. |

Menu category selectors use the **current** Menu Item category. Historical category
snapshots were not stored; category changes can therefore change a refreshed
current-classification view, and archived/unlinked items may have unknown category.
Stock categories are unavailable because no category evidence is stored. Current
department selection never rewrites payroll history. Historical source names, where
captured, remain separate from current picker names.

Unrelated domains retain their labeled scope. In particular, cash drawer bridges,
whole trips, all-outstanding Collection Due, current stock, and current liabilities
must not appear to be reconstructed through an unrelated Order/category filter.
Always read the formula and scope notes beside the measure. Metrics, charts and
contributors for an applicable view are projected from the same selected evidence;
CSV, XLSX and PDF serialize that snapshot with selected IDs, readable picker names,
query scope, source schema/report version and coverage notes. Customer contact
details remain outside analytics exports.
