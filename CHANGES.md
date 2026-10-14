# Changes

All notable changes to this library. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow semantic
versioning once released.

## 0.1.1

### Added

- `Position.Cost_precision` (`eight`, the default, `four`, or `of_decimals` from 0 to 8)
  and `?precision` and `?rounding` on `Position.average_cost`. The exact quotient is
  rounded once at the chosen precision (default half-even); the defaults give the same
  results as 0.1.0.

## 0.1.0

### Added

- Instruments: `Symbol`, `Isin` (with check digit), `Listing` (MIC, currency, status),
  `Instrument`, `Catalog`.
- Prices: `Price` and six-place `Quantity` with directional rounding, end-of-day `Close`
  with origin preference, `Price_history` (quotes, windows, 52-week range), `Staleness`.
- `Market_data.S` with a deterministic `Simulated` source and a `Fixed` source.
- Orders: `Order_request` (amount, quantity, all), `Order_limits`, `Placement` with typed
  refusals, and the `Order` state machine with submission tracking.
- `Position` with reservations and average cost basis, `Portfolio` summaries.
- `Booking`: ledger entries for holds, settlement (with over-capture), release and
  proceeds.
- `Broker.S` and an in-memory `Sim_broker` with spread, delay and manual decisions.
- `Recurring_buy` dates, order ids and failure pausing.
- Stable bin_prot types with pinned digests; `examples/quickstart.ml`.
