**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 03 — Staff, departments, PIN authentication, salaries and advances

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Staff master [STA-01…08]

- [STA-01] Manager can create a person with name, staff code, phone (optional), department, employment date, active flag, salary scheme and optional POS role; validate unique staff code and mandatory name.
- [STA-02] Editable fields: name/contact/department, pay rate, start/end date, status; all changes versioned with actor/time. Salary effective dates prevent retroactive edits to closed payroll periods.
- [STA-03] Archive/deactivate instead of hard deleting any staff referenced in sales, approvals, cash, inventory or payroll. Only truly unused staff can be hard deleted with confirmation and log.
- [STA-04] A person can belong to any custom department but only their assigned authorization role controls app privileges. Kitchen/rider employment without PIN is allowed.
- [STA-05] Staff detail tabs: Profile, POS Access, Salary & Advances, Payments, History. Search by name, role and department; filter active/archived.
- [STA-06] Deactivation immediately invalidates local active sessions and prevents future privileged approvals.
- [STA-07] Changing an employee's system role is independently audited from changing department or salary.
- [STA-08] Include date/actor in all salary, advance and staff credential changes; show no sensitive PIN value in UI.

## Credentials [PIN-01…08]

Create Cashier or Manager POS credentials at staff creation or later. PIN is 4–8 numeric digits, entered twice, unique across all active login credentials. Duplicate attempt shows generic "Choose another PIN"; it must not expose the matching staff member. Manager may create/edit Cashier and Manager PINs; Manager account creation requires reauthentication and audit. No Owner tier exists. Manager reauthentication required for high-risk Manager credential changes. Credential rotation invalidates target sessions. Wrong attempts throttle per staff candidate/device; lockout and recovery follow Manager-managed security policy. Never put raw PIN in memory beyond the shortest practical verification scope. Password/PIN KDF and fingerprint policy in Security document.

Do **not** simply put UNIQUE on a plaintext PIN column. Use a keyed equality fingerprint for collision detection and a separate rate-limited salted verifier. The installation key belongs in Windows DPAPI, not SQLite or export.

## Payroll configuration

Support salaried employee baseline and optionally daily wage/shift wage as configurable schemes (the latter may be phase 2 if not needed at launch). Employee pay terms have effective-from date, PKR rate and manager who approved. Payroll period has start/end business date, employee snapshot, gross earning, adjustments/advance deductions, total payments and remaining liability.

### Ledger model [PAY-01…10]

- **Salary earned** creates liability for employee; **advance paid** creates employee recoverable; **salary payment** consumes available salary liability; **advance deduction** reduces recovery balance and salary liability but does not spend cash again.
- A cash-funded salary payment or advance posts one drawer pay-out and one employee-ledger event in the same transaction. Bank/owner funded payment never modifies register cash.
- Manual recurring salary accrual must be idempotent by `(employee, period, component)`. Support partial payments and multiple advances in the same period.
- An advance should not simply be subtracted from "gross salary" historically; present it separately as an already-paid recoverable balance and explicit settlement allocation.
- If employment terminates mid-period, prorate based on configured rule; no hardcoded 30-day monthly divisor without manager approval.
- Manager can record pay/advance under policy and view all payroll and history. Any post/void/reversal requires reason and audit.
- Disallow negative salary/advance amounts and overpayment without explicit staff-credit/loan policy.
- Advance write-off, benefits, deductions and legal payroll compliance are explicit later policies, not magic numbers.
- Financial reports separate gross pay expense, outstanding payables, cash paid and advances; do not count payroll paid as another expense if already accrued.

## UI flows

**Add staff:** Staff → Add → name, department, pay → optional POS login toggle → role → PIN and confirm → validate uniqueness/role → save → profile appears with `Login active` status and no PIN exposure.

**Edit staff:** Staff → search → detail → edit authorized fields; salary changes ask effective date. Role change triggers explicit privilege confirmation. Reset PIN with mandatory reason and authorization.

**Pay salary:** Staff → salary ledger → select period → show earned, paid, advances, recoveries, due → enter amount, funding source and note → confirm → cash/payroll entries atomically saved; receipt reference shown.

**Advance:** employee → New advance → amount/source/reason/date → post → shows outstanding employee advance and corresponding funding outflow.

## Edge cases

Duplicate PINs including deactivated? Default: disallow reuse among active credentials; retention policy should block recently retired PIN reuse as extra protection. Supervisor tries to create owner → denied. Cashier attempts role-switch via UI/backend command → denied. Deleting a staff member with cash movement → offer archive. Salary change during approved period → new effective period or correction record. One cash payment accidentally re-submitted → idempotency prevents duplicate.

## Acceptance tests

- Create cashier and supervisor with different PINs; both login and land on appropriate permitted workspace.
- Duplicate PIN across roles rejected; stored raw PIN absent from SQLite export/logs.
Manager (Supervisor/Owner) is the only management role, with identical permissions for both titles; Manager can administer and approve but cannot perform cashier tasks. See chapters 01 and 24.
- Staff with history cannot hard delete; archived remains visible in ledger and reports.
- Salary accrual, advance, salary payment and deduction each appear once and reconcile to cash source.
- Rotate PIN then old session and PIN fail appropriately.


## v6 compulsory cashier setup

First-run wizard MUST create initial Manager, then require a separate enabled Cashier with unique **4-digit PIN** (later staff PINs can follow 4–8 policy) before completing initial setup. After Manager opens business day, switch to Cashier session, record opening shift float and then enable sales. Do not give Manager cashier access even during wizard.
