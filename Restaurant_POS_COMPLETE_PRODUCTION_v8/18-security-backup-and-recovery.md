**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 18 — Security, privacy, backups, recovery and reliability

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


## Security threat model

Assume machine accessible to staff, local offline operation, possible shared Windows login and occasional physical access by an attacker. A short PIN is convenience authentication **not a substitute for OS disk encryption or Windows account security**. Protect the database directory by Windows ACLs, strongly recommend BitLocker for machine volume, avoid storing secrets in SQLite, protect backups and staff/customer data from casual copying.

## Authentication implementation

- Each credentialed user has random per-credential salt and a slow password-based verifier (Argon2id via vetted library preferred; PBKDF2-HMAC-SHA256 with calibrated work factor acceptable for deployment constraints). 4–8 digit PINs are inherently low entropy; **per-user/drawer/device lockouts and rate limits are mandatory**.
- For uniqueness checks without plaintext, compute a keyed deterministic HMAC fingerprint of normalized PIN with a key stored via Windows DPAPI; unique equality lookup on active fingerprints. A pepper key must not be stored in SQLite or unencrypted config.
- Owner initial setup: no predefined 0000/1234 account. Validate user-confirmed PIN with anti-trivial-PIN policy (e.g., reject repeated digits/obvious sequential patterns if approved), securely initialize recovery method, record onboarding event.
- Offline brute force resistance: persisted failed counts and per-device delay, not in-memory-only counters. Account recovery requires owner-protected mechanism, with first Manager last-resort recovery procedure documented before deployment.
- Supervisor approval PIN not persisted in UI form; clear bytes on dismissal; audit approved action, never PIN content. Auth sessions auto-lock and invalidate on staff removal/role downgrade.
- Scope manager-only changes: Manager accounts, master security settings, backup restore, system encryption keys and shortcut control.

## Windows data protection

Pick app data location via platform APIs. SQLite database and attachments under restricted directory, enforce file ownership/ACLs for intended operators. DPAPI binds encryption key to install/service identity; recovery backups must include separately secured key restoration process or deliberately encrypt DB independent of DPAPI—document and test on replacement hardware. Windows OS security and backup drive physical protection are part of deployment checklist.

## Backup [BKP-01…12]

Backup is not simply `copy pos.db` while live WAL is active. Use SQLite online backup API or properly checkpointed snapshot; include all necessary WAL/page data in consistent archive. Write temp → checksum → integrity test → atomic archive rename; retain metadata schema version, business day, UTC time, app version, file size/hash, validation state and encryption envelope. Backup after day-close and configured periodic backups, plus before app migration/restore. Retention policy: daily/weekly/monthly copies, capacity check, optional removable drive and encrypted secondary off-machine destination. Drive disconnected → report pending/failed backup but do not falsely claim success. Optionally require successful backup to close day only if owner explicitly configures and runtime permits safe fallback.

## Restore [RST-01…12]

manager-only restore wizard: choose validated backup → show backup date/schema/day/time and affected data → warn that current transactions will be replaced → create pre-restore snapshot → gracefully stop writer / close SQLite → verify archive checksum/integrity and compatibility → restore atomically → migrate if necessary → run `integrity_check`, `foreign_key_check`, ledger reconciliations and authentication key check → resume. On failure automatically restore pre-restore snapshot and present explicit fault. Verify restore on replacement hardware in release readiness drills.

## Data lifecycle / privacy

Access customer phone/address only when necessary; mask in reports by default. Limit log file retention, redact secrets and personal payment data; don't put full addresses/phones into diagnostics or telemetry by default. Export owner reports may contain personally identifiable customer data only if explicitly requested and permitted. GDPR/local legal compliance decisions should be reviewed for jurisdiction; this is a software requirement specification, not legal advice.

## Failure-mode behavior

- **Power outage at checkout:** SQLite commit all or nothing; re-open returns completed idempotent result or original editable cart if not posted.
- **Disk full:** block new posting safely, preserve existing DB, surface urgent message and backup space check; do not pretend an order saved.
- **Partial file corruption:** restore wizard and read-only diagnostics; do not reset DB automatically.
- **Missing backup destination:** local secondary retries and visible owner alert, not blocking cashier unless policy dictates.
- **Unexpected close during pay-out:** one idempotent cash event or none.
- **Time skew:** persist UTC, business day chosen explicitly; warn on implausible clock drift and prohibit double day IDs.
- **Database migration failure:** pre-migration rollback snapshot, safe launch read-only/repair path and logs.

## Security/recovery acceptance

Raw PIN absent from DB/backup/logs; duplicate PIN rejected securely; wrong attempts throttle after restart; manager-only privileges enforced; cash/stock ledger unchanged by unauthorized direct command; restore from last verified archive on separate test machine with secret recovery; order totals and report Z reconcile after restore; simulated disk full and abrupt process kill do not double-post.

## External report transmission security

- Owner-approved recipient allowlist, destination verification/consent (especially WhatsApp), access audits, data minimization and retention limits for financial attachments.
- Delivery-provider credentials protected using OS or server secrets storage; never include PINs, API secrets, raw database path, raw customer addresses or unnecessary individual payroll details in default external summary.
- Sensitive report artifacts protected at rest; consider signed temporary secure download link or encrypted PDF/XLSX transport policy as approved, in addition to normal TLS sending.
- Provider failures are sanitized in UI/logs; include message ID and status only when non-sensitive. Report resend privilege and cancellation audited.
- Offline queue and report artifacts included in disaster-recovery planning. Restoring a backup must not replay all already accepted external sends without idempotency reconciliation.


## v7 image security and backup integrity

Accept only supported raster image types via magic-byte/decode validation, enforce max upload count/file bytes and decoded pixel limit, sanitize all image output with re-encode and strip EXIF (especially GPS), block path traversal, never open raw uploads as executable content. Media directory access is limited to application service; original photos and thumbnails should be included in backup/restore consistency verification. Maintain stable image IDs and database-relative paths. Deleted images should be tombstoned while dependent backup/retry jobs settle; keep media cleanup recoverable.
