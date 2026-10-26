# Production release hardening

User authorization: settle existing PRs #37 and #43, deliver the Windows app,
and remove physical printing because the business does not require it.

## Acceptance

- Cashiers can progress an eligible order through Preparing, Ready and Delivered
  from Orders. Delivery dispatch and completion retain their rider trip rules.
  The service checks active, login-enabled Cashier identity, valid transitions,
  and records actor and event time. Historical events are not invented.
- Revision and cancellation enforce the same service-level Cashier authorization.
- No receipt printer, printer settings, print queue, cash drawer device or native
  report printing is required or exposed. Digital receipts, PDF/CSV/XLSX exports
  and report email remain available. Checkout must not pretend to print.
- Windows distribution includes the executable, Flutter assets, native plugin
  libraries and Visual C++ runtime dependencies. It includes operating and backup
  instructions, source/build identity and SHA-256 checksums.
- GitHub Actions verifies the actual extracted package starts with an isolated
  fresh database, opens a responsive window and contains no default staff logins.
  All framework tests, analysis and builds run remotely.
- Both pending PRs and the release fixes are reviewed and integrated into main;
  the final main commit passes CI and Windows packaging before publication.

## Confirmed test boundaries

The user confirmed cashier progression/revision service authorization, Orders
screen controls, printer failure handling and packaged Windows startup. The later
business decision removes physical printing; its boundary now verifies removal
from the application workflow. Existing analytics boundaries remain confirmed.

## Limits

Startup smoke is a packaging check, not a substitute for testing the restaurant's
real opening balances, staff accounts and daily operations. Historical analytics
continue to disclose unavailable inputs described in `docs/manager-analytics.md`.
