(** Retail brokerage domain: instruments, end-of-day prices, fractional market orders,
    positions with cost basis, and the ledger entries for their cash legs. Pure values and
    module types only; nothing here persists or talks to a network. *)

(** Ledger entries for the cash legs of orders. *)
module Booking = Booking

(** The brokerage port: the module type an executing broker implements. *)
module Broker = Broker

(** The instruments on offer, keyed by symbol. *)
module Catalog = Catalog

(** One end-of-day close and where it came from. *)
module Close = Close

(** A tradable security and its listing. *)
module Instrument = Instrument

(** International Securities Identification Numbers. *)
module Isin = Isin

(** Exchange, trading currency and status of an instrument. *)
module Listing = Listing

(** Sources of end-of-day closes, with simulated and fixed implementations. *)
module Market_data = Market_data

(** A market order and its state machine. *)
module Order = Order

(** Caller-chosen order identifiers. *)
module Order_id = Order_id

(** Minimum and maximum order values. *)
module Order_limits = Order_limits

(** A market order request sized by amount, quantity or all. *)
module Order_request = Order_request

(** Sizing and validation of an order request. *)
module Placement = Placement

(** Positions valued at the latest closes. *)
module Portfolio = Portfolio

(** A holding with reservations and average cost basis. *)
module Position = Position

(** Positive per-share prices. *)
module Price = Price

(** Closes per symbol and date, quotes and ranges. *)
module Price_history = Price_history

(** Share quantities to six decimal places. *)
module Quantity = Quantity

(** Scheduled buys: due dates, order ids and failure pausing. *)
module Recurring_buy = Recurring_buy

(** Buy or sell. *)
module Side = Side

(** An in-memory simulated broker. *)
module Sim_broker = Sim_broker

(** How old an end-of-day price may be. *)
module Staleness = Staleness

(** Ticker symbols. *)
module Symbol = Symbol
