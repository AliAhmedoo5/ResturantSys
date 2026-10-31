# Manager / Supervisor portal manual test checklist

For the Windows application containing PR #36, merged as `75914a1`.
This covers the Supervisor tabs and the other workspaces available to a Manager.
These are manual acceptance checks, not a claim that every scenario has been
manually verified on your PC.

## Before starting

- [ ] Run `E:\Projects\ResturantSys\dist\latest-main-app\resturant_sys.exe`.
- [ ] Use a disposable test PC or VM for a full rehearsal. A second copy of the
  application folder still uses the shared Windows database at
  `%ProgramData%\ResturantPOS\data\pos.db`; it does not create a test database.
- [ ] If using an existing installation, first create and verify a backup through
  Supervisor -> Z-Reports & Backups. Test orders, stock changes, payments, staff
  changes and closing a Business Day become real records in that database.
  Do not close a live restaurant Business Day just to complete this checklist.
- [ ] Have your Manager PIN, a separate test Cashier, two valid pictures, a corrupt
  `.png`, a non-image file, and an image larger than 5 MiB ready.
- [ ] Prefix disposable records with `QA`: QA Burgers, QA Bun, QA Patty,
  QA Burger, QA Supplier, QA Area and QA Cashier. Record starting balances.
- [ ] Use an email address you control for email tests. Sending a test email or
  resending a report sends a real message.

For each test, record PASS / FAIL / BLOCKED, what actually happened, and a
screenshot or exact error if it failed. BLOCKED means a prerequisite is missing,
such as no Deal configured or no printer connected.

## 1. Login, access and navigation

- [ ] Log in with a valid Manager PIN: Manager workspaces are available.
- [ ] Enter a wrong PIN: access is denied without changing data.
- [ ] Lock the app and unlock again: the correct staff identity is displayed.
- [ ] Log in as QA Cashier: Catalog, Khata and Supervisor are unavailable.
- [ ] Return as Manager: you can open a Business Day, but cannot operate a
  Cashier shift or perform billing using the Manager identity.
- [ ] Open every sidebar workspace and every Supervisor tab. Check at 1366x768
  and your usual Windows display scale: controls remain readable and reachable.

## 2. Supervisor -> Staff & Departments

- [ ] Add `QA Department`: it appears in the department list and staff form.
- [ ] Try an empty department name: it is rejected.
- [ ] Register QA Cashier in that department with a unique four-digit PIN.
- [ ] Try an empty name, letters in the PIN, a three-digit Cashier PIN and a PIN
  already used by another staff member: each is rejected.
- [ ] Edit the staff name/department and save: the list reflects the edits.
- [ ] Edit a profile leaving the PIN blank: the current PIN still works.
- [ ] Use Update PIN with mismatched confirmation: saving is blocked.
- [ ] Change QA Cashier's PIN: the old PIN fails and the new PIN works.
- [ ] Deactivate QA Cashier: login is denied. Reactivate: login works again.
- [ ] If testing Manager registration, use a spare account: numeric PINs of
  4-8 digits are accepted; other lengths are rejected. Keep your working Manager
  account active throughout testing.

## 3. Catalog -> Categories and Raw Ingredients

- [ ] Add QA Burgers with a color and display order. Edit it and verify the new
  values after reopening the form.
- [ ] Add QA Bun and QA Patty using count/pieces, each with stock 20. Set costs
  to Rs 10 and Rs 40 respectively and a low-stock threshold of 5.
- [ ] Edit an ingredient's cost and threshold: the new values persist.
- [ ] Exercise category filtering and the low-stock filter where available;
  displayed records match the filter. Test a no-results state.
- [ ] Submit blank required fields and invalid numeric values: they must not
  silently create invalid records.
- [ ] On throwaway records only, test Delete -> Cancel, then Delete -> Confirm.
  Cancellation keeps the record; confirmation removes the intended record.
  Category deletion can also remove dependent Menu Items: read its confirmation.

## 4. Catalog -> Menu Items & BOM

- [ ] Create inactive QA Burger in QA Burgers: price Rs 116, tax 16%, tax-inclusive.
  Preview should show Rs 100 net + Rs 16 tax = Rs 116 retail.
- [ ] Attempt activation before adding its BOM: activation is rejected.
- [ ] Add a recipe of 1 QA Bun + 1 QA Patty. Save and reopen: quantities persist.
- [ ] Edit a recipe quantity and remove/re-add a component. Verify each saved
  version rather than only the immediate preview.
- [ ] Try zero or invalid recipe quantities: an incomplete/non-positive recipe
  must not pass the activation gate.
- [ ] Activate QA Burger after its valid recipe is configured. Log in as Cashier:
  it is available for sale. Deactivate it: it is hidden from new sales.
- [ ] Test tax-exclusive pricing separately: Rs 100 base + 16% tax should produce
  Rs 116 retail. Restore the intended price before the sales rehearsal.

## 5. Single-picture input: Menu Items and Deals

- [ ] In Add Menu Item, click Add picture: native File Explorer opens and accepts
  one JPEG, PNG or WebP. A preview appears.
- [ ] Cancel the form: no Menu Item or picture is saved.
- [ ] Repeat selection and Save: exactly one picture remains after reopening.
- [ ] In Edit Menu Item, drag a different picture onto the picture area: preview
  changes. Cancel and reopen: the original saved picture remains.
- [ ] Repeat replacement and Save: the new picture remains after reopening.
- [ ] Drop two files, a non-image, a corrupt `.png`, and an image over 5 MiB:
  show a useful error and preserve the previous valid picture.
- [ ] Open the browser and cancel selection: the picture remains unchanged.
- [ ] Remove a picture and Cancel: it remains saved. Remove and Save: it is gone.
- [ ] Verify the Cashier grid uses the saved picture, or its normal placeholder
  after removal. Switch away and back/reopen the app to check persistence.
- [ ] Repeat replacement/removal under Catalog -> Deal Photos for an existing
  Deal. If there are no Deals, mark this BLOCKED; this release has no complete
  Deal definition Add/Edit form.

## 6. Catalog -> Modifiers and Pre-Approved Discounts

- [ ] Add a modifier linked to QA Burger, such as Extra Patty: price delta Rs 20,
  ingredient QA Patty, quantity delta 1. Edit and reopen it.
- [ ] Add/edit a modifier group; exercise single/multiple selection, required
  selection and minimum/maximum limits in the Cashier selection dialog.
- [ ] Buy QA Burger with Extra Patty: price increases by Rs 20 and its additional
  ingredient consumption is recorded. Confirm the tax setting used for the test.
- [ ] Disable the modifier: it is unavailable for new selections.
- [ ] Add a 10% discount and a flat Rs 10 discount. Apply each in a separate
  Cashier cart and compare the displayed deduction with its eligible subtotal.
- [ ] Edit and deactivate the discounts: changed values persist and inactive
  discounts are unavailable to Cashiers.
- [ ] Test Cancel and Delete on disposable modifiers/discounts.

## 7. Supervisor -> Delivery Areas

- [ ] Add QA Area with unique code QA, coverage text, fee 5000 paisa and minimum
  food order 10000 paisa. These mean Rs 50 fee and Rs 100 minimum.
- [ ] Edit the fee/minimum and reopen: saved values persist.
- [ ] Try missing name/code and negative/non-integer paisa: reject invalid data.
- [ ] As Cashier, select Delivery: an active area is required and its fixed fee
  is added. Verify the minimum-order rule with food totals below and above it.
- [ ] Archive/deactivate QA Area: it is unavailable for new deliveries while old
  orders retain their recorded delivery details.

## 8. Mandi, Wastage and stock alerts

- [ ] In Mandi, select a count-based test ingredient. Buy 1 Darjan for Rs 120:
  preview should show 12 pieces at Rs 10 each; saving adds 12 to stock once.
- [ ] If testing a weight-based ingredient, 1 Mann converts to 40 kg, or 40000 g
  when the ingredient is stored in grams. Check the displayed storage unit.
- [ ] Cancel a purchase: stock does not change. Try zero/negative quantities and
  invalid cost: no invalid purchase should be recorded.
- [ ] In Wastage, record 2 pieces of a Rs 10 ingredient with a reason and valid
  staff authentication: stock drops by 2 and recorded loss is Rs 20.
- [ ] Try missing reason, invalid staff PIN and invalid quantity: no wastage is
  posted. Cancel also leaves stock unchanged.
- [ ] Bring a test ingredient below its threshold: check Catalog low-stock
  filtering and Supervisor's stock alert/Refresh stock control.
- [ ] In the test environment, sell an item with insufficient stock: the sale
  should continue under Perpetual Stock, with a negative balance/stock alert.

## 9. Khata

- [ ] Create QA Supplier with contact and supplied-ingredient details. Search,
  edit and reopen it: data remains correct.
- [ ] Log a credit delivery of Rs 1000 with slip/reference and stock details:
  supplier balance increases by Rs 1000; check any configured stock receipt.
- [ ] Record Rs 400 payment from external funds: outstanding balance becomes
  Rs 600 and the Cashier drawer does not decrease.
- [ ] In a separate suitable open Cashier shift, test a drawer-funded payment:
  supplier balance decreases and a matching Pay-Out is recorded once.
- [ ] Check ledger dates, references, added/paid amounts and running balances.
- [ ] Try an invalid amount and cancel a delivery/payment: neither should post.
- [ ] Test supplier deletion only on an unused throwaway supplier; cancelling
  the confirmation must preserve it.

## 10. Supervisor -> Feature Toggles

- [ ] Turn Interactive Token Queue Tray off, revisit navigation, then restart:
  verify token navigation respects the saved setting. Restore it on.
- [ ] Turn Cashier Void Requests off and try the Cashier void entry point: it is
  blocked. Restore on and verify it is available for eligible test orders.
- [ ] Set discrepancy threshold to Rs 100; reopen/restart and verify persistence.
- [ ] Try a negative threshold or non-number: saving is rejected.
- [ ] Compare the Cashier void toggle in Catalog -> Settings & Toggles with the
  Supervisor setting; they should reflect the same stored setting after refresh.
- [ ] Some void UI wording refers to older Supervisor-PIN behavior. For current
  Order Revision acceptance, consult ADR 0010/0013: Cashier revisions require
  reasons and stock disposition; settled rider-trip orders remain locked.

## 11. Supervisor -> Token Queue Tray and Kitchen Station

- [ ] As Cashier, open a shift and confirm two simple test orders. Record tokens.
- [ ] As Manager, open Kitchen Station: new Preparing orders display their items.
- [ ] Use PLATED ON PASS (MARK READY): the order moves to Ready.
- [ ] In Token Queue Tray, check filtering/refresh and Mark Delivered: the token
  moves to its delivered state without generating another sale.
- [ ] Confirm cancelled orders do not remain actionable preparation tickets.
- [ ] Confirm status changes preserve token numbers and order values.

## 12. Riders: dispatch and alerts

- [ ] Create test Delivery orders as Cashier; in Riders, select eligible orders,
  choose a configured rider, enter a trip name and dispatch.
- [ ] Try dispatch with no orders or no rider: a clear validation message appears.
- [ ] Check that an order cannot be dispatched twice.
- [ ] Mark one order delivered and return another with a reason; verify statuses.
- [ ] Revise an unsettled dispatched order as Cashier and check the Manager
  dispatch alert and Acknowledge action.
- [ ] COD remains Collection Due until Cashier trip settlement; delivered alone
  must not turn it into received drawer cash.
- [ ] Settle through the Cashier flow and verify amounts. Afterwards, attempts
  to revise/cancel orders belonging to that settled trip must be blocked.

## 13. Supervisor -> Discrepancy Review

- [ ] Use a fresh test shift for known arithmetic: opening float Rs 1000, sell
  2 QA Burgers at Rs 116 for cash, no discount/modifier/other cash movements.
  Tender Rs 500 and return Rs 268: net received is Rs 232, expected drawer Rs 1232.
- [ ] During blind close, expected cash must not be revealed before counting.
- [ ] Count Rs 1032: variance is -Rs 200. With threshold Rs 100, the shift is
  flagged, but a new Cashier shift can still open.
- [ ] As Manager, refresh Discrepancy Review: verify Cashier, shift, times,
  -Rs 200 variance and flagged state.
- [ ] Try Resolve without notes: reject. Resolve with a meaningful note: retain
  the original variance and add resolution details. Reopen/restart to confirm.

## 14. Supervisor -> Z-Reports & Backups

Do these after all test transactions. Finalization closes the test Business Day.

- [ ] Refresh Report Data and View Full Z-Report & Summary. Compare sales,
  tender totals, refunds, Collection Due, wastage, stock and shift discrepancies
  with the records you made. Collection Due is not received cash.
- [ ] Export the daily XLSX and open it: verify its six worksheets, dates and
  sample totals. Check units before comparing: sealed report-workbook monetary
  cells use integer paisa; Rs 116 corresponds to 11600 paisa.
- [ ] Set primary backup folder outside the runtime media directory; Save and
  reopen. Optionally set a connected secondary/USB target.
- [ ] Trigger Instant Database Backup Now: find the reported timestamped ZIP.
  Extract to a separate inspection folder: it contains `pos.db` and
  `catalog_media/` including saved picture files. Do not replace live files.
- [ ] Disconnect the optional USB target and back up again: local backup still
  exists and a secondary-copy warning is visible.
- [ ] Open Finalize & Lock Business Day, then Cancel: the day remains open.
- [ ] Finalize the disposable test day with confirmation: it is sealed, local
  report artifacts appear, and old orders cannot be changed through normal flows.
- [ ] Open the next Business Day and make its first test order: token restarts
  at #01 while the old day's orders and token history remain intact.

## 15. Report delivery & archive

- [ ] Open Z-Reports & Backups -> Report delivery & archive. Save a sender and
  approved recipient you control, using the provider setup described in
  `docs/report-delivery.md`.
- [ ] Check saved Gmail sign-in if using Gmail: get a clear success or error.
- [ ] Send test email with sample PDF & Excel and confirm: both attachments
  arrive and open. This is a real email containing synthetic sample data.
- [ ] With automatic delivery enabled, close a disposable test Business Day:
  verify saved PDF/XLSX artifacts and its delivery-history entry.
- [ ] In a test environment, close a day offline: day-close remains committed;
  local reports remain usable and pending delivery survives restart. Reconnect
  with the app running and check history again.
- [ ] Test Send / resend saved report with a reason only to your test recipient.
  A resend must use the saved report rather than current edited catalog values.
- [ ] ACCEPTED is submission status, not proof of inbox arrival. For AMBIGUOUS,
  check Sent/provider history before retrying to avoid an extra copy.
- [ ] Backup creation is available; there is no general in-app restore wizard.
  Database/media backup and report-file retention are separate concerns; see
  `docs/backups.md` and `docs/report-delivery.md` for recovery/retention details.

## 16. Final persistence and usability pass

- [ ] Close/reopen the app: staff, categories, recipes, pictures, settings,
  balances, historical orders and report history remain saved.
- [ ] Try Tab/Shift+Tab, keyboard activation and File Explorer cancellation.
- [ ] At normal and enlarged Windows scaling, verify errors, Save/Cancel and
  confirmation buttons are readable and reachable, with no clipped totals.
- [ ] If a printer/drawer is configured, manually verify receipt/KOT output,
  reprint behavior and disconnected-device errors. A passing software build
  does not verify the particular printer or cash drawer on your PC.
- [ ] Record unresolved findings. Restore test settings and deactivate disposable
  staff/items as appropriate; financial test records remain part of their test
  database rather than being silently erased.

## Failure report template

```text
Checklist section / step:
App BUILD-INFO source commit:
Screen and logged-in role (no PIN):
Steps and sample inputs:
Expected result:
Actual result / exact error:
Screenshot:
Reproducible after reopening? Yes / No:
```
