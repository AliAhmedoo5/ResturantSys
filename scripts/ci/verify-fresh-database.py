"""Inspect only the isolated database created by the remote package smoke check."""
import sqlite3
import sys
from pathlib import Path

path = Path(sys.argv[1]).resolve()
with sqlite3.connect(path.as_uri() + '?mode=ro', uri=True) as database:
    assert database.execute('PRAGMA integrity_check').fetchall() == [('ok',)]
    assert database.execute('PRAGMA foreign_key_check').fetchall() == []
    assert database.execute('PRAGMA user_version').fetchone()[0] >= 15
    assert database.execute('SELECT COUNT(*) FROM staff').fetchone()[0] == 0, 'Default staff accounts must not ship'
    assert database.execute("SELECT value FROM system_settings WHERE key = 'onboarding_completed'").fetchone() == ('false',)
print('Fresh database integrity passed; no default staff logins.')
