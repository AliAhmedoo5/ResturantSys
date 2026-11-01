# Worked Hours, Attendance, and Labor Productivity Policy

Under [Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60), [Ticket #72](https://github.com/AliAhmedoo5/ResturantSys/issues/72), and [ADR-0020](adr/0020-earned-period-payroll-and-labor-allocation.md), this document defines the restaurant's operational and financial rules governing worker attendance, worked-hours tracking, labor productivity metrics, and cross-department labor cost allocation.

---

## 1. Actual Attendance vs. Cashier Shift Duration

In restaurant operations, physical drawer custody and staff attendance measure two fundamentally distinct concepts:

- **Cashier Shift Duration**:
  - Represents the custody interval of a POS cash register drawer between `shifts.opened_at` and `shifts.closed_at`.
  - While a cashier may keep a register drawer open for 12 hours (e.g. 11:00 AM to 11:00 PM), this indicates custody over cash, not the attendance duration of other staff.
  - Treating drawer duration as attendance corrupts kitchen scheduling, distorts guest-facing throughput metrics, and misattributes hours to non-cashier staff (chefs, dishwashers, prep cooks, waitstaff, cleaners, supervisors).

- **Staff Attendance / Worked Hours**:
  - Represents verified, authenticated physical presence on shift.
  - Logged exclusively via authenticated Manager entry in the `worked_hours` ledger.
  - Records employee ID, department snapshot, work date, UTC clock-in, UTC clock-out, break minutes, and approved net worked minutes.

- **Prohibition of Synthetic Attendance**:
  - The system **strictly forbids** synthesizing attendance from cashier shifts when attendance logs are absent.
  - In periods lacking verified attendance, analytics reports mark labor hours and labor productivity as `Unavailable` with quality `missingEvidence` and the canonical disclosure:
    > *"Cashier shift duration is not paid attendance or worked labor-hour evidence."*

---

## 2. Schema for `worked_hours`

Physical attendance is stored in the immutable `worked_hours` financial ledger:

```sql
CREATE TABLE IF NOT EXISTS worked_hours (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  employee_id INTEGER NOT NULL REFERENCES staff(id),
  department_id INTEGER NOT NULL REFERENCES departments(id),
  work_date TEXT NOT NULL,
  clock_in TEXT NOT NULL,
  clock_out TEXT NOT NULL,
  break_minutes INTEGER NOT NULL DEFAULT 0 CHECK(break_minutes >= 0),
  worked_minutes INTEGER NOT NULL CHECK(worked_minutes > 0),
  business_day_id INTEGER REFERENCES business_days(id),
  manager_id INTEGER NOT NULL REFERENCES staff(id),
  reason TEXT NOT NULL,
  request_key TEXT UNIQUE,
  created_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS worked_hours_employee_date ON worked_hours(employee_id, work_date);
CREATE INDEX IF NOT EXISTS worked_hours_date ON worked_hours(work_date);
CREATE INDEX IF NOT EXISTS worked_hours_business_day ON worked_hours(business_day_id);
```

### Invariants and Database Constraints
1. **Net Worked Minutes**: Net minutes are strictly computed as:
   $$\text{worked\_minutes} = (\text{clock\_out} - \text{clock\_in})_{\text{minutes}} - \text{break\_minutes}$$
   Must be strictly positive (`CHECK(worked_minutes > 0)`). Break minutes cannot be negative (`CHECK(break_minutes >= 0)`).
2. **Immutability Triggers**: `UPDATE` and `DELETE` operations on `worked_hours` are aborted at the SQLite level with triggers raising `'Financial history is immutable'`.
3. **Idempotent Replay Protection**: Each entry enforces a unique `request_key`. Replaying a submission with identical payload returns the existing record ID without creating duplicates; replaying with conflicting attributes is rejected with `StateError`.
4. **Manager Authentication**: Recording requires an active Manager session; attempts by Cashiers or unauthorized roles are rejected.

---

## 3. Productivity Formula and Department Denominator Eligibility

### Formula
Direct labor productivity measures operational efficiency by comparing order throughput to the actual hours worked by guest-facing and production staff:

$$\text{Orders per Direct Labor Hour} = \frac{\text{Eligible Confirmed Orders}}{\text{Direct Operational Worked Hours}}$$

Where:
- $\text{Direct Operational Worked Hours} = \sum \frac{\text{Direct Worked Minutes}}{60.0}$

### Explicit Approved Denominator Allowlist (ADR-0020 §6)
Only staff actively engaged in food preparation, order assembly, guest service, and order delivery are included in the productivity denominator:

- **Kitchen / Back of House (BOH)**: Head chefs, line cooks, prep cooks, dishwashers, kitchen assistants.
- **Front Counter / Register**: Cashiers, order takers, counter staff.
- **Service / Dining / Front of House (FOH)**: Waitstaff, runners, floor hosts, table service staff.
- **Delivery Riders**: Delivery riders, dispatchers, drivers.

### Excluded Administrative Overhead
Administrative and supervisory hours are recorded for payroll and labor expense allocation, but **strictly excluded** from the order throughput denominator:
- **Management & Executive**: General managers, shift supervisors, owners.
- **Back-Office & Administration**: Accountants, HR, administrative assistants, inventory clerks.
- **Unassigned / Unknown Departments**: Any attendance record without an approved direct operational department assignment defaults to overhead.

*Rationale*: Including management overhead in the denominator would artificially depress productivity during administrative tasks (e.g. inventory audits, supplier negotiations), creating false operational alarms.

### Zero Hours & Absence Handling
- If direct worked hours in the selected period are zero, the metric is marked `Unavailable` (`0.0 direct operational hours logged in period`).
- If store order filters (such as dining type or cashier filters) are applied, productivity is marked `Unavailable` because storewide direct operational labor hours cannot be apportioned to arbitrary order subsets.

---

## 4. Cross-Department Labor Cost Allocation Rules

Employees frequently work across multiple departments (e.g., utility staff assisting with kitchen prep during peak rushes and dining floor service during lulls).

### Verified Hours Proportion Method
When verified attendance is logged for an employee in a given earned period (`YYYY-MM`), their monthly earned salary accrual is distributed proportionally based on worked minutes in each department:

$$\text{Department Labor Cost} = \text{Monthly Net Accrual Paisa} \times \frac{\text{Worked Minutes in Department}}{\text{Total Worked Minutes for Employee}}$$

### Deduplicated Integer Paisa Allocation Math (`allocatePaisaProportionally`)
To eliminate floating-point rounding errors and fractional paisa drift:
1. Each department share is computed via integer floor division:
   $$\text{Share Paisa} = \left\lfloor \frac{\text{Accrual Paisa} \times \text{Department Minutes}}{\text{Total Minutes}} \right\rfloor$$
2. The integer remainder ($\text{Accrual Paisa} - \sum \text{Share Paisa}$) is allocated to the department with the largest worked minutes (largest bucket).
3. The sum of allocated departmental amounts **strictly equals** the employee's total accrued salary (zero lost or duplicate paisa).

### Primary Department Fallback
If no verified attendance hours are logged for an employee in the earned period, their net salary accrual defaults 100% to their primary assigned department snapshot (`staff.department_id`).

### Earned Period vs. Posting Period Matching (ADR-0020 §1)
- Salary expense is recognized strictly in its **Earned Period** (`period` formatted as `YYYY-MM`).
- Reports covering a given period (e.g. October 2026) match payroll entries by their earned `period = '2026-10'`, regardless of whether the Manager posted the accrual in October or November.
- This prevents accruals posted in a subsequent month from leaking into that month's departmental labor costs or distorting historical P&L reports.

---

## 5. Verification and Zero Double-Expense Guarantees

The accounting system enforces strict three-tier temporal separation between accruals, postings, and cash payments:

1. **Expense Recognition at Accrual Only**:
   - `ACCRUAL` is the **sole** event that recognizes salary expense and creates a current salary payable liability.
   - `PAYMENT` (drawer, bank, or owner funds) reduces cash and reduces salary payable liability; it **never** recognizes operating expense.
   - `ADVANCE` reduces cash and creates an employee advance balance; it is an asset exchange, not an expense.
   - `RECOVERY` offsets an advance against accrued payable with zero cash movement and zero duplicate expense.
2. **Adjustment Bridge for Closed Days (ADR-0019)**:
   - Once a Business Day is closed and sealed with a Z-Report, historical entries are immutable.
   - Late payroll adjustments for closed periods are logged as append-only `historical_corrections` rows and displayed in reports as an Adjustment Bridge without altering original sealed hashes.
3. **Overnight Shift Safety**:
   - Shift inputs crossing midnight (e.g., 22:00 to 04:00 next day) are automatically resolved into continuous calendar intervals without generating negative durations or calculation aborts.
