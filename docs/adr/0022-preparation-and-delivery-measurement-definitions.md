# ADR-0022: Preparation and Delivery Measurement Definitions (Milestones, Late SLA, Reattempts, and Unsettled COD Aging)

- **Status**: Approved
- **Approver**: Operations & Logistics Policy Lead
- **Governs**: Ticket #74 (closing #74), Specification #60
- **Implements**: Core measurement contracts prior to Ticket #75 and Ticket #79 implementation

---

## Context

In fast-food counter and delivery operations, accurate measurement of food preparation, courier dispatch, fulfillment duration, and cash collection is essential for operational visibility and customer satisfaction. However, fast-food environments present unique constraints:
1. **Manual Milestone Recording Without KDS/KOT**: The kitchen is immediately adjacent to the counter. There is no dedicated Kitchen Display System (KDS) or physical Kitchen Order Ticket (KOT) hardware queue. Status transitions (`CONFIRMED` -> `PREPARING` -> `READY`) are recorded manually by Cashiers on the POS terminal. During peak rushes, Cashiers may occasionally miss milestone taps or mark them out-of-order.
2. **Repeated Kitchen Status Moves (Rework Cycles)**: An order marked `READY` may be returned to `PREPARING` if a customer modifies an item, an order is held under a heat lamp, or an item is remade due to a burn or spill. Naive systems either overwrite the initial completion time (artificially inflating prep time) or drop subsequent rework evidence entirely.
3. **Outlier Skew in Arithmetic Averages**: Simple arithmetic mean preparation and delivery times are heavily distorted by extreme outliers (e.g., an order held for a scheduled pickup, a customer unreachable for an hour, or an forgotten counter tap).
4. **Delivery Area Target SLAs vs. Global Defaults**: Travel times vary drastically across neighborhoods. A flat 30-minute target is unachievable for distant delivery areas, while masking delays in adjacent delivery areas.
5. **Multi-Order (Batch) Trips**: Riders frequently depart with multiple delivery orders on a single trip. Naive metrics attributing trip duration uniformly across orders misstate individual transit times.
6. **Conflating Delivery Attempts with Order Failures**: A rider returning with undelivered food because a customer didn't answer their phone does not constitute an order failure. The customer often calls back within 20 minutes for a successful redelivery. Treating every returned run as a canceled/failed order artificially spikes delivery failure rates.
7. **COD Cash Aging Clock Origin**: When Cash on Delivery (COD) orders are dispatched, cash is in transit. When a rider returns, physical currency must be handed over to the Cashier. Naive systems start aging COD balances from order creation rather than rider return, masking the true duration that cash sits unverified at the counter.

Under [Specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60) and [Ticket #74](https://github.com/AliAhmedoo5/ResturantSys/issues/74), this ADR establishes the formal human policy and measurement contracts for preparation milestones, delivery travel, late SLAs, reattempts, failure rates, and unsettled COD aging prior to implementing analytics and UI in [Ticket #75](https://github.com/AliAhmedoo5/ResturantSys/issues/75) and [Ticket #79](https://github.com/AliAhmedoo5/ResturantSys/issues/79).

---

## Decision

### 1. Preparation & Ready Time Milestone Contract

#### Duration Formula
Preparation duration measures the elapsed time from order confirmation until the kitchen marks the food ready for pickup or dispatch:
$$\text{Prep Duration} = T_{\text{ready}} - T_{\text{confirmed}}$$
- $T_{\text{confirmed}}$: Immutable timestamp recorded when the Cashier confirms the order and allocates a daily Token.
- $T_{\text{ready}}$: Timestamp recorded when the order milestone is first transitioned to `READY`.

#### Manual Counter Adjacency & Repeated Transitions
- Because the kitchen is adjacent to the front counter and lacks automated KDS tracking, kitchen status milestones are recorded by the Cashier.
- **Initial Milestone Immutability**: The very first transition to `READY` records the primary kitchen completion milestone ($T_{\text{ready}}$).
- **Rework Cycles**: If an order transitions back (e.g., `READY` $\rightarrow$ `PREPARING` $\rightarrow$ `READY`), each subsequent move is recorded in an append-only milestone log as a **Rework Cycle** with its timestamp and reason (remake, customer request, warming). Subsequent moves **never** overwrite the primary $T_{\text{ready}}$ milestone.

#### Percentile Metrics (p50 and p90)
- Analytics reports must display **Median (p50)** and **90th Percentile (p90)** preparation times.
- Simple arithmetic means are prohibited as primary metrics because rush-hour anomalies or forgotten order taps severely skew averages.

#### Milestone Sample Coverage & Missing Evidence
- If an order bypasses the `READY` tap (e.g., transitioning directly from `CONFIRMED` or `PREPARING` to `DISPATCHED` or `COMPLETED`), $T_{\text{ready}}$ is unknown.
- Missing timestamps are flagged with `Quality.missingEvidence`.
- Orders lacking $T_{\text{ready}}$ are strictly **excluded** from preparation duration percentiles.
- The system must **never** synthesize or fabricate zero minutes for missing events.
- Reports must disclose explicit sample coverage alongside percentiles:
  $$\text{Prep Time: 14m (p50, N=42/50, 84\% coverage)}$$

#### Out-of-Order Kitchen Milestone Sequence
- If a kitchen completion milestone timestamp occurs prior to order confirmation ($T_{\text{ready}} < T_{\text{confirmed}}$), the event is flagged as `Quality.invalidSequence` (or `Quality.outOfOrderMilestone`).
- Orders with invalid timestamp sequences are strictly **excluded** from preparation duration percentiles (p50 and p90) and duration calculations.
- The system must **never** calculate or display negative preparation durations.
- Invalid sequence events are logged to the data quality audit report for supervisor review.

---

### 2. Delivery Travel Time & Late SLA Thresholds

#### Rider Travel Time Formula
Rider travel time measures the transit duration of a courier trip:
$$\text{Rider Travel Time} = T_{\text{delivered}} - T_{\text{dispatched}}$$
- $T_{\text{dispatched}}$: Trip departure timestamp when the rider leaves the restaurant.
- $T_{\text{delivered}}$: Delivery completion timestamp, recorded either at the door (if mobile dropoff is logged) or upon rider return to the counter.

#### Delivery SLA Contract
- **Delivery Area Target ETA**: Evaluated against the Manager-configured `target_eta_minutes` on the selected `Delivery Area` (also referred to as `Area Target ETA`).
- **Fallback SLA**: If no specific target ETA is configured for the delivery area, the system enforces a default fallback SLA of **45 minutes** from $T_{\text{confirmed}}$.
- **Completed Order Late SLA Evaluation**:
  $$\text{Total Elapsed Delivery Time} = T_{\text{delivered}} - T_{\text{confirmed}}$$
  A completed order is classified as **Late** if:
  $$(T_{\text{delivered}} - T_{\text{confirmed}}) > \text{Delivery Area Target ETA}$$
- **In-Flight Late SLA Evaluation (Active Orders)**:
  For active orders currently preparing or in transit ($T_{\text{delivered}}$ is not yet reached), the elapsed duration is measured against the current time $T_{\text{now}}$:
  $$\text{Current Elapsed Duration} = T_{\text{now}} - T_{\text{confirmed}}$$
  If $(T_{\text{now}} - T_{\text{confirmed}}) > \text{Delivery Area Target ETA}$, the active order is flagged and badged as **`In-Flight Late`** on live manager dispatch screens and active order boards, alerting dispatchers before final delivery completes.

#### Out-of-Order Delivery Timestamps
- If a delivery completion timestamp occurs prior to trip dispatch ($T_{\text{delivered}} < T_{\text{dispatched}}$) or prior to order confirmation ($T_{\text{delivered}} < T_{\text{confirmed}}$), the event is flagged as `Quality.invalidSequence` (or `Quality.outOfOrderMilestone`).
- Invalid delivery sequences are strictly **excluded** from rider travel time calculations, travel duration percentiles, and delivery SLA statistics.
- The system must never calculate negative transit durations.
- Invalid delivery sequences are logged in the data quality audit report.

#### Batch Trips
- When a rider departs on a multi-order trip, orders are grouped under a shared trip ID.
- Where individual dropoff timestamps are recorded, each order calculates its specific travel time.
- Where individual dropoff times are unrecorded, the trip transit time is disclosed as a batch trip measurement.

---

### 3. Final Delivery Failure vs. Reattempts

#### Returned Attempt $\ne$ Final Failure
- A returned trip attempt alone is **NOT** an order failure. In local operations, a customer may temporarily have their mobile phone off, be in prayer, or the rider may need address clarification.
- The order may be brought back to the counter and staged for a reattempt (`REDELIVERY_PENDING`).

#### Reattempt Accounting
- Each trip dispatch and return cycle is recorded distinctly as a delivery attempt.
- Reattempts increment the order's `attempt_count` without marking the commercial order as failed.

#### Final Delivery Failure Criteria
An order is classified as a **Final Delivery Failure** if and only if it reaches an explicit terminal failure disposition:
1. `CANCELLED_UNDELIVERED`: The customer canceled or rejected the order before successful delivery.
2. `RETURNED_WASTED`: Cooked food returned to the restaurant cannot be safely re-served and is written off to `kitchen_wastage` (Stock Disposition: WASTED). Cooked food is **never** auto-restocked.
3. `RETURNED_RESTOCKED`: Limited strictly to unopened, shelf-stable sealed beverages or manufacturer packaged goods.

#### Delivery Failure Rate Formula
Delivery failure rate is calculated across unique dispatched delivery orders:
$$\text{Delivery Failure Rate} = \frac{\text{Unique Dispatched Orders with Final Failed Outcome}}{\text{Total Unique Dispatched Delivery Orders in Period}}$$

---

### 4. Unsettled COD Aging Clocks

#### Aging Clock Origin
- For Cash on Delivery (COD) orders, physical cash is carried by the rider during transit.
- Under ADR-0016, COD payment status remains `Collection Due` until physical handover at the counter.
- The **Unsettled COD Aging Clock** begins the moment the rider returns from the delivery trip ($T_{\text{trip\_return}}$), **NOT** at order creation or dispatch. Cash cannot be settled before the courier is physically present at the till.

#### Aging Bands
Unsettled COD exposure is bucketed into four distinct operational aging bands:
1. **Current Shift**: Rider has returned ($T_{\text{trip\_return}}$ elapsed); cashier shift is currently active and awaiting routine handover settlement.
2. **Overdue / Unsettled (0–24 hours)**: The shift in which the rider returned has closed, but the COD collection remains unsettled in `Collection Due`.
3. **Aged (1–3 days)**: Unsettled COD cash carried across business day closures, representing overdue courier audit risk.
4. **Critical (>3 days)**: Severe unresolved shortage requiring formal Manager escalation and investigation.

---

## Worked Acceptance Examples

### Example 1: Normal Kitchen & Delivery Flow
- **Scenario**: Single delivery order in Gulshan Delivery Area.
- **Timeline**:
  - `19:00`: Cashier confirms Order #1049 ($T_{\text{confirmed}}$).
  - `19:15`: Kitchen finishes cooking; Cashier marks order `READY` ($T_{\text{ready}}$).
  - `19:20`: Rider departs on Trip #12 ($T_{\text{dispatched}}$).
  - `19:42`: Rider delivers order at customer door ($T_{\text{delivered}}$).
- **Calculations**:
  - $\text{Prep Duration} = 19:15 - 19:00 = 15\text{ minutes}$.
  - $\text{Rider Travel Time} = 19:42 - 19:20 = 22\text{ minutes}$.
  - $\text{Total Elapsed Time} = 19:42 - 19:00 = 42\text{ minutes}$.
  - Gulshan Delivery Area Target ETA is 45 minutes.
  - $\text{Total Elapsed (42m)} \le \text{Delivery Area Target ETA (45m)}$ $\rightarrow$ **On-Time (Met SLA)**.

### Example 2: Reattempted Delivery vs Final Failure
- **Scenario**: Customer phone unreachable on first dispatch, delivered on second dispatch.
- **Timeline**:
  - `20:00`: Order #1050 dispatched on Trip #13.
  - `20:30`: Rider returns to restaurant; customer phone was powered off.
  - Cashier marks attempt `FAILED_ATTEMPT` / `REDELIVERY_PENDING`.
  - Reattempt count = 1. Delivery failure count = 0.
  - `21:00`: Customer calls store; order redispatched on Trip #14.
  - `21:20`: Rider successfully hands over order.
- **Resolution**:
  - Final order status = `DELIVERED`.
  - Total trip attempts = 2.
  - Final delivery failure = 0 (Order successfully fulfilled; not counted as failure).

### Example 3: Final Delivery Failure & Wastage Disposition
- **Scenario**: Customer cancels at the door due to cold food/delay.
- **Timeline**:
  - `20:15`: Order #1051 dispatched on Trip #15.
  - `21:00`: Rider returns with order; customer refused delivery at doorstep.
  - Cashier marks order `CANCELLED_UNDELIVERED`.
  - Cashier logs cooked burger and fries into `kitchen_wastage` (Stock Disposition: `WASTED`).
- **Resolution**:
  - Final order status = `Final Delivery Failure`.
  - Cooked food is discarded to wastage ledger, never returned to inventory.
  - Counted once in Delivery Failure Rate numerator and denominator.

### Example 4: Missing Milestone Handling
- **Scenario**: Heavy counter rush causes Cashier to skip the `READY` tap.
- **Timeline**:
  - `18:30`: Cashier confirms Order #1052.
  - `18:50`: Cashier packs order and directly dispatches on Trip #10 without pressing `READY`.
- **Resolution**:
  - $T_{\text{ready}}$ is missing (`Quality.missingEvidence`).
  - Order #1052 is **excluded** from preparation time p50/p90 percentiles. Zero minutes is NOT assumed.
  - Summary report outputs: `Prep Time (p50): 12m (N=19/20, 95% coverage)`.

### Example 5: Out-of-Order Timestamp Sequence Handling
- **Scenario**: System clock mismatch or cashier terminal tap sequence error.
- **Timeline**:
  - `19:30`: Cashier confirms Order #1053 ($T_{\text{confirmed}}$).
  - Due to a terminal clock synchronization discrepancy or accidental pre-tap, $T_{\text{ready}}$ is logged with a timestamp of `19:25` ($T_{\text{ready}} < T_{\text{confirmed}}$).
- **Resolution**:
  - Flagged as `Quality.invalidSequence` (`Quality.outOfOrderMilestone`).
  - Negative duration ($19:25 - 19:30 = -5\text{ minutes}$) is strictly prohibited and rejected.
  - Order #1053 is **excluded** from preparation duration percentiles (p50 and p90).
  - Event is recorded in the data quality audit report: `Order #1053: invalid milestone sequence (T_ready < T_confirmed)`.
  - Delivery transit measurements apply the identical exclusion if $T_{\text{delivered}} < T_{\text{dispatched}}$ or $T_{\text{delivered}} < T_{\text{confirmed}}$.

---

## Consequences

### Positive
- **Honest Kitchen Metrics**: p50 and p90 percentiles protect kitchen performance indicators from rush-hour outliers and forgot-to-tap edge cases.
- **Accurate Operational Delivery Rates**: Decoupling temporary attempt returns from final failures gives an accurate picture of actual delivery logistics success without inflating failure alarms.
- **Clear Cash Accountability**: Grounding the COD aging clock at rider trip return ($T_{\text{trip\_return}}$) reflects real cash drawer responsibility and highlights delayed settlements.
- **Transparent Evidence Quality**: Explicitly reporting sample coverage ($N=x/y$, %) ensures managers know when data gaps exist rather than relying on fabricated zeroes.
- **Food Safety Enforcement**: Mandating that returned cooked food is written off to `kitchen_wastage` prevents unsafe inventory restocking.

### Trade-offs & Limitations
- **Manual Tap Dependency**: Because fast-food counters lack automated KDS sensors, milestone capture relies on cashier taps. High counter rush periods may reduce milestone sample coverage.
- **Transit Timestamp Granularity**: When couriers do not have active mobile apps to mark dropoffs at the door, $T_{\text{delivered}}$ is captured upon courier return to counter, which approximates trip completion time.
- **Legacy Order Handling**: Historical orders created prior to milestone capture retain unknown milestone evidence and cannot be backfilled.
