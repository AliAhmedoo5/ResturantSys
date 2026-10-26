# ResturantPOS for Windows x64

Extract the entire ZIP into a writable application folder, then launch
`resturant_sys.exe`. Keep the `data` folder and every DLL beside the executable.
Visual C++ runtime libraries are included. This portable package is unsigned.
No physical receipt printer or cash drawer device is required.

On first launch, complete onboarding: restaurant identity, separate Manager and
Cashier PINs, catalog/recipes and the first Business Day. There are no default
staff credentials. Sign in as Cashier and open a shift for counter operations;
use the Manager account for administration and analytics.

## Existing installations

Create and verify a backup through Manager Portal → Z-Reports & Backups before
upgrading. Close the old application and replace the application folder with a
fresh extraction. Never run two versions against the same live database.

Business data normally lives at `%ProgramData%\ResturantPOS\data\pos.db`; it is
separate from this package. Preserve that directory and catalog media. Schema
upgrades run automatically; reverting an executable does not undo a database
migration. Recovery requires a verified pre-upgrade backup and matching app.
See the repository's `docs/backups.md` for the full backup/recovery procedure.

## Daily operation

Use Cashier Orders to track preparation and completion. Delivery orders retain
rider trip dispatch/settlement rules. Shift close and Business Day Z-Close are
separate operations. Verify opening cash, tax configuration and payment tenders
against the restaurant's operating policy before live billing.

Manager analytics includes live and historical data, source drill-down and
CSV/XLSX/PDF downloads. Missing historical inputs are identified as unavailable;
they are not estimates of profit or payroll. Email delivery requires the
restaurant's own SMTP configuration; local exports work without email.

## Package verification

Compare `Get-FileHash .\resturant-pos-windows-x64.zip -Algorithm SHA256` with
`SHA256SUMS.txt` from the same release. `build-manifest.json` identifies the source
commit, version and GitHub Actions run. Remote checks cover automated behavior,
database recovery and launch of a fresh extraction. Complete first-run setup and
verify the restaurant's own data before taking live payments.
