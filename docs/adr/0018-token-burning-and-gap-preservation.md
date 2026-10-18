# Token Burning and Audit Gap Preservation

## Context
Reusing or recycling canceled order numbers or daily token numbers (#01, #02...) causes kitchen confusion, duplicate tickets, and audit tampering where missing orders can be masked.

## Decision
1. Daily sequential tokens are allocated strictly at atomic order commit. Held or unconfirmed drafts receive no token.
2. Once allocated, a token is permanently burned. If Token #14 is subsequently canceled, revised, or refunded, the next order is assigned Token #15. Gaps created by cancellations are preserved as part of the immutable financial audit log.
3. Tokens reset to #01 only upon opening a new Business Day.

## Consequences
- Guaranteed uniqueness of daily pickup chits.
- Prevents order masking or gap manipulation in accounting audits.
