# Compulsory First-Run Onboarding Wizard

## Context
When deploying on a fresh Windows desktop terminal or after restoring a clean database, failing to guide initial setup risks leaving the system with no active cashier account, default insecure credentials, or no open business day, causing counter checkout errors during live operation.

## Decision
The system enforces a 5-step First-Run Wizard:
1. Configure restaurant name, storage directory, PKR currency, and tax-inclusive 0% default.
2. Create first Manager account with a secure 4–8 digit PIN.
3. **MANDATORY**: Create primary Cashier profile with a unique 4-digit PIN (different from Manager). The wizard cannot complete without an enabled Cashier.
4. Guided recipe creation or sample catalog setup (recipes are mandatory before items can be activated).
5. Manager opens the first Business Day, and the UI presents a guided switch to Cashier login for shift opening.

## Consequences
- Prevents headless or un-runnable counter states.
- Enforces strict two-role separation from moment zero.
- Guarantees immediate billing readiness upon application installation.
