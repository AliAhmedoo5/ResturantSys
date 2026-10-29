# Earned-Period Payroll, Worked-Hours Attendance, and Labor Allocation Policy

## Context
In restaurant management, labor represents one of the largest recurring operating expenses, yet its accounting and operational productivity measurements are frequently distorted by naive assumptions:
1. **Conflating Earned Period, Posting Date, and Payment Money Flow**: Labor is earned during the calendar month in which employees work (e.g., October). However, managers typically post salary accruals at month-end or early the following month (e.g., 2 November), and actual cash disbursements (payouts or bank transfers) often occur days later (e.g., 5 November). Naive accounting systems either record labor expense on the date money leaves the drawer (distorting monthly profit & loss) or recognize an expense both when accruing and when paying (double-counting labor cost).
2. **Conflating Cashier Shift Duration with Staff Attendance**: A POS register drawer open for 12 hours measures the cashier's drawer custody window. It does **not** represent 12 hours of attendance for kitchen chefs, dishwashers, prep cooks, waitstaff, cleaners, or supervisors. Treating register open duration as staff attendance corrupts labor productivity metrics (such as Orders per Labor Hour), distorts kitchen staffing decisions, and falsely attributes hours to staff who never touched the register.
3. **Mid-Month Hires, Unpaid Leave, and Fractional Paisa Rounding**: Staff joining mid-month or taking unpaid leave require transparent, approved proration rules without floating-point rounding errors or undocumented day divisors.
4. **Advance Loans and Net Due Entanglements**: Uncontrolled salary advances risk employee debt accumulation and overpayment beyond earned net payable.
5. **Sealed Report Integrity**: When payroll revisions occur after a Business Day or monthly period is closed with an End-of-Day Z-Report, earlier naive systems either mutated closed database rows (breaking cryptographic audit hashes) or generated phantom cash movements in today's live drawer.

Under [Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60) and [Ticket #72](https://github.com/AliAhmedoo5/ResturantSys/issues/72), this decision establishes the binding human policy governing earned-period payroll, worked-hours attendance, and department labor allocation prior to implementing [Ticket #73](https://github.com/AliAhmedoo5/ResturantSys/issues/73) and [Ticket #94](https://github.com/AliAhmedoo5/ResturantSys/issues/94).

---

## Decision

### 1. Three-Tier Temporal Separation (Earned Period vs. Posting Period vs. Payment Period)
To guarantee 100% accounting and operational accuracy, the system enforces a strict three-tier temporal model:
- **Earned Period (`period` / `earned_period` formatted as `YYYY-MM`)**:
  - Defines the calendar month in which employee services were rendered.
  - All profitability, cost of goods, and operational labor cost reports allocate salary expense strictly to its **Earned Period**.
  - E.g., October 2026 labor cost belongs to October financial analytics, even if posted in November.
- **Posting Period (`business_day_id`, `created_at`)**:
  - The operational Business Day and immutable system timestamp at which an authenticated Manager enters a payroll transaction (`ACCRUAL`, `PAYMENT`, `ADVANCE`, `RECOVERY`, or `REVERSAL`).
  - Audited under Manager accountability without backdating system recording timestamps.
- **Payment Period (`actual_at`, `cash_movement_id`, `source`)**:
  - The actual moment physical drawer cash, bank digital funds, or owner funds are disbursed to an employee.
  - Recorded exclusively in cash/money flow for that payment date and source.
- **Zero Double-Expense Invariant**:
  - **Accrual (`kind = 'ACCRUAL'`)** is the **sole** event that recognizes salary expense and establishes a current salary payable liability.
  - **Payment (`kind = 'PAYMENT'`)** is an asset/liability balance sheet exchange (reduces cash/bank, reduces salary payable). It **never** recognizes operating expense.
  - **Advance (`kind = 'ADVANCE'`)** is a pre-funding receivable (reduces cash/bank, increases employee advance balance). It is **not** an expense.
  - **Recovery (`kind = 'RECOVERY'`)** offsets an outstanding advance against an accrued payable. It moves zero cash and recognizes zero expense.

```
+-----------------------------------------------------------------------------------+
| Temporal Layer    | Database Attribute  | Financial Meaning                       |
+-------------------+---------------------+-----------------------------------------+
| Earned Period     | period (YYYY-MM)    | P&L Expense Recognition (October Cost)   |
| Posting Period    | created_at / day_id | Administrative Entry Time (02 Nov entry)|
| Payment Period    | actual_at / source  | Physical Money Flow (05 Nov disbursement)|
+-----------------------------------------------------------------------------------+
```

---

### 2. Monthly Base Salary Configuration and Effective Date Boundaries
- **Storage**: Employee monthly compensation is stored in `salary_rates` per employee in Integer Paisa (`amount_paisa > 0`, where PKR 1.00 = 100 paisa) keyed by `effective_period` (`YYYY-MM`).
- **Effective Month Boundaries**: Salary changes take effect on the first day of the designated `effective_period` calendar month.
- **Immutability of Accrued Periods**: A salary rate change **cannot** be posted for a period that has already been accrued in `payroll_entries`. Any retrospective adjustment requires an explicit, audited reversal workflow.

---

### 3. Proration Formula, Calendar Day Divisors, and Integer Paisa Rounding
When an employee works a partial month (e.g. joins mid-month or takes approved unpaid leave), their earned salary is prorated according to standard restaurant commercial practice:
- **Calendar Month Divisor ($D_{\text{month}}$)**: The denominator is the exact number of calendar days in the earned month:
  $$D_{\text{month}} \in \{28, 29, 30, 31\}$$
  - E.g., October has 31 days; November has 30 days; February has 28 (or 29 in leap years).
- **Daily Rate Calculation**:
  $$\text{Daily Wage Paisa} = \left\lfloor \frac{\text{Monthly Base Salary Paisa}}{D_{\text{month}}} \right\rfloor$$
- **Prorated Earned Salary Formula**:
  $$\text{Earned Paisa} = \min\left(\text{Monthly Base Salary Paisa}, \left\lfloor \frac{\text{Monthly Base Salary Paisa} \times D_{\text{worked}}}{D_{\text{month}}} \right\rfloor\right)$$
- **Strict Integer Division & Zero Fractional Paisa Drift**:
  - Division uses integer floor arithmetic (`~/` in Dart / integer division in SQLite). Fractional paisa are never stored or accumulated as floats.
  - Any minor odd-paisa truncation residue ($\le D_{\text{month}} - 1$ paisa, typically $< 30$ paisa) remains unearned or resolves in the final closing pay slip of the period, guaranteeing that cumulative paid wages never exceed the configured monthly ceiling.
- **Mandatory Justification for Proration**:
  - The default accrual amount defaults to 100% of the employee's configured monthly rate.
  - Any explicit entry less than the full monthly rate requires an explicit reason (minimum 10 characters) detailing the worked days count and justification.

---

### 4. Advances, Offsets, Recoveries, and Overpayment Prevention
- **Advance Cap**: An employee's cumulative unrecovered advances can **never** exceed one full configured monthly salary:
  $$\text{Current Advance Paisa} + \text{New Advance Paisa} \le \text{Configured Monthly Salary Paisa}$$
- **Net Due Formula**:
  $$\text{Net Due Paisa} = \text{Accrued Payable Paisa} - \text{Outstanding Advance Paisa}$$
- **Explicit Recovery**: Advances are not silently wiped; they are offset against accrued payable via explicit `RECOVERY` entries recorded by an authenticated Manager.
- **Overpayment Prohibition**: Payments cannot exceed `Net Due Paisa`. Overpayment attempts are rejected at the application controller and database constraint levels.

---

### 5. Retroactive Corrections, Reversals, and Immutability of Sealed Reports
- **Open-Period Corrections**:
  - If a mistake is made in the current unclosed period before payments or recoveries are linked, the Manager records an immutable `REVERSAL` of the accrual and inserts the correct accrual.
- **Closed Historical Periods (ADR-0019 Compliance)**:
  - Once a Business Day or monthly period is closed with a sealed Z-Report, historical `payroll_entries`, `business_days`, and stored report JSON snapshots are **100% immutable**.
  - Retroactive corrections (e.g. late-discovered unpaid overtime or bonuses earned in a closed past month) must be recorded as an append-only entry in `historical_corrections` with:
    - `target_entity_type = 'PAYROLL_ENTRY'`
    - `correction_type = 'LATE_EXPENSE'` or `CONTRA_REVERSAL`
    - `delta_amount_paisa`: Signed Integer Paisa
    - `affected_business_day_id`: Business Day of the historical earned period
    - `manager_name_snapshot` and mandatory `reason`
  - Reports display the Original Sealed Value alongside the itemized **Adjustment Bridge** up to the selected cutoff timestamp ($T_{\text{cutoff}}$).
  - Cash disbursements for historical corrections must **never** inject phantom cash into today's active drawer; they execute through the current open day's normal funding sources.

---

### 6. Actual Attendance vs. Cashier Shift Duration & Worked-Hours Eligibility
- **Fundamental Distinction**:
  - **Cashier Shift Duration**: Represents physical drawer custody at the POS register between `shifts.opened_at` and `shifts.closed_at`. It is **not** an attendance record.
  - **Staff Attendance / Worked Hours**: Represents verified physical presence on shift, captured via dedicated attendance logs (`staff_attendance` / `worked_hours`) specifying employee ID, date, department, clock-in, clock-out, break minutes, and approved net worked hours.
- **Prohibition of Synthetic Attendance**:
  - Historical periods lacking explicit attendance logs must **never** fabricate hours from cashier shifts.
  - Reports mark labor hours as `UnavailableQuality.missingEvidence` with the canonical note:
    > *"Cashier shift duration is not paid attendance or worked labor-hour evidence."*
- **Worked-Hours Eligibility for Productivity**:
  - **Direct Labor Productivity Metric**:
    $$\text{Orders per Direct Labor Hour} = \frac{\text{Eligible Confirmed Orders}}{\text{Direct Operational Worked Hours}}$$
  - **Eligible Departments for Denominator**: Only direct production and guest-facing staff (Kitchen, Service / Front of House, Register Cashiers, Delivery Riders) are counted in the productivity denominator.
  - **Administrative Overhead Exclusion**: Management, accounting, and back-office hours are recorded for labor cost but excluded from order throughput denominators to avoid penalizing operational efficiency with administrative overhead.
  - **Zero Hours / Absence Handling**: If direct worked hours for a selected period are absent or zero, productivity is displayed as `Unavailable`, avoiding division-by-zero errors or misleading infinite/zero ratios.

---

### 7. Department Attribution and Cross-Department Labor Allocation
- **Staff Primary Department**: Each staff member has a primary department assignment (`department_id` in `staff`).
- **Transaction-Time Department Snapshots**: Attendance entries capture `department_id_snapshot` at the time of each shift. Staff promotions or department transfers take effect on an explicit date boundary and do not rewrite historical attendance attributions.
- **Cross-Department Work Allocation**:
  - When staff work across departments (e.g., a waiter assisting with kitchen prep during off-peak hours), attendance entries support multiple segments per day attributed to the respective departments.
  - Monthly earned salary is allocated to departments based on verified worked hours proportions:
    $$\text{Department Labor Cost} = \text{Monthly Earned Salary} \times \frac{\text{Verified Hours in Department}}{\text{Total Verified Hours for Employee}}$$
  - If detailed attendance hours are unavailable for an employee, their monthly earned salary defaults 100% to their primary assigned department snapshot.

---

## Worked Acceptance Examples

### Example 1: Mid-Month Hire Proration, Advance, Recovery, and Multi-Month Payment
- **Scenario**: Cook Tariq is hired on 16 October 2026. His agreed base monthly salary is PKR 46,500.00 (4,650,000 paisa). October has 31 calendar days.
- **Calculations & Ledger Entries**:
  1. **Daily Rate**:
     $$\lfloor 4,650,000 \text{ paisa} / 31 \rfloor = 150,000 \text{ paisa/day (PKR 1,500.00/day)}$$
  2. **Prorated Earned Salary (16 days worked, 16–31 Oct)**:
     $$\text{Earned Paisa} = \lfloor (4,650,000 \times 16) / 31 \rfloor = 2,400,000 \text{ paisa (PKR 24,000.00)}$$
  3. **Salary Advance on 20 October**: Tariq requests an emergency cash advance of PKR 5,000.00 (500,000 paisa).
     - Manager records `ADVANCE`: `amount_paisa = 500000`, `source = DRAWER`, `advance_delta_paisa = +500000`.
     - Drawer cash decreases by PKR 5,000.00. Tariq balance: `payable = 0`, `advance = 500,000`, `net_due = -500,000`.
  4. **October Month-End Accrual (Posted 31 October)**:
     - Manager posts `ACCRUAL` for `period = '2026-10'`, `amount_paisa = 2400000` (reason: "Prorated 16 days joined 16 Oct").
     - `payable_delta_paisa = +2400000`.
     - Tariq balance: `payable = 2,400,000`, `advance = 500,000`, `net_due = 1,900,000` paisa (PKR 19,000.00).
     - October P&L Statement recognizes **PKR 24,000.00** labor cost.
  5. **Advance Recovery (Recorded 1 November)**:
     - Manager records `RECOVERY`: `amount_paisa = 500000`.
     - `payable_delta_paisa = -500000`, `advance_delta_paisa = -500000`.
     - Cash moved = 0. Tariq balance: `payable = 1,900,000`, `advance = 0`, `net_due = 1,900,000` paisa.
  6. **Salary Disbursement (Recorded 5 November)**:
     - Manager disburses net pay via Bank Transfer: `PAYMENT`, `amount_paisa = 1900000`, `source = BANK`.
     - `payable_delta_paisa = -1900000`.
     - Bank cash outflow = PKR 19,000.00 in November money flow.
     - Tariq balance: `payable = 0`, `advance = 0`, `net_due = 0`.
- **Audit Verification**:
  - October Labor Expense = PKR 24,000.00.
  - November Labor Expense = PKR 0.00 (Payment did not duplicate expense).
  - October Cash Outflow = PKR 5,000.00 (Advance).
  - November Cash Outflow = PKR 19,000.00 (Bank Payment).
  - Total Cash Outflow = PKR 24,000.00 = Total Labor Expense.

---

### Example 2: Actual Worked Hours vs. Cashier Shift Duration & Labor Productivity
- **Scenario**: On Business Day #45 (Friday), Cashier Bilal opens register Shift #90 at 11:00 AM and closes it at 11:00 PM (12 elapsed drawer hours).
- **Physical Attendance Logged**:
  - Chef Farhan (Kitchen): 11:00 AM – 8:00 PM (1 hr break) = 8.0 worked hours.
  - Chef Zahid (Kitchen): 2:00 PM – 11:00 PM (1 hr break) = 8.0 worked hours.
  - Cashier Bilal (Counter): 11:00 AM – 9:00 PM (1 hr break) = 9.0 worked hours.
  - Manager Asif (Overhead / Management): 10:00 AM – 7:00 PM (1 hr break) = 8.0 worked hours.
- **Trading Volume**: 135 confirmed orders during the day.
- **Productivity Metric Computation**:
  - Direct Operational Worked Hours = $8.0 (\text{Farhan}) + 8.0 (\text{Zahid}) + 9.0 (\text{Bilal}) = 25.0 \text{ hours}$.
  - Management Hours (Excluded from direct denominator) = $8.0 \text{ hours}$.
  - Direct Labor Productivity = $135 \text{ orders} / 25.0 \text{ hours} = \mathbf{5.4 \text{ orders/labor hour}}$.
- **Error if Naive Shift Duration Was Used**:
  - Naive duration = 12.0 hours (Cashier shift only).
  - Distorted Productivity = $135 / 12.0 = 11.25$ orders/hr (falsely ignores kitchen labor, rendering metric useless for staffing).

---

### Example 3: Cross-Department Labor Allocation
- **Scenario**: Utility staff member Danish earned PKR 30,000.00 (3,000,000 paisa) in October 2026.
- **Logged Attendance**:
  - Kitchen Prep: 80 hours.
  - Dining Service / Floor: 120 hours.
  - Total Worked Hours: 200 hours.
- **Department Allocation**:
  - Kitchen Share = $80 / 200 = 40\% \implies 3,000,000 \times 0.40 = \mathbf{1,200,000 \text{ paisa (PKR 12,000.00)}}$.
  - Service Share = $120 / 200 = 60\% \implies 3,000,000 \times 0.60 = \mathbf{1,800,000 \text{ paisa (PKR 18,000.00)}}$.
  - Sum = PKR 30,000.00. No unallocated residue or duplicate expense.

---

### Example 4: Retroactive Salary Correction Across Closed Periods via Adjustment Bridge
- **Scenario**: In October 2026, Cashier Bilal was accrued PKR 40,000.00. On 10 November, after October Month-End reporting is sealed, the Manager verifies that Bilal was owed an approved PKR 5,000.00 bonus for October festival operations.
- **Resolution**:
  1. October sealed Z-Reports and stored report JSON snapshots remain untouched and immutable.
  2. The active November cash drawer is **not** touched with phantom historical movements.
  3. Manager logs Historical Correction under ADR-0019:
     - `target_entity_type = 'PAYROLL_ENTRY'`
     - `correction_type = 'LATE_EXPENSE'`
     - `delta_amount_paisa = +500000` (PKR 5,000.00)
     - `affected_business_day_id = 35` (Last day of October)
     - `reason = "October festival bonus approved by Owner in writing"`
  4. **Reporting Presentation**:
     - **Original Sealed October Labor Cost**: PKR 40,000.00
     - **Adjustment Bridge**: +PKR 5,000.00 (Correction #12: Bilal festival bonus)
     - **Adjusted October Labor Cost**: PKR 45,000.00
  5. When the bonus cash/bank payout is made on 12 November, it executes in November's active day as a regular net-due payment, balancing books with zero double-counting.

---

## Consequences

### Positive
- **Guaranteed P&L Accuracy**: Profitability reports accurately reflect the true cost of labor in the period it generated revenue, completely decoupled from payment settlement timing.
- **Auditable Zero Double-Expense**: Accrual creates liability and expense; payment and recovery clear liability and advances without creating duplicate expense rows.
- **Meaningful Labor Productivity**: Operational productivity metrics reflect true multi-department physical attendance rather than misleading cashier drawer durations.
- **Sealed Report Permanence**: Conforms strictly to ADR-0019; historical closed days and sealed hashes are never overwritten.
- **Complete Integer Paisa Arithmetic**: Integer floor division eliminates rounding drift and floating-point inaccuracies.

### Trade-offs & Operational Requirements
- **Manager PIN Authorization**: Accruals, proration adjustments, advances, and corrections require explicit Manager PIN authentication and audited business justifications.
- **Dedicated Attendance Collection**: To compute direct labor productivity, restaurants must capture staff attendance rather than relying on automated register timestamps. Where unlogged, reports transparently display missing-evidence disclosures rather than fabricating synthetic data.
