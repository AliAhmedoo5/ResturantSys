**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 15 — Production architecture, offline operation and deployment

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Technology baseline

- Flutter stable (Windows), Dart, Material 3 themed with fully custom operational components.
- Riverpod for state orchestration and local reactive queries; GoRouter for role-aware navigation; Drift + SQLite for persistent data and migrations.
- `sqlite3` native bundled appropriately; WAL mode and transactional persistence. Determine file paths using platform storage APIs instead of hardcoding administrative protected paths. Use secure Windows installer/AppData location appropriate to service account, backup and multi-user access; apply ACLs.
- Use pure Dart value/domain services for monetary calculations, inventory conversions, order state machines and permission guards; Flutter widgets never issue raw SQL.
- decimal/integer arithmetic: store amounts as `INTEGER` **paisa**, rates/quantities with specified scale or decimal string conversion library, converting only at audited DB boundary. Never use `double` for financial balance.

## Layers and folders

```
lib/
  bootstrap/            # first run, database check, logger, clocks
  app/                  # router, theme, shell, role-based navigation
  core/{money,units,time,errors,permissions,ids,domain_events}/
  data/{database,migrations,dao,transactions,backup}/
  features/
    authentication/ business_days/ shifts/ staff/ payroll/
    pos/ catalog/ deals/ discounts/ customers/ orders/ refunds/
    delivery/ riders/ stock/ wastage/ procurement/ suppliers/
    cash/ expenses/ reports/ settings/ shortcuts/
  shared/widgets/
```

Domain interfaces isolate persistence and UI. A single **transaction coordinator** orchestrates side effects for posted actions. Report repository reads ledger projections, not UI state. Maintain testable adapters for time/IDs and future print/payment integrations.

## Order checkout atomicity

`confirmCheckout(intentKey, draftRevision, actor)`:

1. Permission and active business day/shift validation.
2. Re-read current catalog, effective price, deal, discount and availability; compare draft revision and show conflicts before final confirm.
3. Compute money, tax allocation/rounding, package and BOM requirements in deterministic pure function.
4. In one DB transaction enforce unique idempotency key, reserve/allocate business day token, insert order/lines/snapshots, initial status, receivable/payment allocations, consumption ledger, audit event and committed intent result.
5. Commit. Return persisted order ID and total. Outside transaction, optionally generate digital receipt, nonblocking report-cache invalidation and UI success.
6. Crash/retry on same intent key returns original order, not second order.

## Offline persistence and concurrency

- SQLite WAL for readers and single writer serialized transactions, explicit busy timeout, foreign keys ON, indexes and checkpoint policy.
- Use one repository writer command queue for conflicting ledger mutations; provide progress and limited retry for `BUSY`, preserving idempotency key.
- No network dependency for billing, supplier postings, PIN unlock, reports on local data or backups.
- Do **not** put one writable SQLite file on LAN share/SMB for multiple tills. Future multi-terminal model: one local on-premises transaction service with authenticated clients, explicit sync and central locking; redesign sync conflicts before enabling it.
- Business day/shift locks transaction-time checked even if UI is stale; prevent late order into closed day.
- Cross-process multi-instance guard for same DB file; second app instance may open read-only tools or focus existing app, not create independent writers with competing shift context.

## Data snapshots and projections

Price, tax, discount, modifier, address, deal choices and unit conversion factor snapshot on finalized source transaction. Ledger is immutable; projection tables/current balances may be rebuilt from events. For reporting speed maintain versioned summary cache invalidation on new events with verified reconciliation queries. Migrations must preserve all old snapshots.

## Backup, restore and encryption boundaries

See security file. Auto-backup after business day close and timed backups while operating (policy), WAL-consistent SQLite backup API/checkpoint method, write to temp file then atomic rename, checksum, optional secondary drive; verify opening and sample integrity. Restore only while writer stopped after safeguarded pre-restore backup; test full reopen/migration and report. Distinguish operational SQLite integrity from secret-key recovery (DPAPI machine context).

## Windows operations

Create signed MSI/MSIX or trusted installer appropriate to deployment, install app binary separate from writable data. Full-screen kiosk-like option but accessible OS controls. Startup preflight shows database/backup health, current business day and shift; no arbitrary demo seed in production. Automatic logging with secret/phone redaction, exportable diagnostic report without money manipulation. Provide safe app upgrade/migration and rollback copy.

## Performance targets and monitoring

Design targets (not user-approved SLAs): POS keyboard input responsive <100ms typical; product tile action visible <150ms; database local checkout typical <500ms for ordinary basket on target hardware; customer search <300ms with normalized phone index; report of one-month data completes without blocking cashier input. Performance measurement with realistic 50k+ orders and 100k+ ledger events, long catalogs and Excel exports. Domain work on appropriate isolate when needed; no UI-thread heavy aggregation.

## Versioning and migration

Drift schemaVersion integer; forward-only tested migrations in upgrade path with pre-migrate backup; no wipe-and-recreate on production user data. Version settings and report formulas, inventory costing and payment status changes. SQLite PRAGMA `foreign_key_check` and `integrity_check` as maintenance operations. CI tests migrate old fixtures into current schema and compare key ledger totals before/after.

## Dependencies and interfaces

Interface seams: `Clock`, `UniqueIdGenerator`, `PinCredentialService`, `OrderCommandService`, `LedgerTransactionCoordinator`, `CatalogRepository`, `InventoryPostingService`, `ReportQueryService`, `BackupService`, `DigitalReceiptService`, and optionally future `PaymentVerificationAdapter`, `PrinterAdapter`, `MultiTerminalSyncAdapter`. No direct or automatic banking/card settlement is assumed.

## Durable report delivery outbox [ARCH-SEND]

`ReportGenerator` produces immutable artifacts from committed `DayCloseSnapshot`, stores content digests and report metadata. `ReportOutbox` transactionally queues immutable jobs keyed by `(business_day_id,revision,channel,recipient,purpose)`. `DeliveryWorker` claims leases, retries with backoff and idempotent provider client; state and error history survive restart. Provider interface `sendEmail(artifactRefs,recipient,template)` / `sendWhatsAppDocument(...)` is separate from domain order and close service. API keys/WhatsApp credentials MUST NOT be embedded as readable source or plain bundled app secrets; use OS secret protection for device-scoped secrets and preferably a backend relay for shared remote credentials. Manual WhatsApp is a distinct local UI share action. The local worker needs Windows process/service running; no false offline delivery guarantees.


## v7 offline catalog media architecture

Store originals and compressed thumbnails in protected app data path (`media/catalog/...`), referenced using normalized relative paths and content hashes in SQLite. Import pipeline: validate magic bytes and supported raster formats → decode with pixel/dimension bounds → strip metadata → resize/compress thumbnails → stage temp file → write metadata transaction → atomic rename/finalize with recoverable cleanup job. On app launch, reconcile incomplete staged images; verify missing thumbnails and rebuild from original where safe. All gallery changes operate on media IDs, not file names. Image cache must be bounded and asynchronous; no HTTP/image CDN needed. SQLite backups must include corresponding catalog media (or a manifest + deterministic media archive); restore validates file hashes and rebuilds thumbnails as needed.
