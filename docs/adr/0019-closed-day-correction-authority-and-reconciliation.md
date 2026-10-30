# Closed-Day Correction Authority, Append-Only Evidence, and Reconciliation Policy

## Context
In restaurant operations, discrepancies and late-discovered financial transactions inevitably surface after a Business Day has been formally closed with an End-of-Day Z-Report. For example, a Cash on Delivery (COD) cash pouch may be verified in the restaurant safe after day close, an unrecorded cash receipt or supplier payment slip may be found, or a delivery collection may have been recorded against the wrong shift.

Earlier naive implementations either:
1. Permitted direct mutations (`UPDATE` / `DELETE`) on closed business days, shifts, or order records, which corrupts historical accounting, breaks sealed report integrity hashes, and conceals audit fraud; or
2. Generated a fake "current-day" physical cash movement in today's active cash drawer to balance past books, which injects ghost cash into today's drawer, throwing off the active cashier's opening float, expected cash, and blind count handover discrepancy; or
3. Granted Managers operational counter rights to take live tenders or reopen cashier shifts, violating ADR-0009 (Strict Two-Role Interactive Authorization Model).

Under [Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60) and [Ticket #70](https://github.com/AliAhmedoo5/ResturantSys/issues/70), we establish the formal human policy governing closed-day corrections and reconciliation prior to implementing [Ticket #71](https://github.com/AliAhmedoo5/ResturantSys/issues/71).

## Decision

### 1. Two-Role Authorization Boundary (Manager-Only Administrative Authority)
- **Authority**: Only authenticated users with the `MANAGER` role (which encompasses Owner and Supervisor aliases) may append historical corrections via the Manager Portal after PIN verification.
- **Cashier Hard-Block**: `CASHIER` accounts have zero access to closed business days or historical correction workflows.
- **Strict Role Boundary Preservation (ADR-0009)**: Recording a historical correction is strictly an administrative audit action. It **never** grants Managers live cashier billing, cart creation, customer tender collection, or shift drawer operational privileges. Managers cannot reopen closed shifts or act as cashiers on historical days.

### 2. Append-Only Evidence Schema & Immutability Triggers
- Corrections are stored in a dedicated append-only SQLite ledger table: `historical_corrections`.
- **Columns**:
  - `id INTEGER PRIMARY KEY AUTOINCREMENT`
  - `correction_key TEXT NOT NULL UNIQUE` (idempotency key preventing duplicate submissions on network or UI retries)
  - `affected_business_day_id INTEGER NOT NULL REFERENCES business_days(id)`
  - `affected_shift_id INTEGER REFERENCES shifts(id)` (nullable; attributed to a specific shift when known, or null for whole-day adjustments)
  - `target_entity_type TEXT NOT NULL` (`ORDER_PAYMENT`, `CASH_MOVEMENT`, `VENDOR_TRANSACTION`, `PAYROLL_ENTRY`, `EXPENSE_ENTRY`)
  - `target_entity_id INTEGER` (foreign key to the original transaction if applicable)
  - `correction_type TEXT NOT NULL` (`LATE_PAYMENT_COLLECTION`, `LATE_REFUND`, `LATE_EXPENSE`, `LATE_VENDOR_PAYMENT`, `CONTRA_REVERSAL`, `DISCREPANCY_EXPLANATION`)
  - `delta_amount_paisa INTEGER NOT NULL` (Signed 64-bit integer paisa: positive for net cash inflow/receipt, negative for net outflow/disbursement)
  - `payment_source TEXT NOT NULL` (`DRAWER_CASH`, `BANK_DIGITAL`, `OWNER_FUNDS`)
  - `event_time TEXT NOT NULL` (Actual occurrence timestamp in ISO-8601 Asia/Karachi time)
  - `recorded_at TEXT NOT NULL` (Immutable system recording timestamp in UTC/Karachi)
  - `recorded_by_staff_id INTEGER NOT NULL REFERENCES staff(id)`
  - `manager_name_snapshot TEXT NOT NULL` (Captured at insert time to survive staff renaming)
  - `reason TEXT NOT NULL` (Mandatory business justification, minimum 10 characters)
  - `source_reference TEXT` (Optional receipt number, slip ID, bank reference, or courier note)
  - `reverses_correction_id INTEGER REFERENCES historical_corrections(id)` (Populated only for contra-reversals)
- **SQLite Immutability Triggers**:
  - `BEFORE UPDATE` and `BEFORE DELETE` triggers abort any modification:
    `RAISE(ABORT, 'Historical corrections are immutable')`.

### 3. Absolute Immutability of Sealed Reports and Cryptographic Hashes
- Sealed X-Reports, Z-Reports, stored report JSON, and generated report integrity hashes are **immutable and permanent**.
- A historical correction **never** rewrites closed `business_days` or `shifts` database rows, never recalculates sealed Z-Report JSON snapshots, and never modifies historical cryptographic hashes.
- Standard historical queries (e.g. "View Original Z-Report for Day #40") always return the pristine, unadjusted, original sealed report as it existed at the moment of day close.

### 4. Absolute Prohibition of Current-Day Drawer Movements for Historical Cash
- Physical cash received or disbursed in a past closed period was handled in the past.
- The system strictly **forbids** generating a `cash_movements` record in today's active shift for historical cash.
- Inserting a cash movement today for past cash would inject phantom currency into the live drawer, corrupting today's Opening Float, Expected Cash, and Blind Count Handover Discrepancy. Historical cash adjustments remain purely in the historical adjustment ledger.

### 5. Append-Only Contra-Reversals
- An erroneous historical correction can **never** be deleted or updated in place.
- If a Manager makes a clerical error when logging a correction, they must record a **Contra-Correction**:
  - `correction_type = 'CONTRA_REVERSAL'`
  - `reverses_correction_id = <original_correction_id>`
  - `delta_amount_paisa = -<original_delta_amount_paisa>` (exact mathematical inverse)
  - `reason`: Explanation of the reversal and reference to the error.
- Both the original incorrect entry and the contra-reversal remain permanently visible in the audit trail.

### 6. Reconciliation and Correction Cutoff Semantics
- When viewing historical reports in the Manager Portal, the Manager can toggle between:
  1. **Original Sealed View**: Displays the exact snapshot taken at day close without any post-close adjustments.
  2. **Correction-Adjusted View**: Displays the original snapshot alongside an explicit **Adjustment Bridge** up to a defined **Correction Cutoff Timestamp** ($T_{\text{cutoff}}$).
- **The Adjustment Bridge**:
  $$\text{Adjusted Metric} = \text{Original Sealed Metric} + \sum_{\text{recorded\_at} \le T_{\text{cutoff}}} \text{delta\_amount\_paisa}$$
- Every adjusted report and exported document (CSV, Excel, PDF) displaying adjusted data MUST clearly include:
  - The Original Sealed Value
  - The itemized list of corrections contributing to the bridge (Date, Reason, Amount, Manager Name, Event Time)
  - The Adjusted Value
  - The explicit $T_{\text{cutoff}}$ timestamp indicating the cutoff boundary.

## Worked Acceptance Examples

### Example 1: Late COD Cash Handover After Day Close
- **Scenario**: On 2026-10-25 (Business Day #40), Rider Imran delivers Order #1042 (total PKR 2,500 = 250,000 paisa, COD). Due to an evening counter rush, Cashier Bilal closes Shift #82 with a blind count without logging the cash handover pouch. The Manager closes Business Day #40 with Z-Report #40. On 2026-10-28 (Business Day #43), the Manager finds and verifies Imran's pouch in the safe.
- **Resolution**:
  - Sealed Z-Report #40 remains untouched: Cash Sales = PKR 45,000, Collection Due = PKR 2,500, Discrepancy = 0 paisa.
  - Active Business Day #43 cash drawer receives **zero** cash movements (no phantom cash in today's drawer).
  - Manager enters Historical Correction:
    - `affected_business_day_id`: 40
    - `affected_shift_id`: 82
    - `target_entity_type`: `ORDER_PAYMENT`
    - `target_entity_id`: 1042
    - `correction_type`: `LATE_PAYMENT_COLLECTION`
    - `delta_amount_paisa`: +250000 (PKR 2,500.00)
    - `payment_source`: `DRAWER_CASH`
    - `event_time`: `2026-10-25 21:30:00`
    - `reason`: "Imran COD cash pouch verified in safe after day close"
  - **Reconciliation & Reporting**:
    - Original Sealed Day #40 Report: PKR 45,000 cash, PKR 2,500 collection due.
    - Adjusted Day #40 Report ($T_{\text{cutoff}} = \text{2026-10-28 11:00:00}$):
      - Original Cash Receipts: PKR 45,000.00
      - Adjustment Bridge: +PKR 2,500.00 (Correction #1: Order #1042 COD Handover)
      - Adjusted Cash Receipts: PKR 47,500.00
      - Adjusted Collection Due: PKR 0.00

### Example 2: Late Supplier Cash Payout Slip Discovered
- **Scenario**: On 2026-10-26 (Business Day #41), PKR 3,500 (350,000 paisa) was paid to dairy supplier "Al-Madina Milk" from the drawer, but the cashier forgot to log the cash payout. Shift #84 ended with an unexplained shortage of PKR 3,500 (-350,000 paisa Discrepancy). On 2026-10-29, the vendor delivery receipt signed by the chef is recovered.
- **Resolution**:
  - Sealed Z-Report #41 remains unchanged with its -350,000 paisa Discrepancy.
  - Active drawer on 2026-10-29 is untouched.
  - Manager enters Historical Correction:
    - `affected_business_day_id`: 41
    - `affected_shift_id`: 84
    - `target_entity_type`: `VENDOR_TRANSACTION`
    - `correction_type`: `LATE_VENDOR_PAYMENT`
    - `delta_amount_paisa`: -350000 (PKR -3,500.00)
    - `payment_source`: `DRAWER_CASH`
    - `event_time`: `2026-10-26 18:15:00`
    - `reason`: "Found signed Al-Madina Milk receipt #4891 for 26 Oct delivery"
  - **Reconciliation**:
    - Adjusted Day #41 Report: Vendor Cash Disbursements increases by PKR 3,500.
    - Adjusted Drawer Variance: -PKR 3,500 + PKR 3,500 = PKR 0.00 explained variance.

### Example 3: Erroneous Correction and Append-Only Contra-Reversal
- **Scenario**: On 2026-10-29, the Manager enters a correction for Day #40 intending to record a late utility bill expense of PKR 1,200 (120,000 paisa), but accidentally types 1,200,000 paisa (PKR 12,000).
- **Resolution**:
  - The erroneous row (`id = 5`) is NOT edited or deleted (prevented by trigger `historical_corrections_no_update`).
  - The Manager records a Contra-Correction:
    - `affected_business_day_id`: 40
    - `correction_type`: `CONTRA_REVERSAL`
    - `reverses_correction_id`: 5
    - `delta_amount_paisa`: +1200000 (exact opposite of the erroneous -1,200,000 paisa)
    - `reason`: "Reversing Correction #5 due to clerical digit typo"
  - The Manager then records the intended correction:
    - `affected_business_day_id`: 40
    - `correction_type`: `LATE_EXPENSE`
    - `delta_amount_paisa`: -120000 (PKR -1,200.00)
    - `reason`: "KESC Electricity late cash payout for Day #40"
  - **Reconciliation**:
    - The Adjustment Bridge lists: Correction #5 (-12,000), Correction #6 (+12,000), Correction #7 (-1,200). Net adjustment = -PKR 1,200.00.
    - Full transparency and zero loss of audit trace.

## Consequences
- **Positive**:
  - Preserves 100% cryptographic and data integrity of historical closed days and sealed Z-Reports.
  - Guarantees today's live cash drawer is never contaminated with ghost movements from the past.
  - Maintains strict Two-Role RBAC without granting Managers live cashier register operations.
  - Provides mathematical auditability with an itemized Adjustment Bridge and explicit cutoff timestamp.
  - Allows full error recovery through immutable contra-reversals.
- **Trade-offs**:
  - Reporting logic must calculate and present both the original sealed baseline and the adjusted bridge.
  - Correction entries require manual Manager PIN authentication and explicit business justification.

