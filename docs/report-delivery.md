# Business Day reports and delivery

The Manager portal's **Z-Reports & Backups → Report delivery & archive** contains delivery settings, local PDF/Excel artifacts, and delivery history. The close command atomically seals shifts and Business Day records and stores a revision-1 report snapshot. An uncounted shift stays uncounted and is flagged for review. Daily pickup tokens belong to a Business Day; the next day starts at #01 without changing old token identities.

PDF and XLSX files are saved under `reports` beside the SQLite database. A report filename includes the Business Day ID/date, revision, and snapshot hash. Reports contain sales, all recorded tender methods, Collection Due separately, inventory changes, wastage, shift reconciliations, and Vendor Khata movements. Tender collection is net of explicit refunds. Drawer reconciliation uses positive physical cash receipts and subtracts refund PAY_OUT movements once, so refunded cash is never deducted twice. Monetary values in workbook columns are integer paisa; inventory quantities use the ingredient's storage unit. Customer contact details, PINs, and credentials are excluded.

Filesystem failure leaves a committed pending snapshot. The startup worker, its minute timer, or **Retry local report export** recovers it without reopening the day or repeating stock postings. Snapshots preserve the original names/balances even when catalog data changes later. A transactional export lease prevents concurrent recovery from creating duplicate artifact pairs; after an interrupted export, its ten-minute lease expires before recovery. Expected artifact checksums are saved before final files are written, so recovery verifies existing files rather than trusting changed bytes. Keep the database and reports directory together in backups. The existing automated database backup is separate from report file retention; include the reports directory in the store's backup policy.

## Configure delivery

### Direct Gmail (default for new setups)

In **Delivery settings**, choose **Gmail**, enter the restaurant's Gmail address,
and enter a Google **app password**. Enable 2-Step Verification in that Google
account first, then create an app password at
<https://myaccount.google.com/apppasswords>. Use a dedicated restaurant account.
Some managed or Advanced Protection accounts cannot create app passwords.
A normal Google account password is not supported. No domain, hosted relay,
paid mailbox, or Google Cloud project is needed for this app-password setup.

Enter the approved email recipients and enable automatic delivery. The sender
uses `smtp.gmail.com:465` with TLS and sends the saved PDF/XLSX bytes after
checking their hashes. It never uses a payment gateway or changes day-close
accounting. The Google app password is stored using platform secure storage
(protected by Windows credentials on Windows), scoped to this installation and
Windows user. SQLite, reports, audit events and outbox payloads contain no app
password. A blank password field keeps the existing saved credential. **Remove
saved Gmail password** disconnects it. Changing your Google password revokes
app passwords; generate and save a replacement to resume sending.

Restoring a database on a different PC or Windows account requires entering the
app password again. Never include it in support logs, source code, or database
backups. Updating the saved password for the same sender can resume existing
jobs; changing the Gmail sender or delivery provider cancels old queued jobs
instead of silently submitting them through another identity.

Personal Gmail sending limits apply (Google documents a 500-email/day limit).
The app caps combined report attachment bytes at 18 MiB to allow for MIME/base64
expansion. Successful SMTP submission means **ACCEPTED**, not confirmed inbox
delivery. Known connection failures get durable automatic retries. A connection
interruption or timeout that might have happened after submission is
**AMBIGUOUS**: check the sender's Gmail Sent mail before requesting a retry.
A stable Message-ID helps identify the report, but Gmail SMTP does not provide
an idempotent send API or a guarantee against duplicate delivery after a manual
retry. The PC and POS must be running to send queued reports.

Setup references: [Google app passwords](https://support.google.com/mail/answer/185833),
[Gmail sending limits](https://support.google.com/mail/answer/22839).

### Existing HTTPS relay

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
