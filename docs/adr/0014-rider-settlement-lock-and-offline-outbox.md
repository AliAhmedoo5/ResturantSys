# Rider Trip Settlement Lock and Offline Report Outbox

## Context
Delivery cash collection and end-of-day reporting are critical financial boundaries prone to race conditions, network failures, and data manipulation. If orders could be amended after a rider settles their cash pouch, cash variance reconciliation would be corrupted. Similarly, requiring an internet connection to send end-of-day reports risks hanging the physical store closure during nighttime internet dropouts.

## Decision
1. **Rider Trip Settlement Lock**: When a Cashier acknowledges a rider's cash handover and marks the trip `Settled`, all orders on that trip are permanently locked from direct line or price revisions. Any subsequent adjustment requires a separate document.
2. **Offline Report Outbox**: Business Day Z-Close atomically commits all financial tallies and saves PDF/Excel reports locally on disk. Automated report dispatch (Email / WhatsApp) is enqueued into an SQLite-backed offline outbox with background retry logic. Internet failure never blocks local register day closure.

## Consequences
- Cashier and rider shift handovers are mathematically immutable once settled.
- Restaurant operations close reliably without network dependence.
- Outbox ensures no reports are lost during internet downtime.
