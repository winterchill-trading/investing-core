(** Retail brokerage domain: instruments, end-of-day prices, fractional market orders,
    positions with cost basis, and the ledger entries for their cash legs. Pure values
    and module types only; nothing here persists or talks to a network. *)

module Booking = Booking
module Broker = Broker
module Catalog = Catalog
module Close = Close
module Instrument = Instrument
module Isin = Isin
module Listing = Listing
module Market_data = Market_data
module Order = Order
module Order_id = Order_id
module Order_limits = Order_limits
module Order_request = Order_request
module Placement = Placement
module Portfolio = Portfolio
module Position = Position
module Price = Price
module Price_history = Price_history
module Quantity = Quantity
module Recurring_buy = Recurring_buy
module Side = Side
module Sim_broker = Sim_broker
module Staleness = Staleness
module Symbol = Symbol
