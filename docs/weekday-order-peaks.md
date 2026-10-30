# Weekday and recurring Order peaks

Manager Portal → Reports → Order operations compares confirmed Order workload.
Business Day mode groups weekdays by the assigned operational opening date;
calendar mode uses the actual creation date in Asia/Karachi (UTC+05:00). A
post-midnight Order keeps its operational weekday in Business Day mode and uses
the following calendar weekday in calendar mode. Neither mode creates unopened
Business Days. Holds and revisions add no confirmed Orders; later cancellations
and refunds do not remove workload.

The primary operational weekday ranking divides confirmed Orders on selected
completed Business Days by the count of those distinct completed Business Days.
Opened zero-order days count in the denominator; separate Business Day IDs on
the same date count separately. The numerator, denominator, aggregate Orders,
open-day counts and open-day Orders are exposed together. No completed days
means an unavailable average. Open activity never contributes to this ranking.
Calendar weekday totals are labeled separately and do not imply this operational
average. Order-only filters affect the numerator, while the denominator retains
all selected opened Business Days; this policy is disclosed in the snapshot.

The weekday/hour table uses actual Karachi clock hours, with the weekday basis
shown beside it. A known observed zero is 0; unobserved intervals or unavailable
creation-time evidence show unavailable. Open-period activity is partial at the
snapshot cutoff. Weekly trends start on Monday and monthly trends start on the
first of the local calendar month. Trends retain exact inclusive start and
exclusive end bucket boundaries plus the selected range, observed Business Day
IDs, source Order IDs and closure coverage. First/last clipped periods and open
periods are labeled incomplete. Do not add weekday, hourly and trend projections
together: they summarize the same Orders.

The UI and CSV, XLSX and PDF exports consume the same immutable snapshot rows.
Exports retain the time basis, numerator, denominator, open activity, boundaries,
source links and coverage disclosure, alongside schema and report provenance.
Original sealed X/Z reports and their recording times remain unchanged.
