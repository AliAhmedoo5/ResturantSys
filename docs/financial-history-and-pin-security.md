# Supplier history and PIN security

Schema version 17 protects existing installations as well as fresh databases.

Removing a supplier with any Khata transaction, opening balance, or current
balance archives the supplier. Even a fully settled ledger counts as history.
Only an unused supplier with zero balances can be permanently deleted. A database
trigger rejects direct deletion of suppliers with financial history, including
the old cascading delete path.

The supplier workspace shows archived suppliers with an Archived badge. Their
statements and settlements remain available. New deliveries require restoring
the supplier using Restore supplier in its menu. Archive supplier is also
available for unused suppliers that management wants to keep.

New PIN verifiers use PBKDF2-HMAC-SHA256 with 600,000 iterations, a random
16-byte salt, and a 32-byte verifier. The work factor and salt are included in
the stored versioned value. The work factor follows the
[OWASP PBKDF2-HMAC-SHA256 guidance](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html#pbkdf2).
Authentication performs slow derivation in a
background isolate. Existing SHA-256 credentials remain usable and are replaced
with PBKDF2 only after successful verification; plaintext PINs are never migrated
or stored. Existing credentials not yet used retain their legacy verifier until
successful login or a manager PIN reset.

PIN equality lookup uses an HMAC-SHA256 fingerprint. Its random 32-byte key lives
in flutter_secure_storage under the current OS user, scoped to the database path;
the key is never written into SQLite. A database key-check value detects a
missing or mismatched OS key and authentication fails closed. Copying a database
to another Windows user, machine, or path therefore requires recovery of its
original OS credential-store entry. A database backup alone does not contain
that key. This change does not implement portable key recovery or the separate
guided backup restore workflow.

Five failed attempts cause a one-minute lockout. Device and active-drawer
counters are shared by login, Manager approval, PIN changes, and wastage PIN
verification, and persist across service recreation and database reopening.
PIN-only entry cannot identify an account for an unknown PIN, so device/drawer
counters protect that path. Identified-account PIN changes and rejected
Cashier PINs used for Manager approval also record a staff counter. Concurrent
attempts serialize through SQLite transactions. A correct PIN does not bypass
an unexpired lock. Successful verification after expiry clears applicable
counters. Manager approval has a separate counter that ordinary Cashier login
cannot clear. Clock rollback cannot expire a lock early.

PIN uniqueness checks cover registration, profile PIN edits, Manager resets,
and self-service PIN changes. A unique fingerprint index protects concurrent
writes; credentials awaiting fingerprint enrollment are verified during
duplicate checks. Non-login staff have no usable PIN.

The root causes were a cascading supplier delete, shared-salt hash equality in
authentication and duplicate checks, and no durable failed-attempt state. The
initial GitHub Actions reproduction failed all three assertions in
`test/security/urgent_protection_test.dart`. Subsequent regression coverage also
checks settled history, direct database deletion, opening balances, archive
restoration, legacy migration, duplicate PIN paths, parallel attempts, lock
expiry, missing OS keys, and schema migration.
