# Purchasing, payroll and expenses

Schema version 19 adds the three Manager workflows without changing old stock,
cash movements, orders, or sealed reports. All new financial ledger amounts are
integer paisa. Drawer postings write their financial event and exactly one cash
movement in the same transaction; bank and owner funding create no drawer entry.

## Supplier purchasing

In Vendor Khata, select a supplier and open **Supplied items & invoices**. Select
existing ingredients/packaging or add a supplied product with its stock unit.
Removing a mapping blocks new linked receipts but preserves old invoice snapshots.
Credit delivery entry offers only linked items and accepts an optional invoice due
date. The domain controller also rejects unrelated ingredients and invalid dates.

The invoice view shows outstanding amounts, due dates, overdue invoices, and
payment allocations. Record Payment can target an invoice or automatically cover
opening payable followed by the earliest due invoices. Partial payments are
supported. Allocations must equal the payment, belong to that supplier, and not
exceed invoice or supplier due. Duplicate nonempty references and duplicate
request keys are rejected transactionally.

During upgrade, existing actual linked deliveries seed supplier-item mappings;
free-text descriptions are not guessed into mappings. Legacy payments are
reconstructed against opening payable then receipts in posting order. These are
deterministic reconstructed allocations, not evidence of historical allocation
choices. Unallocatable excess legacy payments remain in the original ledger.
Unknown due dates remain unknown. New supplier overpayments are blocked.

### Delivery commitments and receipt punctuality

Schema version 24 adds `supplier_receipt_evidence` as an immutable append-only
audit ledger capturing promised delivery deadlines, actual receipt timestamps,
and recording Manager identities. Delivery promise amendments are recorded append-only
pointing to the earlier commitment without silently overwriting historical evidence.
Receipt punctuality compares actual receipt times to recorded commitments;
unknown promises or receipts are disclosed honestly rather than classified as failed deliveries.
Stable cross-references between Mandi wholesale procurements and Vendor Khata credit purchases
unify acquisition spend and purchase counts without double-counting.

### Mandi wholesale units and Moving WAC valuation (ADR-0023)

Under [ADR-0023](adr/0023-historical-inventory-valuation-policy.md), wholesale
procurements from traditional Pakistani markets (*Sabzi Mandi* and poultry vendors)
support localized Desi purchasing units (Mann = 40kg, Pao = 250g, Dharri = 5kg, Bori = 50kg,
Darjan = 12pcs, Peti/crate item-specific):
- **Conversion Snapshots**: Purchase invoices snapshot the exact unit conversion
  multiplier and base stock unit at the moment of invoice entry (`unit_multiplier`,
  `base_unit`). Subsequent changes to unit configuration never alter historical
  stock ledger quantities or purchase rates.
- **Moving Weighted Average Cost (Moving WAC)**: Each posted purchase invoice
  updates the ingredient's Moving WAC in signed 64-bit integer paisa via:
  $$\bar{C}_{\text{new}} = \frac{(Q_{\text{current}} \times \bar{C}_{\text{old}}) + (Q_{\text{purchase}} \times C_{\text{purchase}})}{Q_{\text{current}} + Q_{\text{purchase}}}$$
- **Perpetual Negative Stock Reconciliation**: When physical deliveries arrive and are
  consumed during rush hours before invoice entry, on-hand stock may drop below zero.
  Posting the delayed invoice covers the negative stock balance at the new invoice
  rate, establishes the remaining positive stock at the invoice rate, and clears the
  temporary negative balance badge without double-deduction or checkout block.

## Payroll

Manager Portal → **Payroll** includes staff without POS login and retains inactive
staff history. Configure an effective monthly salary in YYYY-MM, then manually
accrue a period. Blank accrual amount uses the full configured salary; an explicit
amount permits approved proration with a reason. Approved earned-month policy
uses the month's actual calendar-day divisor and integer floor arithmetic; see
[earned payroll reporting](earned-payroll-reporting.md).
Salary rates are immutable and cannot change already accrued periods.

Post advances, recover them explicitly against accrued pay, and make partial
salary payments from drawer/bank/owner funds. The screen separates accrued
payable, outstanding advances, and net due. Outstanding advances are capped at one
configured monthly salary; a separate employee loan/credit policy is not enabled.
Payments cannot exceed net due after advances. Only one unreversed accrual may
exist per employee/month. Reversing an accrual allows a corrected accrual; payments
and recoveries must be reversed first if needed to keep balances nonnegative.

Reversals keep original entries and reasons. A drawer-funded payment reversal
requires returned cash and the current open drawer; it never changes a closed
shift. Accrual recognizes salary expense; payment and recovery do not recognize
it a second time.

## Expenses

Manager Portal → **Expenses** provides categories with names, descriptions, status,
sort order, allowed funding source, and optional approval threshold. Names are
case-insensitively unique. All postings already require an active Manager, so
every threshold is covered by recorded Manager authorization. A used category
archives when removed; an unused category deletes. Edit to restore an archive.
Category changes are audited and historical expenses retain category snapshots.

Record category, description, payee, amount, source, reason, and optional receipt
path. A category may be added from the entry dialog without losing the draft.
Corrections atomically reverse the original and post a linked replacement.
Standalone reversal creates a negative expense entry and returns funds to the
original source. Enter these only after funds are returned; the dialog states
their cash effect. Reversals post to the current open Business Day and current
drawer when applicable, retaining the original period and entry for audit.

Financial entries and audits reject update/delete at the database level. Request
keys prevent duplicate payroll/expense cash effects and reject mismatched replays.
Legacy generic pay-outs are not guessed into expense or payroll entries.

Analytics includes recorded expenses, posting and earned-month salary accruals,
employee balances, and current overdue invoices. Earned salary and its later
settlement remain distinct; all shared exports use the same snapshot. Historical
coverage limitations and unsupported allocations are disclosed in the report.

## Validation

Run only in GitHub Actions (CI workflow):

```text
flutter analyze --no-fatal-infos
flutter test test/finance test/widgets/operations_workspace_test.dart test/khata test/analytics test/database test/shifts
```

The tests cover migration from v18, allocation and stock integrity, partial
payments, proration, advances, recovery, duplicate requests, reversals, atomic
correction rollback, category snapshots/archive, source policies, Manager access,
and form draft retention. Full existing-suite CI is also required before merging.
