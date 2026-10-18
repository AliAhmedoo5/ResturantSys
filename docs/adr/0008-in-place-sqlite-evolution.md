# In-Place SQLite Evolution Over Framework Rewrite

## Context
The v8 master specification mentions Drift ORM and Riverpod. However, the existing production codebase has a fully functioning embedded SQLite implementation on Windows using `sqflite_common_ffi` with ACID transactions, WAL mode, relational integrity, schema versioning, and direct domain controllers. Replacing this with Drift ORM and code-generated Riverpod would require deleting and rewriting all working database access, repositories, and UI controllers from scratch.

## Decision
We will retain and evolve the existing `sqflite_common_ffi` database architecture in-place. We will execute idempotent raw SQLite DDL migrations to introduce the v8 tables (`order_revisions`, `order_revision_lines`, `delivery_areas`, `customer_addresses`, `catalog_images`) and update existing columns (such as making `cash_movements.approved_by` nullable).

## Consequences
- Preserves all tested database and controller foundations.
- Avoids build-runner dependencies and code-generation churn.
- Strictly adheres to the zero-local-framework-build CI/CD guardrail while maintaining offline-first Windows reliability.
