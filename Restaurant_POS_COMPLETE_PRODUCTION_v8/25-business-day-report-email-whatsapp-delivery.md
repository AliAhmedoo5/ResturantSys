**AUTHORITATIVE v8 OPERATIONAL POLICY (12 October 2026):** CASHIER may revise or cancel an already confirmed order without Manager PIN; record original and revised versions, reason, cashier, timestamps, price/payment changes and inventory disposition. This does not authorize silently returning money: any separately executed refund must be documented, limited to refundable collected funds and reconciled with actual cash/external refund evidence, with no routine Manager PIN unless a separately approved exception policy is established. Stock must NEVER block cashier checkout for zero/negative ingredient or packaging balances: post full BOM consumption once, permit negative balances, alert, and let later receipts reconcile naturally without delayed second deduction. Cash, card, Raast/bank transfer, JazzCash, Easypaisa and split payments are MANUALLY confirmed/recorded by the Cashier—NO payment APIs are required. COD may remain unpaid after delivery until collected/settled. Two system roles only: Cashier and Manager (Supervisor/Owner same role); Manager cannot do cashier operations. Refer to chapters 30–32; chapter 32 overrides older order-lock/rounding/tax/token/onboarding/modifier wording.

# 25 — Automatic and manual end-of-business-day report delivery (email / WhatsApp)

> **AUTHORITATIVE ROLE POLICY (v5):** There are exactly TWO interactive POS authorization roles: **Cashier** and **Supervisor/Owner (Manager)**. “Supervisor” and “Owner” are interchangeable titles for the **same Manager role**, with identical permissions and no manager-only tier. **Manager must not perform cashier operational tasks**: no POS bills/cart/checkout, customer order creation or editing, cashier discounts at checkout, payment collection, cashier shift opening/counting, order preparation/dispatch/delivery updates, or rider cash intake. Manager instead administers catalog, deals, discounts, employees/PINs, stock, suppliers/Khata, management cash/expenses, reports, day opening/closure, configuration, exceptions and approvals. Manager may READ operational order/shift/settlement details and APPROVE a cashier's protected action without becoming that cashier. Staff without POS access are not an additional interactive role. Apply this rule to every screen, command, shortcut, test and data migration; any older contradictory statement is superseded.


**Feature status:** newly requested and included as a production module. Email with PDF/Excel delivery is the **recommended first-release implementation**; manual WhatsApp sharing is a practical optional first-release shortcut; automated WhatsApp Business Platform is an explicit integration phase requiring a configured provider/account, internet and appropriate recipient consent. Owner must approve final channel, pricing and retention policy. Do **not** claim that WhatsApp delivery works offline.

## 1. Goals [SEND-01…12]

- [SEND-01] On finalized business-day close, generate immutable-versioned **Z-report PDF**, detailed **XLSX workbook**, and optional **CSV** based on committed local data; include business date, timezone, restaurant, report generation time, revision/hash, and event range.
- [SEND-02] Save generated reports locally and record `report_run_id`, `business_day_id`, file path, digest, version, snapshot cutoff, creator and generated time. Day close success is independent of network delivery.
- [SEND-03] Manager configures a list of verified/approved email recipients; owner may separately approve WhatsApp recipients and their permission/consent state.
- [SEND-04] Manager configures enabled channels, attachment choices, auto-send on close, retry policy, confidential financial sections, subject/template and whether supervisors may manually resend.
- [SEND-05] Manager can select **Send now** from an authorized closed-day report and see clear delivery attempt state: Queued, Sending, Provider accepted, Confirmed delivered (only with provider evidence), Failed retryable, Failed final, Cancelled. **Provider accepted is not proof of inbox receipt.**
- [SEND-06] When offline, enqueue locally durable delivery jobs with complete immutable report references; retry later using backoff and bounded attempts. Never generate a duplicate report just to retry sending.
- [SEND-07] Idempotency: unique `business_day_id + report_revision + channel + recipient + template_version + delivery_purpose` or equivalent stable key; explicit resend creates an auditable new attempt without duplicating the original automatic job.
- [SEND-08] A failed email/WhatsApp send does not roll back a closed business day, reopen a cash shift, duplicate stock postings or change Z totals.
- [SEND-09] Report access is restricted, reports exclude PINs, credential hashes, system secrets and unnecessary customer PII; recipient email/phone and attachments treated as sensitive.
- [SEND-10] Delivery history is available to supervisor/owner; owner can disable a channel, revoke recipients and inspect retry/error reason without exposing API secrets.
- [SEND-11] If PC is powered down with a queued job, a **local-only** implementation cannot send until the Windows worker runs again. If sending must continue while store PC is off, use a cloud service *after* securely uploading and queuing the immutable artifact while internet is available.
Manager (Supervisor/Owner) is the only management role, with identical permissions for both titles; Manager can administer and approve but cannot perform cashier tasks. See chapters 01 and 24.

## 2. Operator workflows

### A. Owner one-time setup

1. **Settings → Reports → Delivery settings**. Switch on Email and/or WhatsApp, choose automatic-on-close and allowed manual resends.
2. For Email: set verified sender/domain/provider, owner recipients, CC/optional staff recipient list, PDF + Excel toggles, subject and approved summary sections. Tap **Send test report**; show delivery attempt status.
3. For WhatsApp: choose **Manual** or **Official API**. Manual opens WhatsApp/chat and allows the operator to attach file; cannot silently attach+send from a plain share link. Automatic requires a supported business provider account, sender/business phone, correct API credentials, approved message template for business-initiated delivery as required by platform rules, recipient permissions and cost/limits review.
4. Set schedule: recommended trigger **After business day successfully closes**, not at a fixed midnight. Enable additional scheduled summary only as an optional separate operation (no duplicate accounting day closure).
5. Set retry window, max attempts, retention and encryption. Save and audit changes; test delivery. Owner sees which channels are ready and any configuration blocker.

### B. Supervisor closes the day

1. Supervisor resolves or acknowledges outstanding shifts, rider cash discrepancies, supplier payables, refunds and stock exceptions according to blocking/non-blocking rules.
2. Supervisor reviews Z-report, counted cash and financial warnings; selects **Close & Lock Business Day**.
3. One atomic close transaction persists `closed_at`, `closed_by`, final totals/snapshot reference and immutable close event. Generating report artifact uses committed state; report delivery is a separate workflow.
4. PDF and XLSX are saved to local protected report storage; `report_run` and attachment checksums are recorded.
5. For each enabled approved recipient and selected channel, create an outbox record. If internet available, worker submits; if not, mark **Queued — waiting for connection**.
6. Close success view shows separately: **Business day closed**, **PDF generated**, **Excel generated**, **Email queued/sent/failed**, **WhatsApp queued/sent/failed**. A failed send cannot undo closure.
7. Supervisor can open **Reports → Delivery History** and retry permitted failed jobs. Reason must be required when deliberately resending a successfully submitted report to avoid accidental duplication.

### C. Owner receives report

Email subject example: `Restaurant — Business Day 2026-10-12 — Z Report` (business day, not necessarily calendar send date).

Message text example (illustrative values, never hard-code):

> Restaurant Daily Business Report — 12 Oct 2026  
> Net sales: Rs. 85,400  
> Orders: 78  
> Cash variance: Short Rs. 300  
> Supplier payables: Rs. 42,000  
> Pending rider cash: Rs. 3,100  
> Attachments: Z_Report_2026-10-12.pdf; Daily_Operations_2026-10-12.xlsx  
> Generated from finalized business-day records. Review exception details in the attached report.

A WhatsApp message may include a short approved summary and, using the official API when configured, send a document attachment supported by the current provider/platform constraints. Template/media requirements vary: confirm current Meta policy and limits at integration time rather than encoding assumptions in the domain.

## 3. Delivery modes and responsibilities

| Mode | Sending mechanism | Required infrastructure | What it can promise |
|---|---|---|---|
| Email automatic | HTTPS transactional email service or authenticated SMTP relay | Working internet; protected secrets; configured sender, sender reputation | Can attach PDF/XLSX and observe provider submission status |
| Email manual | Open mail client with recipients/subject and let user attach report; optional shell share | Configured mail client; human action | User-controlled sending, no automatic guarantee |
| WhatsApp manual | Open approved WhatsApp chat or share workflow | App/browser and human attaching document | Convenience only; never mark 'Sent' unless user confirms |
| WhatsApp automatic | Official WhatsApp Business Platform / supported provider | Business setup, template/recipient permission, secured integration, internet | Automated messages/documents subject to template, size, delivery and platform policies |
| Cloud relay | HTTPS upload to secure service, server processes queue and callbacks | Cloud hosting, authentication, encryption, support operation | Can keep processing after desktop goes offline **only when job was uploaded first** |

**Recommended architecture:** Flutter calls application `CloseBusinessDay` command → Drift transaction → `ReportGenerationService` writes versioned files → `ReportOutboxRepository` → Windows worker/service while app is running (optionally service independent of UI) → `EmailTransport` or `WhatsAppTransport`. For API token safety, prefer a controlled backend relay with short-lived desktop authentication; do not ship long-lived master API keys in the distributed binary.

## 4. Settings and UI contract

**Settings → Delivery:** delivery enabled; channels; sender identity; verified recipients; WhatsApp mode and approved numbers; auto-on-close; PDF/XLSX/CSV options; report section visibility; test; retry; report password/encryption/secure-link mode; recipient validation; live health/status of channel. Manager manages credentials/global recipients with audited changes.

**Close day:** report preview; generated file choices; `Email owners` and `WhatsApp owners` statuses; prevent re-closing and duplicate job creation. Show queued badge and meaningful retry time.

**Delivery History:** business date, report revision, channel, recipient (partially masked), queued time, latest attempt, provider reference, attempt count, status, sanitized error, retry action, manual resend action. Filter by status/date/channel.

## 5. Minimal logical schema

```text
report_runs(id, business_day_id, revision, snapshot_cutoff_utc, created_at_utc,
  created_by_staff_id, status, content_hash, schema_version, locked)
report_artifacts(id, report_run_id, kind[pdf|xlsx|csv], storage_path,
  size_bytes, sha256, encryption_info, created_at_utc)
report_recipients(id, channel[email|whatsapp], address_encrypted,
  masked_address, verified_at_utc, consent_basis, active, created_by)
report_delivery_policies(id, enabled, channel, purpose, auto_on_close,
  attach_pdf, attach_xlsx, attach_csv, allow_supervisor_resend,
  retry_max, retry_backoff_policy, report_scope, created_by, updated_at)
report_delivery_jobs(id, report_run_id, recipient_id, channel, purpose,
  unique_idempotency_key, requested_by, requested_at_utc,
  state, next_retry_at_utc, attempt_count, latest_error_code)
report_delivery_attempts(id, job_id, attempted_at_utc, provider_request_id,
  provider_message_id, result, sanitized_error, response_code, duration_ms)
report_delivery_events(id, job_id, source, state, provider_event_id,
  happened_at_utc, received_at_utc)
```

Use a job lease or transactional state claim to prevent two workers sending the same job concurrently. Account for a crash after the provider accepts a request but before local success is saved: stable provider idempotency keys if supported, or explicit ambiguous-delivery status requiring guarded retry.

## 6. Failure behavior and security

- **Internet disconnected on close:** local day close and file generation succeed; queued job persists, due after reconnection. Do not repeatedly prompt cashier during checkout.
- **Provider rejects credentials:** mark failed with actionable owner message; never log secret contents. Retry only after credential/configuration fix.
- **Unknown recipient, wrong number or invalid format:** owner corrects recipient; old attempts remain in log; never silently change destination of an already queued job.
- **API rate limit / temporary outage:** exponential backoff with jitter; configurable maximum; no hot polling.
- **Attachment too large:** keep immutable report and offer secure link/passworded archive policy or smaller PDF summary; disclose delivery truncation and never silently omit detailed workbook.
- **Sensitive report sent to wrong recipient:** disable destination, audit incident, rotate any exposed access credentials, apply report retention/access controls. Do not include customer phones and staff payroll details in default WhatsApp summary.
- **Reports generated more than once for the same closed day:** create explicit version/revision with old report retained and reason if corrected snapshot permitted; no silent overwrites.
- **Worker restarts mid-send:** lease expiry recovery, deduplicated attempt and ambiguous status monitoring.
- **WhatsApp read/delivery status:** only mark Delivered when real provider callback/confirmation exists; otherwise 'Submitted/Accepted' at most.
- **Backups:** report artifacts, outbox and recipient settings need backup/restoration policy. Encrypt sensitive addresses, tokens and file archives per security standard.

## 7. Acceptance scenarios [SEND-QA]

1. Offline close → PDF/XLSX persisted, email queue pending → restart app still pending → network returns → one send per recipient.
2. Business date spanning midnight appears consistently in attachment filename, title and summary.
3. Two successive close clicks result in one finalized business day and one automatic send job per recipient/channel.
4. Provider timeout after accepting submission does not cause automatic duplicate delivery without reconciliation.
5. Supervisor tries to send to unapproved email/WhatsApp number: denied; owner adds recipient: allowed and audited.
6. Email and WhatsApp recipients receive role-appropriate content; no PIN, secrets or excessive customer PII.
7. Retry a failed WhatsApp template submission gives actionable error and does not corrupt financial report.
8. Reports still show closed status when email fails or PC is turned off.
9. User changes email recipient after close: existing queued job continues to reference its verified intended recipient; new approved delivery is a new audited job.
10. Corrections to historical financial postings after close create auditable adjustment in allowed later day and/or explicitly revised report; never edit prior attachment silently.

## 8. Recommended implementation milestones

- **Phase A — MUST:** Generate PDF + XLSX, local outbox/delivery history, manager-approved email recipients, automatic + manual send and retry, no close blocking, tests.
- **Phase B — SHOULD / optional first release:** Manual WhatsApp share link and export/open file UX, safe messaging disclaimer.
- **Phase C — requires integration decision:** Official WhatsApp automatic delivery through secure backend provider, approved template and consent management, webhook event receipts and cost/rate-limit controls.
