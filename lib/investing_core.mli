(** Retail brokerage domain: instruments, end-of-day prices, fractional market orders,
    positions with cost basis, and the ledger entries for their cash legs. Pure values
    and module types only; nothing here persists or talks to a network. *)

module Isin = Isin
module Listing = Listing
module Price = Price
module Quantity = Quantity
module Symbol = Symbol
