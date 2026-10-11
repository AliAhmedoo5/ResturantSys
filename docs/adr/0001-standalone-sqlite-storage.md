# Standalone Local SQLite Storage

The POS system operates on an in-store Windows counter laptop in environments with zero reliable internet, no dedicated server hardware, and zero recurring cloud subscription budgets. We chose an embedded SQLite database running locally inside the Flutter Windows desktop process instead of a client-server database (like PostgreSQL/MySQL) or cloud backend. This eliminates network latency, guarantees offline counter billing during internet outages, and simplifies deployment to a single self-contained application directory.
