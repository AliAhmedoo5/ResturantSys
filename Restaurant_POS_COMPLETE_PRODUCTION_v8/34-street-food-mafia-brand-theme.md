# 34 — Final visual theme: Street-Food / Mafia Branding (v8)

**Confirmed 18 October 2026. Authoritative theme update.** This chapter replaces older **Warm Counter** UI color/design direction wherever they conflict. It does **not** change any functional rule from chapters 00–33, including the two roles, mandatory recipes, optional images, cashier order editing, service areas, manual tenders and audit/stock invariants.

## 34.1 Identity and intended feel

High-energy street-food / mafia-influenced restaurant visual identity, inspired by bold menu advertising aesthetics: stylized crown icons, sparing brush-stroke graphics, strong sans-serif headings and realistic product photography. Do not copy Crunch Cartel's actual protected logos, graphics or copyrighted photos; use authorized restaurant assets and original design patterns. Prioritize usability rather than imitation.

## 34.2 Color tokens (suggested, not official brand codes)

| Name | Hex | Usage |
|---|---|---|
| Obsidian Black | `#050708` | Primary app background |
| Dark Navy | `#101820` | Fixed compact sidebar, deepest surfaces |
| Cartel Yellow | `#FFC400` | Primary CTAs, highlighted active navigation |
| Burnt Gold | `#F5A623` | Secondary accents, subtle brush strokes |
| Off White | `#F5F7FA` | Main readable text |
| Card Surface | `#14242D` | Cards, modals, data tables |

Supplement with tested accessible grays/borders and semantic green (ready), amber (preparing), blue (delivery), red (cancelled/failed); the team must validate contrast, especially small text on dark surfaces.

## 34.3 Component principles

- **Background:** black and charcoal, no distracting texture in cashier task surfaces.
- **Sidebar:** fixed, dark, compact, visible labels and clear active-state yellow marker.
- **Cards:** dark navy surfaces, restrained 1px border, subtle shadows; avoid oversized dashboard cards.
- **Primary button:** bright yellow with dark text; high focus affordance, proper disabled/loading states.
- **Typography:** bold sans-serif brand header, readable mid-weight functional text, tabular figures for money and quantities.
- **Icons:** simple outline icon system; yellow highlights only for selected or important states. Crowns belong to brand identity, not generic controls.
- **Tables:** dense yet legible, sortable, compact, accessible row actions. No distracting colors on financial rows.
- **Status badges:** green Ready, amber Preparing, blue Out for Delivery, red Cancelled/Failed; always text + icon, never color alone.
- **Food pictures:** crisp realistic images when Manager has uploaded any; gallery is OPTIONAL and a text/icon fallback always works.
- **Corners:** slightly rounded, mostly 8–12px, not excessive pills.
- **Shadows:** restrained depth, extremely subtle glow only in promotional or brand regions, never as a system health signal.

## 34.4 Flutter token implementation guidance

Create semantic token classes rather than scattered hex literals. Example constants:

```dart
class BrandPalette {
  static const obsidian = Color(0xFF050708);
  static const darkNavy = Color(0xFF101820);
  static const yellow = Color(0xFFFFC400);
  static const burntGold = Color(0xFFF5A623);
  static const offWhite = Color(0xFFF5F7FA);
  static const cardSurface = Color(0xFF14242D);
}
```

Define additional accessible `onSurface`, `secondaryText`, `border`, `focus`, `error`, `warning`, `success`, `info`, `disabled` through the theme. Do not use yellow for every status. Test text-on-yellow and text-on-card in the actual Windows rendering engine; do not presume contrast from raw hex values alone.

## 34.5 Cashier screen layout remains operational

At baseline 1366×768: dark fixed sidebar and narrow header; product grid and search on left, pinned cart/total/Continue action on right. Flow `Cart → Customer Details → Payment → Complete Order`. The main action gets bright yellow. Long product lists scroll inside their own grid only; the whole cashier page and total do not move. Photos use thumbnails and optional manager-uploaded cover, with fallback; price and item title stay prominent. One-tap add, hold/recall, discount presets and configured keyboard shortcuts remain unobstructed.

## 34.6 Manager pages and reports

Apply tokens to Menu & Deals/recipe editor, inventory, suppliers/Khata, payroll, cash expenses, delivery areas, reports, staff PINs and settings. Reports use dark tables and accessible graphs, not excessive yellow charts. Management CRUD sheets maintain labels/validation clearly; yellow primary actions are reserved for Save/Publish/Confirm. Menu/deal editor displays an optional picture uploader and mandatory recipe gate separately.

## 34.7 Pass/fail acceptance

1. Check default light/warm style is no longer present as production default, and theme palette uses exact six provided hex values.
2. Primary yellow CTA is readable with dark text and keyboard focus visible.
3. Cashier at 1366×768 completes a simple sale without page-level scrolling; totals, price and action persist with optional food photographs.
4. Product with no photograph renders designed readable placeholder and can be sold if BOM complete.
5. All four semantic statuses use text and accessible colors.
6. Back-office ledger tables remain readable with many rows and large currency values at 100%, 125% and 150% Windows scaling.
7. Brand crown/brush strokes appear only in restrained identity/accent placement, not on cash fields, error text or stock/count numbers.
8. No copyrighted third-party photos/brand art are bundled without authorization.
9. Complete keyboard and screen-reader focus/contrast acceptance for cashier and Manager forms.

**Precedence:** Chapter 34 governs visual treatment, while chapters 30–33 continue to govern order edits, stock, payments, mandatory recipes, engineering specifics, service areas, customer step and optional media.
