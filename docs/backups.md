# Database and catalog backups

Managers configure backups under **Manager Portal → Z-Reports & Backups**.
The primary local directory is required; leaving its setting empty uses the
application default. An optional secondary destination can point to a connected
USB drive or writable LAN share. Save destination changes before starting a
manual backup. Business Day Z-Close also uses these saved settings.

Each backup is a timestamped ZIP containing:

```text
pos.db
catalog_media/
  <original relative photo paths>
```

The application stores catalog photos in its `media` directory at runtime. The
archive calls that directory `catalog_media`; it preserves the database-relative
paths within it. A catalog without photos still has an empty media directory in
the archive.

Backup creation checkpoints the WAL without waiting for active readers or
writers, then uses SQLite's online backup API to produce a consistent database
snapshot. Snapshot creation and ZIP compression run on a worker isolate. The live
database stays open for counter billing. A checkpoint alone followed by copying
the live database file would not provide the same consistency guarantee.

Photos are staged and checked against the snapshot's recorded paths, sizes, and
checksums before publishing the archive. Missing or changed referenced photos
fail the backup rather than producing an incomplete recovery copy. Backup
destinations must be outside the source media directory.

The primary archive is published only after it has been completed. Repeated
backups with the same timestamp receive distinct filenames. The secondary
destination receives the same archive. If that destination is unavailable, the
primary copy is retained and the result reports a warning. Check the reported
paths rather than assuming a disconnected USB drive has received a copy.

## Durable backup attempt history and health

Every backup attempt—whether initiated interactively (`MANUAL`), automatically
by Business Day Z-Close (`Z_CLOSE`), or on a background schedule (`SCHEDULED`)—is
persisted immediately to an immutable SQLite table: `backup_attempts`.

Each record captures:
- `attempted_at`: ISO-8601 timestamp of the backup request.
- `initiator`: `MANUAL`, `SCHEDULED`, or `Z_CLOSE`.
- `manager_id`: Authenticated staff account ID for interactive attempts (null for scheduled).
- `primary_status`: Target-specific primary result (`SUCCESS`, `FAILED`, `SKIPPED`).
- `primary_path`: Completed archive path on the primary disk.
- `secondary_status`: Target-specific secondary result (`SUCCESS`, `WARNING`, `FAILED`, `NOT_CONFIGURED`, `SKIPPED`).
- `secondary_path`: Completed copy path on external USB drive or share.
- `verification_status`: Integrity and archive verification outcome (`VERIFIED`, `FAILED`, `UNVERIFIED`).
- `failure_category`: Safe classification enum (`NONE`, `STORAGE_UNAVAILABLE`, `MEDIA_CORRUPTED`, `DESTINATION_INVALID`, `PERMISSION_DENIED`, `DATABASE_ERROR`, `UNKNOWN`).
- `failure_message`: Sanitized, confidential-safe failure or warning description.

SQLite triggers enforce append-only immutability; `UPDATE` and `DELETE` operations
are aborted. Failed attempts and secondary destination warnings are preserved rather
than overwritten or masked.

Configured local or secondary paths in `system_settings` are never treated as
evidence of backup completion. Manager Analytics (`AnalyticsFamily.audit`) and the
Manager Portal display last verified backup age and health metrics directly from
durable SQLite evidence, never inferring history from directory listings or files
on disk.

The recovery tests extract the ZIP into a fresh temporary directory, open its
database with SQLite, check schema version and integrity, and read saved records
and media. They also exercise backup creation while the live WAL database is in
use. These tests run through GitHub Actions.

## Guided restoration

Open **Manager Portal > Z-Reports & Backups > Restore from a backup ZIP**.
Close all shifts and the Business Day first. Select the archive, review its
schema version, order count and media count, and acknowledge replacement of
current records. Canceling this preview does not change restaurant data.

Validation checks ZIP paths, duplicate entries, SQLite integrity and foreign
keys, supported schema versions (18 through the application's current version),
an active Manager login, and referenced photo sizes/checksums. ZIP imports are
limited to 512 MB compressed / 2 GB extracted and 100,000 entries. Links and
paths outside the expected database/media layout are refused.

PIN security uses a key in the original Windows user's credential store. The
restore checks that the archive matches that key before scheduling replacement.
A ZIP alone cannot recover PIN access on a different Windows installation;
recover the original credential store first. The key is never exported in the ZIP.

After confirmation, the application creates a safety ZIP of current database and
media. A failed safety backup prevents scheduling. The dialog displays its path
and offers **Close application to finish restore**. Reopen the POS to finish.
Use the staff PINs from the restored backup afterward.

Replacement happens before SQLite connections or background senders start. The
application also holds an installation lock to prevent a second instance from
opening during recovery. A durable journal retains original database files,
WAL sidecars and media until replacement and migrations pass validation. A
failed or interrupted swap restores those originals. Completed/failed requests,
the original files, and safety ZIP remain available for investigation. Successful
recovery adds a restore audit event and displays a startup result message.

If startup validation fails before replacement, use **Cancel pending restore and
open current records**, or resolve the error and retry. If a swap was interrupted,
retry first to roll it back. The application refuses to bypass an unfinished swap.

For independent inspection, extract an archive into a separate directory and
check SQLite's `PRAGMA integrity_check` and `PRAGMA foreign_key_check`. Never
extract over the live installation.
