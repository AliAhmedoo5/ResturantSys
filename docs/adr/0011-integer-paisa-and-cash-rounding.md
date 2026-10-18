# Integer Paisa Representation and Half-Up Cash Rounding

## Context
Floating-point arithmetic (`double`) introduces binary representation errors, rounding drift, and currency discrepancies in restaurant accounting. v8 Chapter 32 mandates exact money computation and an explicit rounding rule for physical cash transactions in Pakistan (where coins/fractions smaller than Rs. 1 are obsolete in counter practice).

## Decision
All monetary values (prices, costs, discounts, taxes, tenders, and balances) are represented and stored as signed 64-bit integer paisa (Rs. 1.00 = 100 paisa). For physical cash tenders, the net cash payable is rounded to the nearest whole rupee (100 paisa) using mathematical half-up arithmetic (e.g. 50 paisa rounds up to the next rupee; 49 paisa rounds down). Digital payments (JazzCash, Easypaisa, Raast, Card) remain exact without rounding. The variance between exact total and rounded cash due is explicitly stored as `cash_rounding_paisa` and posted to a rounding variance ledger.

## Consequences
- Completely eliminates floating-point drift in ledger reconciliation.
- Cash change calculations use whole-rupee integers.
- Exact tracking of rounding gain/loss for shift and tax audits.
