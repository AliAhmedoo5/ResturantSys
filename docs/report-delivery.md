# Business Day reports and delivery

The Manager portal's **Z-Reports & Backups → Report delivery & archive** contains delivery settings, local PDF/Excel artifacts, and delivery history. The close command atomically seals shifts and Business Day records and stores a revision-1 report snapshot. An uncounted shift stays uncounted and is flagged for review. Daily pickup tokens belong to a Business Day; the next day starts at #01 without changing old token identities.

PDF and XLSX files are saved under `reports` beside the SQLite database. A report filename includes the Business Day ID/date, revision, and snapshot hash. Reports contain sales, all recorded tender methods, Collection Due separately, inventory changes, wastage, shift reconciliations, and Vendor Khata movements. Tender collection is net of explicit refunds. Drawer reconciliation uses positive physical cash receipts and subtracts refund PAY_OUT movements once, so refunded cash is never deducted twice. Monetary values in workbook columns are integer paisa; inventory quantities use the ingredient's storage unit. Customer contact details, PINs, and credentials are excluded.

Filesystem failure leaves a committed pending snapshot. The startup worker, its minute timer, or **Retry local report export** recovers it without reopening the day or repeating stock postings. Snapshots preserve the original names/balances even when catalog data changes later. A transactional export lease prevents concurrent recovery from creating duplicate artifact pairs; after an interrupted export, its ten-minute lease expires before recovery. Expected artifact checksums are saved before final files are written, so recovery verifies existing files rather than trusting changed bytes. Keep the database and reports directory together in backups. The existing automated database backup is separate from report file retention; include the reports directory in the store's backup policy.

## Configure delivery

Configure an HTTPS relay URL and Manager-approved email recipients. Optional WhatsApp recipients need an international number and a recorded consent basis. The relay must use a real transactional email service or the official WhatsApp Business Platform with its required business/account/template approvals. Installing this application does not provision those services.

Provide a scoped relay bearer credential using the `RESTAURANT_REPORT_RELAY_TOKEN` process environment variable. Do not put provider master keys, tokens, or credentials in the URL, SQLite settings, source code, or report attachments. The relay endpoint may not contain user credentials, query parameters, or fragments. Its TLS certificate must validate normally.

Enable automatic-on-close. The close snapshot records approved destinations and relay endpoint; ready artifacts create one durable automatic `report_outbox` job per channel/recipient. Later recipient or endpoint edits never redirect an old job. Revoking the target, disabling automatic delivery, or changing the relay endpoint cancels outstanding old jobs when the worker next examines them. Changing settings applies to future closes.

## Relay contract

The application POSTs JSON with an `Authorization: Bearer …` header and stable `Idempotency-Key`. The body includes:

```json
{
  "report_run_id": 42,
  "revision": 1,
  "business_date": "2026-10-23",
  "snapshot_sha256": "<sha256>",
  "channel": "EMAIL",
  "recipient": "owner@example.invalid",
  "consent": "",
  "subject": "Business Day 2026-10-23 — Z Report",
  "idempotency_key": "<stable sha256>",
  "attachments": [
    {"kind": "pdf", "sha256": "<sha256>", "content_base64": "<bytes>"},
    {"kind": "xlsx", "sha256": "<sha256>", "content_base64": "<bytes>"}
  ]
}
```

Local filesystem paths are removed before transmission. The desktop verifies every attachment digest before submission. The relay must durably deduplicate `Idempotency-Key`, retaining the result across retries, and submit each channel through its approved provider. It must return a 2xx response only with explicit provider acceptance evidence:

```json
{"accepted": true, "provider_reference": "provider-message-id"}
```

HTTP success without this evidence is ambiguous. The application records **ACCEPTED**, which means provider submission accepted; it does not claim inbox receipt or confirmed WhatsApp delivery. Provider delivery callbacks are not part of this desktop implementation.

429 and 5xx responses schedule bounded exponential retries with a deterministic per-job offset. Connection failure persists a pending retry. Invalid configuration and permanent rejection stop retries. A timeout or an expired in-flight lease is **AMBIGUOUS** because the provider may have accepted the request. Check relay/provider history before explicitly retrying with a required Manager reason. The same idempotency key remains in use, so the relay must return its original result rather than duplicate a submission. Delivery history masks destination addresses in the UI and displays sanitized errors.

The worker runs once at app startup and every minute while the app remains open. It claims jobs transactionally, attempts at most 20 per tick, and records attempt counts/schedules in SQLite. Jobs remain durable when the PC is off; sending resumes when the app is running again. Network delivery never runs inside the Business Day seal transaction. Neither network nor local export failure can reverse a committed close.

## Validation

Framework analysis, tests, and generated artifact checks run in GitHub Actions only. The tests use temporary SQLite databases and synthetic fixture data, not the installed restaurant database. Approved seams cover atomic close/checkout, real local report files, and outbox retry with a failing transport adapter; live provider delivery is outside these tests.
