# Cashier delivery dispatch

The Cashier can complete delivery operations without switching to the Manager account.

1. Confirm the delivery order in Register. Cash on Delivery remains Collection Due.
2. Open Riders in the sidebar, select the waiting orders and rider, then dispatch the trip.
3. Return to Register to continue billing. An unfinished cart is preserved while opening Riders.
4. Mark orders delivered as the rider completes them. Delivery alone does not settle COD.
5. When the rider returns, the Cashier operating the open shift counts the cash and settles the trip.

Riders shows waiting orders and active trips for the active Business Day, including orders from earlier shifts in that day. Refresh deliveries to reload the queue. A load failure displays a Retry action instead of silently appearing as an empty queue.

The Manager can still monitor and assign trips from Riders. Cash collection requires the Cashier's own open shift. Orders retain their original sales shift; rider cash is received in the collecting Cashier's shift. Dispatch and settlement cannot cross Business Days.

Preparing orders, including prepaid deliveries, are eligible for assignment. To record food readiness, open **Register → Orders → Mark Ready**. The **Revise / Cancel** dialog displays the stage but does not change it. Dispatch records Out for Delivery; the trip controls record delivery.

The rider selector uses active staff IDs and names independently of POS login roles. Non-login staff and legacy kitchen records can remain in the staff directory without preventing deliveries from loading or receiving POS login permissions.
