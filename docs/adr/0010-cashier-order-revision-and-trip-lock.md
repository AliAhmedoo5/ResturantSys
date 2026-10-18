# Autonomous Cashier Order Revisions and Settlement Lock

## Context
Earlier designs required a Supervisor PIN to cancel or void settled orders (using an `order_voids` table). This created counter bottlenecks during fast-food rushes. The v8 authoritative policy (Chapters 30, 32) grants the Cashier full autonomy to revise (add/remove items, adjust quantities) or cancel confirmed orders without a Manager PIN while the order is in `Confirmed`, `Preparing`, `Ready`, or `Out for Delivery`, provided its associated rider trip has not reached `Settled`.

## Decision
We replace the legacy Supervisor PIN Void mechanism with an append-only revision engine backed by `order_revisions` and `order_revision_lines` tables. The Cashier executes modifications and cancellations with a required reason. Once a delivery order's associated rider trip reaches `Settled` (or the Business Day closes), direct line edits are locked permanently. Refunds of collected funds are tracked as separate financial disbursement actions, never automatic upon cancellation.

## Consequences
- Eliminates manager approval overlays during counter rushes.
- Full traceability through immutable before/after snapshots and money/stock deltas.
- Prevents post-settlement audit fraud by enforcing the rider trip settlement lock.
