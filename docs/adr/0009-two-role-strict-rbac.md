# Strict Two-Role Interactive Authorization Model

## Context
Earlier drafts included four roles (`cashier`, `kitchen`, `supervisor`, `owner`) and allowed supervisors to operate front-counter POS terminals. The v8 authoritative policy (Chapters 00, 01, 24, 30) mandates that there are exactly two interactive POS login roles: `CASHIER` and `MANAGER` (with Supervisor and Owner treated as identical aliases of Manager). Crucially, the Manager must never perform cashier operational tasks (billing, customer carts, discounts at checkout, or cashier shift drawer operations). Kitchen helpers have no interactive POS login.

## Decision
We consolidate system authentication into two interactive roles: `CASHIER` and `MANAGER`. Kitchen accounts with POS login rights are eliminated. At the service boundary, Manager credentials are hard-blocked from initiating checkout, creating customer orders, collecting customer tenders, or operating cashier drawer shifts. Managers perform catalog, recipe, stock, supplier, staff PIN, settings, and business-day closure administration.

## Consequences
- Eliminates role ambiguity and privilege leakage.
- Prevents managers from manipulating live drawer counts or billing under managerial credentials.
- Kitchen staff operate via verbal communication or physical token status boards without POS terminals.
