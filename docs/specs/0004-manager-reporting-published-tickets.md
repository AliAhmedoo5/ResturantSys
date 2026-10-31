# Published reporting tickets

Published and verified on 29 October 2026: 38 native child issues of [specification #60](https://github.com/AliAhmedoo5/ResturantSys/issues/60), covering all 44 original proposal slices. Five groups combine related unblocked work. There are 32 agent implementation tickets, six human policy decisions and 24 native blocking edges. The parent specification body and open state are unchanged.

| Issue | Title | Label | Blocked by | Original slices |
| --- | --- | --- | --- | --- |
| [#61](https://github.com/AliAhmedoo5/ResturantSys/issues/61) | Show auditable reporting identities, historical names, times and provenance | ready-for-agent | None | 1, 10 |
| [#62](https://github.com/AliAhmedoo5/ResturantSys/issues/62) | Record independent checkout receipts and refund events | ready-for-agent | None | 2 |
| [#63](https://github.com/AliAhmedoo5/ResturantSys/issues/63) | Trace COD settlement to the actual receiving Shift | ready-for-agent | [#62](https://github.com/AliAhmedoo5/ResturantSys/issues/62) | 3 |
| [#64](https://github.com/AliAhmedoo5/ResturantSys/issues/64) | Report finance payments by actual time and Payment Source | ready-for-agent | None | 4 |
| [#65](https://github.com/AliAhmedoo5/ResturantSys/issues/65) | Reconcile one selected Cashier Shift end to end | ready-for-agent | [#62](https://github.com/AliAhmedoo5/ResturantSys/issues/62), [#63](https://github.com/AliAhmedoo5/ResturantSys/issues/63), [#64](https://github.com/AliAhmedoo5/ResturantSys/issues/64) | 5 |
| [#66](https://github.com/AliAhmedoo5/ResturantSys/issues/66) | Select Business Day or calendar-time order activity | ready-for-agent | None | 6 |
| [#67](https://github.com/AliAhmedoo5/ResturantSys/issues/67) | Rank busiest Order days and hours separately from sales value | ready-for-agent | [#66](https://github.com/AliAhmedoo5/ResturantSys/issues/66) | 7 |
| [#68](https://github.com/AliAhmedoo5/ResturantSys/issues/68) | Compare weekdays fairly and explore recurring Order peaks | ready-for-agent | [#67](https://github.com/AliAhmedoo5/ResturantSys/issues/67) | 8 |
| [#69](https://github.com/AliAhmedoo5/ResturantSys/issues/69) | Explore actual-time inflow, outflow and net-flow peaks | ready-for-agent | [#65](https://github.com/AliAhmedoo5/ResturantSys/issues/65), [#66](https://github.com/AliAhmedoo5/ResturantSys/issues/66) | 9 |
| [#70](https://github.com/AliAhmedoo5/ResturantSys/issues/70) | Decide closed-day correction authority and reconciliation policy | ready-for-human | None | 11 |
| [#71](https://github.com/AliAhmedoo5/ResturantSys/issues/71) | Append approved historical corrections and show adjusted reports | ready-for-agent | [#65](https://github.com/AliAhmedoo5/ResturantSys/issues/65), [#70](https://github.com/AliAhmedoo5/ResturantSys/issues/70) | 12 |
| [#72](https://github.com/AliAhmedoo5/ResturantSys/issues/72) | Decide earned-period payroll and labor allocation rules | ready-for-human | None | 13 |
| [#73](https://github.com/AliAhmedoo5/ResturantSys/issues/73) | Show monthly earned payroll alongside posting and payment views | ready-for-agent | [#64](https://github.com/AliAhmedoo5/ResturantSys/issues/64), [#72](https://github.com/AliAhmedoo5/ResturantSys/issues/72) | 14 |
| [#74](https://github.com/AliAhmedoo5/ResturantSys/issues/74) | Decide preparation and delivery measurement definitions | ready-for-human | None | 15 |
| [#75](https://github.com/AliAhmedoo5/ResturantSys/issues/75) | Report observed preparation and ready times | ready-for-agent | [#74](https://github.com/AliAhmedoo5/ResturantSys/issues/74) | 16 |
| [#76](https://github.com/AliAhmedoo5/ResturantSys/issues/76) | Show current Hold age and Cashier ownership | ready-for-agent | None | 17 |
| [#77](https://github.com/AliAhmedoo5/ResturantSys/issues/77) | Retain and report Hold lifecycle history | ready-for-agent | [#76](https://github.com/AliAhmedoo5/ResturantSys/issues/76) | 18 |
| [#78](https://github.com/AliAhmedoo5/ResturantSys/issues/78) | Report recorded delivery reasons and reattempts | ready-for-agent | None | 19 |
| [#79](https://github.com/AliAhmedoo5/ResturantSys/issues/79) | Report delivery timing, final outcomes and unsettled aging | ready-for-agent | [#74](https://github.com/AliAhmedoo5/ResturantSys/issues/74), [#78](https://github.com/AliAhmedoo5/ResturantSys/issues/78) | 20 |
| [#80](https://github.com/AliAhmedoo5/ResturantSys/issues/80) | Separate verified rider-held cash from customer debt | ready-for-agent | [#63](https://github.com/AliAhmedoo5/ResturantSys/issues/63) | 21 |
| [#81](https://github.com/AliAhmedoo5/ResturantSys/issues/81) | Classify first-time and returning customers across available history | ready-for-agent | None | 22 |
| [#82](https://github.com/AliAhmedoo5/ResturantSys/issues/82) | Expose stored configuration and operations audit safely | ready-for-agent | None | 23 |
| [#83](https://github.com/AliAhmedoo5/ResturantSys/issues/83) | Decide security-event access and retention policy | ready-for-human | None | 24 |
| [#84](https://github.com/AliAhmedoo5/ResturantSys/issues/84) | Capture and report missing authentication and PIN events | ready-for-agent | [#82](https://github.com/AliAhmedoo5/ResturantSys/issues/82), [#83](https://github.com/AliAhmedoo5/ResturantSys/issues/83) | 25 |
| [#85](https://github.com/AliAhmedoo5/ResturantSys/issues/85) | Persist verified backup attempts and health history | ready-for-agent | None | 26 |
| [#86](https://github.com/AliAhmedoo5/ResturantSys/issues/86) | Reconcile supplier payables and aging at a historical cutoff | ready-for-agent | None | 27 |
| [#87](https://github.com/AliAhmedoo5/ResturantSys/issues/87) | Decide line-level sales and cost allocation policy | ready-for-human | None | 28 |
| [#88](https://github.com/AliAhmedoo5/ResturantSys/issues/88) | Report allocated Menu Item and Deal net sales and margins | ready-for-agent | [#87](https://github.com/AliAhmedoo5/ResturantSys/issues/87) | 29 |
| [#89](https://github.com/AliAhmedoo5/ResturantSys/issues/89) | Reconcile ingredient opening-to-ending quantities | ready-for-agent | None | 30 |
| [#90](https://github.com/AliAhmedoo5/ResturantSys/issues/90) | Decide historical inventory valuation policy | ready-for-human | None | 31 |
| [#91](https://github.com/AliAhmedoo5/ResturantSys/issues/91) | Value reconciled historical inventory under the approved policy | ready-for-agent | [#89](https://github.com/AliAhmedoo5/ResturantSys/issues/89), [#90](https://github.com/AliAhmedoo5/ResturantSys/issues/90) | 32 |
| [#92](https://github.com/AliAhmedoo5/ResturantSys/issues/92) | Report supplier acquisition prices, frequency and receipt punctuality | ready-for-agent | None | 33, 34 |
| [#93](https://github.com/AliAhmedoo5/ResturantSys/issues/93) | Separate food and packaging COGS using event-time classification | ready-for-agent | None | 35 |
| [#94](https://github.com/AliAhmedoo5/ResturantSys/issues/94) | Capture worked hours and report labor productivity | ready-for-agent | [#72](https://github.com/AliAhmedoo5/ResturantSys/issues/72) | 36 |
| [#95](https://github.com/AliAhmedoo5/ResturantSys/issues/95) | Apply domain filters consistently across Manager reports and exports | ready-for-agent | None | 37, 38, 39 |
| [#96](https://github.com/AliAhmedoo5/ResturantSys/issues/96) | Save Manager report workflows and inspect their KPI contributors | ready-for-agent | None | 40, 42 |
| [#97](https://github.com/AliAhmedoo5/ResturantSys/issues/97) | Choose preceding-period or comparable-weekday report comparisons | ready-for-agent | [#66](https://github.com/AliAhmedoo5/ResturantSys/issues/66) | 41 |
| [#98](https://github.com/AliAhmedoo5/ResturantSys/issues/98) | Print reports and control large exports with progress and cancellation | ready-for-agent | None | 43, 44 |

The first reporting phase is #61–#69. Work the frontier of tickets whose blockers are resolved; later independent tickets have no artificial phase blocker. All implementation retains the parent invariants and GitHub Actions-only framework validation.