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

The recovery tests extract the ZIP into a fresh temporary directory, open its
database with SQLite, check schema version and integrity, and read saved records
and media. They also exercise backup creation while the live WAL database is in
use. These tests run through GitHub Actions.

To inspect an archive without changing the live restaurant records, extract it
into a separate directory and run SQLite's `PRAGMA integrity_check` and
`PRAGMA foreign_key_check` against the extracted `pos.db`. A healthy database
returns `ok` for integrity and no rows for foreign-key violations. Preserve the
archive and current application data before any recovery operation. This feature
creates backups; it does not replace the live database automatically. When
recovering photos, map the archive's `catalog_media/` contents back to the
application's `media/` directory while preserving relative paths.
