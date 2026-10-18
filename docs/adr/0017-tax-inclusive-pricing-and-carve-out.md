# 0% Tax-Inclusive Pricing Default and Carve-Out

## Context
Unexpected sales tax additions at checkout cause customer friction at fast-food counters in Pakistan. Furthermore, provincial sales tax rates and taxability rules vary across regions and categories.

## Decision
1. System installation defaults to `tax_pricing = TAX_INCLUSIVE` and `tax_rate_bps = 0` (0%).
2. The displayed menu price is the exact amount payable by the customer.
3. When the Manager configures an applicable tax rate, the shelf price remains unchanged, and tax is calculated as an internal carve-out:
   `tax_included = rounded_paisa(item_price * rate_bps / (10000 + rate_bps))`
   `taxable_base = item_price - tax_included`.
4. The system never applies an unexpected tax surcharge on top of catalog prices under default settings.

## Consequences
- Transparent shelf-to-payment pricing for customers.
- Full compliance readiness when provincial taxes are enabled without recalculating menu prices.
