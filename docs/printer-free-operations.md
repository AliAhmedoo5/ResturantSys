# Digital operations

The business does not use physical printers. The production app does not configure printers, submit print jobs, pulse cash drawers, show a Reprint Tray, or require printer drivers. This user decision on 2026-10-26 supersedes earlier customer receipt, thermal X/Z report, and printer setup requirements.

Checkout remains a committed SQLite transaction with an on-screen order and token confirmation. Cashier fulfillment milestones, order revisions, manual tenders, and cash reconciliation remain business records. Cash drawer accounting describes recorded cash, not a hardware connection.

Managers can review X/Z report text and copy it, export the end-of-day workbook, and use existing sealed PDF/workbook exports and report email delivery. Analytics CSV, XLSX, and PDF exports remain available. Existing databases are preserved; obsolete printer settings in an upgraded database are ignored.
