# COD Lifecycle Decoupled from Physical Delivery

## Context
In restaurant delivery with Cash on Delivery (COD), treating physical delivery as proof of payment creates phantom cash drawer balances. A rider may drop off the food, but the cash remains physically in the rider's pocket or cash pouch until returned to the counter.

## Decision
1. Delivery fulfillment and payment reconciliation are strictly decoupled. When an order is delivered, its delivery status is `Delivered`, but its payment status remains `Collection Due`.
2. Only when the rider returns to the store and the Cashier performs formal Rider Trip Settlement (counting physical currency handed over) does the order become `Paid` / `Settled`, and the cash enters the active cashier shift drawer.
3. If the customer paid via direct electronic wallet transfer to the store, the Cashier confirms the digital reference during settlement without generating a drawer cash movement.

## Consequences
- Drawer cash balances reflect only currency physically counted and held inside the till.
- Clear financial accountability between individual delivery riders and the front cashier.
