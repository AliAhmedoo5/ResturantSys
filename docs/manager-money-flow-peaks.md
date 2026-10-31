# Money-flow peaks

Open Manager reports → Expenses to explore the finance timeline and actual-time
money-flow charts. Each funding stream has inflow, outflow, greatest net and least
net views for the selected periods and Karachi clock hours. All tied peaks remain
visible, ordered chronologically. Source details and CSV/XLSX/PDF use the same
immutable bucket and contributor rows as the charts.

Business Day selection uses receiving assignments, including collections whose
originating Orders are outside the selected cohort. Calendar selection uses actual
event time with an inclusive start and exclusive end. Periods use distinct Business
Days at daily granularity, Monday-start weeks and Karachi calendar months. Hourly
buckets use actual clock hours. Open activity is explicitly incomplete at cutoff;
rankings describe observed evidence, rather than a comparison of completed periods.

Inflow and outflow are nonnegative magnitudes in Integer Paisa. Net equals inflow
minus outflow. DRAWER, BANK, OWNER and RIDER_HELD are separate streams. A confirmed
customer-to-rider collection is a business receipt; the later rider-to-drawer
handover is an internal custody transfer. Drawer flow includes its custody effect,
while consolidated inflow/outflow excludes it. COD settlement attribution, salary
accrual, unpaid supplier purchases and Opening Float are not money-flow inputs.
Stable payment-event links prevent counting their tenders or Cash Movements again.

Unknown actual times never use recording time as a replacement. Coverage rows
disclose unallocatable unknown-time events, selected posting-context legacy finance
and manual movement records, and selected Order-cohort legacy tenders. Unknown-time
calendar evidence cannot be assigned to the selected date range. Missing evidence
does not create zero-activity periods. Sales retains its separately labeled legacy
Order-cohort view. Physical Shift reconciliation retains its whole-Shift scope.
