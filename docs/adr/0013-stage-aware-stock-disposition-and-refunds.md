# Stage-Aware Stock Disposition and Decoupled Refunds

## Context
When an order is revised or canceled after confirmation, handling physical stock and collected customer money naively leads to fraudulent drawer shortages or fake inventory balances. In fast-food preparation, once ingredients have been grilled, fried, or assembled into a cooked burger, they cannot be returned to raw bulk inventory if the customer changes their mind. Similarly, canceling an order must not silently disburse money from the till.

## Decision
1. **Stock Disposition**: All order item removals during revision or cancellation require an explicit `bom_disposition`:
   - `RESTOCK_RAW`: Ingredients return to stock ONLY if preparation has not commenced (`Confirmed` stage).
   - `WASTED_COOKED`: Ingredients are posted to kitchen waste ledger if preparation is active or complete (`Preparing`, `Ready`, `Out for Delivery`).
2. **Decoupled Refunds**: Revisions resulting in reduced payable amounts or cancellations of prepaid orders create a `Refund Owed/Pending` state. An actual refund requires a separate, explicit cashier disbursement action (drawer cash payout or manual digital transfer verification).

## Consequences
- Guarantees raw inventory counts match physical stock in the store room.
- Prevents unverified cash leakage from the till during rush cancellations.
- Maintains an auditable chain of financial transactions.
