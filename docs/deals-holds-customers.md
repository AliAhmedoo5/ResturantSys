# Deals, holds and customers

- **Manager → Catalog → Deals:** create or open a deal, set its base price, add one component per serving, select allowed Menu Items, choose one default per component, and enter any upgrade prices. Drafts can be saved before publication. Active deals require complete recipes for every selectable Menu Item. The picture action remains available.
- **Cashier → Hold:** save the current cart with a label. Multiple holds persist across restarts and shifts for that Cashier. Holding does not allocate a Token, collect payment or consume stock.
- **Cashier → Recall:** first hold or clear the current cart, then select a saved hold. Prices, recipes, modifiers and deal components are checked against the current catalog. Invalid holds remain available for correction through a replacement cart or explicit discard. Recalled holds remain saved until checkout succeeds. Saving the recalled cart replaces its previous hold atomically.
- **Cashier → Customers:** search by name or normalized phone, add/edit a record, inspect history, select a customer, or repeat a previous order into an empty cart. Repeat uses current prices and requires new payment and discount selection. Delivery details are reviewed again; saved addresses can be selected explicitly.
- **Manager → Manager Portal → Customers:** inspect and edit the directory. Select a duplicate, choose **Merge duplicate**, select the record to keep and enter a reason. The merge retains phone aliases and both histories, records the Manager and timestamp, and preserves committed order snapshots. Managers cannot repeat orders or operate carts.

Schema version 18 adds persistent holds, customer identities, an immutable merge audit and customer links. Legacy customer orders are linked separately, including orders on closed Business Days; their snapshots are preserved.

Regression tests: `test/orders/backlog_workflows_test.dart` and `test/widgets/backlog_workflows_widget_test.dart`. Run these and the complete test suite through the repository's GitHub Actions CI workflow; do not run Flutter locally.
