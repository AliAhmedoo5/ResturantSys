# Warm Counter Theme & Design System Specification

A clean, modern restaurant interface with warm neutral backgrounds, deep green actions, clear typography, and practical touch controls.

## 1. Visual Philosophy & Core Tenets

- **Calm & Restrained**: Most surfaces remain neutral. Avoid gradients, glassmorphism, heavy drop shadows, and saturated colored containers.
- **Deep Green Actions**: Green is reserved strictly for primary affirmative actions (`Charge`, `Mark ready`, `Record payment`) and selected/active navigation states.
- **High-Speed Ergonomics**: All interactive elements satisfy a minimum 48px touch target. Corner radii are standardized (8px for controls, 12px for panels).
- **Numeral Precision**: Prices and quantities are right-aligned with fixed tabular numeral widths (`FontFeature.tabularFigures()`) to prevent visual jitter when totals update.
- **Tactile Clarity**: States are communicated through both color and explicit textual or structural feedback.

---

## 2. Color System

| Element | Light Mode | Dark Mode | Usage & Rationale |
|---|---|---|---|
| **Page background** | `#F5F3EE` | `#151A17` | Warm stone/charcoal background reducing glare under harsh store lights |
| **Cards & panels** | `#FFFFFF` | `#202722` | Crisp, flat containers for content isolation without heavy shadows |
| **Primary text** | `#202822` | `#F0F3EE` | High contrast body, headings, and amounts |
| **Secondary text** | `#59635B` | `#B2BEB4` | Subdued metadata, secondary labels, and timestamps |
| **Primary action** | `#245C40` | `#9ED3AC` | Deep green for the single prominent action per workflow |
| **Text on primary** | `#FFFFFF` | `#142B1C` | Maximum legibility on primary action surfaces |
| **Borders** | `#D9DED5` | `#414D43` | Clean 1px structural separation without thick visual weight |
| **Warning** | Amber (`#D97706`) | Soft amber (`#FBBF24`) | Discrepancy flags, low-stock warnings, paper low alert |
| **Destructive action** | Muted red (`#DC2626`) | Soft red (`#F87171`) | Voiding orders, discarding cart, cancelling transactions |
| **Active section highlight** | Pale green (`#E3EFE7`) | Subtle forest tint (`#1C3324`) | Selected sidebar navigation item and active category tabs |

---

## 3. Typography & Numerical Spacing

- **Primary Font**: `Inter`, with `Segoe UI` and `sans-serif` system fallbacks.
- **Tabular Figures**: All currency, quantities, tokens, and numeric inputs MUST enable tabular figures (`fontFeatures: [FontFeature.tabularFigures()]`) to ensure vertically aligned numerals across tables and receipts.

### Typography Hierarchy

| Style Token | Size | Weight | Line Height | Primary Role |
|---|---|---|---|---|
| **Kitchen Token / Change** | 36–44px | 800 (ExtraBold) | 1.1 | Kitchen queue board tokens, payment return change callout |
| **Order Total** | 32px | 700 (Bold) | 1.2 | Cart checkout total, shift opening float, register cash summary |
| **Page Heading** | 24px | 600 (SemiBold) | 1.25 | Main screen headers, modal titles, section dividers |
| **Body & Inputs** | 16px | 400 / 500 (Medium) | 1.4 | Form text fields, menu item titles, table cells, numpad buttons |
| **Secondary Label** | 14px | 400 / 500 (Medium) | 1.4 | Field captions, timestamps, modifiers breakdown, table column headers |

### Spacing & Corner Tokens

- **Grid Spacing**: Standardized 8px base increments: `8px`, `12px`, `16px`, `24px`, and `32px`.
- **Corner Radii**:
  - `8px`: Interactive controls (buttons, text inputs, category chips, numpad keys).
  - `12px`: Structural containers (cards, side panels, modals, dialogs).
- **Touch Target**: Minimum `48px × 48px` bounding box for all interactive click/tap targets.
- **Alignment**: Currency and prices are always aligned to the right.

---

## 4. Application Shell Layout

### Header
- Fixed at the top across all operational views.
- Displays:
  1. **Restaurant Name** & Terminal ID.
  2. **Business Date** & status.
  3. **Shift Status** (e.g., Active Shift #02).
  4. **Active Staff** (Name & Department).
  5. **Printer Status** indicator (Online / Paper Low / Offline).
  6. **1-Tap Lock Action** (`Lock Register` button returning immediately to the PIN numpad).

### Sidebar
- Compact, labeled vertical navigation positioned on the left.
- Simple, high-clarity outline icons.
- Highlights the active section with a **pale green background** (`#E3EFE7` in light mode, `#1C3324` in dark mode).

### Workspace
- Clear page heading (24px semibold).
- Top bar with relevant contextual controls (search, filter chips, date range pickers).
- Main content layout keeping frequent actions in direct reach.
- **Single Prominent Action**: Each workflow view presents one clear primary deep-green button (e.g., `Charge`, `Mark ready`, `Record payment`, `Generate Z-Report`).

---

## 5. Screen Design Directions

| Screen | UI Direction |
|---|---|
| **Counter** | Menu search and category tabs positioned above a spacious item grid. Fixed order panel on the right displaying dining type selector (Dine-In, Takeaway, Delivery), item quantities, modifier breakdowns, subtotal/tax/discount, 32px order total, and a prominent 48px+ `Charge` button. |
| **Payment** | Clean, focused settlement panel with dedicated tabs for `Cash`, `Card`, `Raast`, and `Split`. Large numeric input for amount tendered and a 36–44px bold display for calculated change return. |
| **Kitchen** | Kanban-style queue with `Preparing`, `Ready`, and `Delivered` columns. Large token identifiers (36–44px), readable item lists, highlighted special instructions/modifiers, and clear progression buttons (`Mark ready`, `Complete`). |
| **Stock & Mandi** | Clean purchase entry form positioned beside current stock table. Displays Desi Mandi unit conversions (Mann, Darjan, Peti) and resulting recipe unit cost directly below the quantity input fields. |
| **Vendor Khata** | Supplier list on the left, clear outstanding balance callout, and a chronological credit/payment ledger on the right. Payment source (`Active Cash Drawer` vs `External Bank`) is prominently selectable in the settlement modal. |
| **Shifts** | Minimalist blind cash-count form with large numeric fields for counted cash. System expected cash is strictly hidden until the count is finalized and submitted. |
| **Reports** | Clean data tables with alternating subtle fills, right-aligned monetary amounts, concise summaries, and clearly labeled export triggers (`Export Excel .xlsx`). |
| **PIN Access** | Clean centered lock screen with a 4-digit masked PIN display and a spacious touch numpad with zero distracting elements. |

---

## 6. UX Behavioral Contracts

1. **One-Tap Addition**: Basic catalog menu items add to cart with a single tap. Modifiers and meal deal choice dialogs only open when options are mandatory or requested.
2. **Persistent Cart Visibility**: The active order panel remains visible and pinned on the right while browsing menu categories and items.
3. **Dual State Communication**: Active and selected states are communicated simultaneously via color (pale green surface) and textual/iconic indicators (checkmarks, filled pills, bold text).
4. **Inline Field Validation**: Validation alerts and error messages are placed directly beside or below the respective input fields, avoiding intrusive blocking popups for minor input errors.
5. **State Preservation on Failure**: If a print, network, or hardware command fails, all entered form data and cart items remain intact and editable.
6. **Decoupled Financial & Hardware Events**: The system explicitly separates **“Sale saved”** (atomic SQLite database commit) from **“Receipt printed”** (hardware spooler queue). Printer disconnects or paper jams never revert a valid sale.
7. **Destructive Action Confirmations**: Final or destructive operations (voiding an order, discarding a cart with items, force closing a shift) require an explicit confirmation dialog.
8. **Hybrid Touch & Physical Keyboard Acceleration**: All controls feature visible focus indicators, with comprehensive hotkey acceleration for mouse-free laptop operation.
9. **Plain, Direct Labels**: Action buttons use clear, unambiguous imperative verbs: **Charge**, **Mark ready**, **Record payment**, **Retry print**, **Lock register**.
10. **Restrained Micro-Animations**: Transitions and feedback animations remain subtle and brief (150ms–200ms) to preserve operational speed during rushes.
