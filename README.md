# investing-core

Retail brokerage as pure OCaml values: instruments and listings, end-of-day prices,
market orders for fractional shares, positions with average cost basis, and the double-entry
ledger entries for the cash side of every order. There is no storage and no network code:
a service keeps the values in its own store and calls a real broker or data vendor through
the module types defined here. A simulated market-data source and a simulated broker make
the whole flow runnable in tests and demos.

## Why separate

A bank or app that lets customers buy shares needs the same rules wherever the orders end
up: how cash turns into a fractional quantity and which way each amount rounds, which
orders may be cancelled, how much cash to hold and what to do when the fill costs more
than the hold, how the cost basis moves on a partial sale, when an end-of-day price is too
old to trade on. Those rules are easy to get subtly wrong and hard to test through HTTP.
Keeping them in a library with no I/O makes every rule an expect test or a property, lets
two services (an API and a back-office tool) share them, and keeps the broker and the
data vendor swappable behind small module types. Matching engines such as
`exchange-core` and `order-book` solve a different problem (an exchange's book); this
library is the customer's side of a brokerage account.

## Quick start

The library builds with the OxCaml compiler (its `money` and `fixed-decimal` dependencies
need it). Pin the organization's libraries in dependency order, then this one:

```sh
opam pin add fixed-decimal https://github.com/winterchill-trading/fixed-decimal.git
opam pin add money https://github.com/winterchill-trading/money.git
opam pin add ledger https://github.com/winterchill-trading/ledger.git
opam pin add investing-core https://github.com/winterchill-trading/investing-core.git
```

In a dune file: `(libraries investing-core)`; the top module is `Investing_core`.

## Usage

[`examples/quickstart.ml`](examples/quickstart.ml) walks one buy from prices to
portfolio, and its output is checked by `dune test`:

```ocaml
let plan =
  Placement.plan ~instrument ~prices ~today ~position:None
    (Buy_amount (Money.Amount.of_string "250.00 USD"))
(* buy 6.024096 ACME at 41.5, hold 250.00 USD *)

let order = Order.create ~id ~account:customer ~symbol ~request ~plan ~at:now
let hold_entries = Booking.buy_placed balances order ~at:now
(* the broker fills at 41.52075 (5 bps spread): cost 250.13 USD *)
let settlement = Booking.transition chart balances ~before:order ~after:filled ~at
(* one over-capture entry: 250.00 from the hold, 0.13 from the balance *)
```

```
plan: buy 6.024096 ACME at 41.5, hold 250.00 USD
after hold: available 750.00 USD, held 250.00 USD
fill: 6.024096 at 41.52075, cost 250.13 USD
after fill: available 749.87 USD, held 0.00 USD, owed to broker 250.13 USD
portfolio: value 250.00 USD, cost 250.13 USD, unrealised -0.13 USD, average cost 41.52158266
```

## Model

| Module | What it is |
|---|---|
| `Symbol`, `Isin` | Ticker symbols; ISINs with their Luhn check digit |
| `Listing`, `Instrument`, `Catalog` | Exchange (MIC), currency and status; the security; search by text and kind |
| `Price`, `Quantity` | Positive prices to 8 places; share quantities to 6 places, never negative; products rounded in a named direction |
| `Close`, `Price_history`, `Staleness` | End-of-day closes with an origin preference (feed over seed over simulated), quotes with previous close, windows and 52-week range, stale and too-old rules |
| `Market_data` | `S` (a source of closes), `Simulated` (deterministic random walk), `Fixed` (serves given closes) |
| `Order_request`, `Order_limits`, `Placement` | Buy by amount or quantity, sell by quantity, amount or all; minimum and maximum order value; sizing and typed refusals |
| `Order` | The order state machine with submission tracking |
| `Position`, `Portfolio` | Holdings with reservations, average cost basis, realised and unrealised results; a valued summary in one currency |
| `Booking` | Ledger entries for holds, settlement, release and proceeds |
| `Broker`, `Sim_broker` | The brokerage port (`Broker.S`) and an in-memory simulated broker |
| `Recurring_buy` | Due dates, deterministic order ids and failure pausing for scheduled buys |

### Rules

- **Rounding by direction.** Cash becomes shares rounded down to a millionth, so a buy by
  amount never costs more than the amount at the estimate price. A buy's cost rounds up
  and a sale's proceeds round down to the currency's minor unit. Quantities with more than
  six decimals are refused, not cut.
- **Sizing.** A buy by amount holds the amount; a buy by quantity holds its estimated
  cost. Sells hold no cash; they reserve shares, and a new sell may only use shares not
  already reserved. `Sell_all` is the only sell exempt from the minimum order value, so a
  small remainder can always be sold.
- **Prices.** For each symbol and date one close is kept: a feed's close replaces seed
  data, which replaces a simulated close. Orders are estimated at the latest close on or
  before today; by default a close older than 4 days is stale (shown with its age) and one
  older than 10 days is refused.
- **Order life.** `pending -> filled | rejected | cancelled`, and final states are final.
  While pending, the order records whether it was sent and whether the broker
  acknowledged it. An unsent order can be cancelled here; a sent order with no answer
  cannot (the broker may be executing it); an acknowledged one is cancelled after the
  broker confirms. A broker fill is always for the whole quantity.
- **Cost basis.** Average cost: a buy adds its cost; a sale removes
  `basis * sold / held` (half-even), or the whole basis when the position empties, so no
  cent is ever stranded. Realised result is proceeds minus the basis removed. Fees and FX
  costs are not part of the basis.
- **Staleness and limits are values**, so a service can configure them per market.

### Ledger entries

| Event | Entries (account currency = instrument currency) | Idempotency key |
|---|---|---|
| Buy placed | hold: customer -> customer/pending | `order:<id>:hold` |
| Buy filled at or below the hold | capture cost to `clearing:brokerage/<ccy>`, release the rest, one entry | `order:<id>:settlement` |
| Buy filled above the hold | over-capture: the hold plus the difference from the balance; refused by the ledger when the balance cannot pay | `order:<id>:settlement` |
| Buy rejected or cancelled | release the hold | `order:<id>:release` |
| Sell filled | `clearing:brokerage/<ccy>` -> customer, the proceeds | `order:<id>:proceeds` |

The brokerage clearing account may go negative: after buys it shows what is owed to the
broker, after sales what the broker owes, and it returns to zero when the broker settles.
Shares are not ledger balances; `Position` tracks them.

### Simulated market data and broker

`Market_data.Simulated` walks each symbol from a start price on an anchor date, one step
of at most `daily_bps` per weekday, with steps derived from MD5 of the seed, symbol and
date: the same prices on every machine and for every query range, published rounded to
`decimals` places. `Sim_broker` accepts every order (idempotently per key), and after
`fill_delay` fills it whole at the reference close moved by `spread_bps` against the
customer, or rejects it when there is no price or the configured outcome is to reject.
Its clock is an Async `Time_source`; nothing happens until `emit_due` runs (from `start`
in a service, directly in a test). `fill_now` and `reject_now` decide an order at once.

## Tests

`dune test` runs expect tests for every module and Quickcheck properties:

- shares bought for an amount never cost more than the amount, and one more millionth
  would;
- a buy's hold always covers its estimated cost;
- cost basis is conserved over random buys and sells (paid = held basis + removed basis,
  realised = received - removed) and selling everything leaves nothing behind;
- a partial sale removes its exact share of the basis within half a minor unit;
- over random event streams final states never change, fills are whole and nothing is
  cancelled while in transit;
- simulated closes from a range query equal single-day closes, on both sides of the
  anchor;
- recurring dates from a range agree with the dates by index.

Stable `bin_prot` digests are pinned in `test/test_stable.ml`; a change there means a new
`Stable.V2`, not an edit of `V1`.

## Portability

The only OxCaml-specific syntax is layout annotations: `Price.t` and `Quantity.t` are
declared `immediate`, and `Quantity` takes `Fixed_decimal.S` modules as
`('a : immediate)`. It depends on Jane Street's
`v0.18~preview` packages, published in the OxCaml opam repository, and on `money`,
`ledger` and `fixed-decimal` from this organization.

## Releasing

The version lives in git tags and is written into `investing-core.opam` by `dune subst`;
`CHANGES.md` collects notes under `## Unreleased`. Release `fixed-decimal`, `money` and
`ledger` first, then follow the `dune-release` flow. Nothing has been released yet.

## Known gaps

- **FX legs.** An order's cash legs are booked in the instrument's currency; an account in
  another currency must convert first with its own FX booking. Pricing and booking a
  conversion inside the order flow belongs with an FX library.
- **Partial fills, limit orders and order expiry** are not modelled; orders are market
  orders filled whole.
- **Fees** (commission, FX markup) are not charged or added to the cost basis.
- **Corporate actions** (splits, dividends, symbol changes) and tax-lot methods other than
  average cost (FIFO, specific lots) are not modelled.
- **Portfolio history** (value per day) needs positions per day; the library values
  current positions only.
- A real market-data fetcher and a real broker adapter implement `Market_data.S` and
  `Broker.S` outside this library.

## Used by

No other repository in the organization depends on it yet.
