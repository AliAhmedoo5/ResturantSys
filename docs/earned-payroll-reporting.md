# Earned payroll reporting

Manager Analytics → Staff and payroll shows recorded earned salary separately
from posting-period accruals. Select complete calendar months (first day through
the first day of the following month). A partial month or Live selection cannot
allocate a monthly salary to individual days, so earned totals are unavailable.
Order filters do not allocate payroll. Profitability includes the same earned
salary and an alternative operating result which replaces posting-period salary;
it never adds both expenses. Other operating costs retain their posting scope.

The policy is explicitly approved in [issue #72](https://github.com/AliAhmedoo5/ResturantSys/issues/72#issuecomment-6507716052)
and documented in [ADR-0020, PR #101](https://github.com/AliAhmedoo5/ResturantSys/pull/101).
The report uses the existing explicit payroll `period` and posted Integer Paisa
amounts. It does not accrue an unposted salary from a configured rate or fabricate
worked days. Approved partial-month amounts use integer floor of monthly base
times worked calendar days divided by actual days in the month, capped at base.
For example 4,650,000 paisa × 16 / 31 = 2,400,000 paisa. Managers retain the
worked-day justification in the accrual reason.

An October salary posted in November remains October earned expense. Its
November payment is November money flow, with BANK, OWNER and DRAWER separated
in the existing finance timeline. Only an accrual (and its linked reversal)
recognizes salary expense. Advance funding and explicit recovery never do.

Paid, recovered, unpaid payable and outstanding advances refer to ledger entries
explicitly labeled with selected earned months, through the snapshot generation
cutoff. They are **not month-end historical balances**. Accrued − paid − recovered
= unpaid payable. Outstanding advances are separate receivables. Later settlement
updates a refreshed exploratory view while earlier snapshots and sealed reports
remain intact. Negative legacy month balances withhold settlement totals because
the installation-wide payment controls do not prove cross-month allocation.

Payroll contributor rows retain original recording time, kind, reason, employee
identity evidence, reversal link and payable/advance deltas. Earned-scope and
posting-scope flags distinguish the two views. Linked payment events provide
actual payment time, assigned Business Day, physical Shift and Cash Movement;
they are links to the same funds, never another payment. Original payroll rows
do not retain a posting Business Day FK; this gap is disclosed. A payment's day
does not prove the accrual's posting day. Missing actual time stays missing.

The existing shared CSV, XLSX and PDF serializer consumes the same immutable
metrics, rows, explanatory notes and cutoff displayed by the workspace.
Current names remain separately labeled from retained transaction-time names.
PIN credentials and customer contact fields are not payroll evidence.

No historical correction bridge, attendance capture or effective department
allocation is introduced by this reporting slice. The report discloses their
absence and does not claim adjusted sealed values or labor-hour productivity.
Original closed reports are neither rewritten nor backdated. Legacy unposted or
unallocated payroll remains unknown, including installations with no entries.
