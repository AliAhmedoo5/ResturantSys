# Order activity time basis

The Manager reporting workspace defaults to assigned Business Days. A day grouping retains each Business Day ID, even when two Business Days share an opening date. Week grouping begins on Monday; month grouping uses local calendar months. The operational weekday follows the assigned Business Day opening date.

Calendar time selects Orders by their actual creation timestamp in Asia/Karachi, independently of their assigned Business Day. An Order at 01:00 on 30 October can belong to the Business Day opened on 29 October. Switching the view changes its selected bucket, never its assignment. Both the creation timestamp and assigned Business Day appear in Order source details.

All ranges include the start and exclude the end. Query date/time components represent Karachi wall time. UTC and explicit-offset evidence is converted to Karachi; naive historical timestamps retain the disclosed legacy Karachi assumption. Missing timestamps cannot enter calendar buckets.

The immutable snapshot and CSV, XLSX and PDF metadata retain the selected basis, grouping, range boundaries and bucket definitions. Eligible sales value and eligible Order count retain their existing cancellation rules; committed workload remains a separate Order operations metric. Non-order ledgers and whole-drawer reconciliation continue to use their labeled Business Day scope. A calendar Order selection does not move a tender into another drawer or infer a collection date.

Source details retain stable Business Day IDs. Calendar snapshots additionally identify the assigned Business Days of selected Orders, including days opened outside the chosen calendar interval. The overview's Business Day rows describe the operational context rather than a calendar cash reconciliation.

Workload daily/hourly rows retain period completion status, contributing and open
Business Day IDs, original closure evidence and the snapshot cutoff. Completed
buckets alone receive peak ranks; incomplete activity is shown separately with
an **Incomplete** chart label and its observed count/value. An old opening date
does not close a still-open Business Day. An elapsed calendar date is distinct
from closure of its contributing Business Days. Current calendar windows remain
partial until their end has elapsed, even when their contributing days closed.
Empty hours not yet observed in selected operational intervals have unavailable
totals; separately labeled observed counts retain activity recorded so far.
The same per-bucket status, cutoff and ranking basis are exported.
