# Soft Inventory Deduction During Peak Service

Fast-food counter checkout cannot afford to block customer queues when database stock quantities drop to zero or negative due to delayed invoice entry or untracked emergency stock. We decided to allow sales transactions to proceed even when raw ingredient stock is insufficient, recording negative inventory balances alongside visual alerts. This prioritizes counter throughput and customer service during rushes while deferring stock reconciliations to post-shift inventory adjustments and purchase logging.
