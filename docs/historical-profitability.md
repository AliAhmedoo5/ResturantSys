# Historical profitability and discount accounting

Schema version 21 starts immutable order cost capture. It does not reconstruct
costs for earlier orders from today's ingredient rates.

## Cost policy

At checkout, the POS freezes each consumed ingredient's quantity, the recorded
acquisition rate per recipe/stock unit, and extended integer-paisa cost. The
quantity includes the selected deal components, modifiers and automatic
Takeaway/Delivery packaging. Procurement and linked supplier credit deliveries
update acquisition rates; changes are retained in ingredient cost history.
This is an event-time acquisition-rate policy, not FIFO or weighted-average
stock valuation. The underlying unit rates retain decimal precision; extended
money is rounded once into integer paisa.

Revisions consume additions at their event-time rate. Raw returns release the
original order's cost lots, newest first, and retain references to those original
events. Exhausting a lot releases its exact remaining paisa. Cooked removals
and cancellations mark the original cost as wasted without another deduction
from profit. Repeated checkout/cancellation command IDs do not post costs twice.

Unknown or zero ingredient rates are missing cost evidence, not free food. Any
uncovered order or unknown rate in the selected cohort withholds complete COGS
and profit. Cost event rows and capture coverage remain visible for inspection.
Legacy orders remain uncovered even when revised after the upgrade.

## Revenue and operating result

The report recognizes orders at confirmation, including COD receivables and
delivery fees, and excludes the stored sales-tax carve-out. Current audited
revision/cancellation totals determine recognized value. Gross profit is this
tax-exclusive revenue less consumed costs, net of raw returns. Cooked losses
remain consumed cost even when the canceled order has no revenue.

The recorded net operating result subtracts posted expense ledger entries,
salary accruals and raw kitchen waste, and adds signed posted physical-count
valuation. Expense/payroll reversals reduce their original cost. Salary payments,
advances, supplier payments, acquisition spend and generic drawer outflows are
not charged again. Net result uses posting-period allocation across complete
Business Days; order filters withhold it because overhead has no reliable
cashier/dining/payment allocation. Unposted liabilities are never inferred.

## Discount stacking

Managers explicitly enable **Allow combining with other stackable discounts**
on each participating preset. Existing presets remain exclusive by default.
Selecting an exclusive preset replaces other selections. Stacks apply in stable
preset-ID order to remaining eligible line balances, so click order cannot alter
payment. Caps, minimum spend, eligibility and daily usage limits still apply.
Discounts never make an eligible line negative or apply to delivery fees.

Checkout revalidates current terms and each Business Day limit within its
transaction, then stores every preset's terms, name, order and awarded paisa.
Held carts retain all selected IDs and refresh current terms on recall/payment.
Revisions use the order's frozen pre-approved terms. Tax carve-out follows each
line's actual remaining discounted value.

## Physical-count analytics

Inventory analytics includes posted count observations in the selected Business
Day intervals: expected/count quantities, signed variance, unit, cost estimate,
creator, approver, poster, snapshot sequence and adjusting movement reference.
Zero-variance observations have no adjusting movement. Quantity totals never
combine incompatible ingredient units. Missing count valuation withholds a
complete financial variance total.
