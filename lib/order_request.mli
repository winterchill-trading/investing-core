(** What a customer asks for: a market order, sized by cash or by shares.

    - [Buy_amount a]: spend about [a]. The quantity is [a / price] rounded down to a
      millionth of a share, so the estimated cost never exceeds [a]; [a] is held.
    - [Buy_quantity q]: buy exactly [q] shares; their estimated cost, rounded up, is held.
    - [Sell_quantity q]: sell exactly [q] shares.
    - [Sell_amount a]: sell shares worth about [a]: [a / price] rounded down.
    - [Sell_all]: sell every share not already reserved by another sell.

    Amounts are in the instrument's currency. *)

open! Core

type t =
  | Buy_amount of Money.Amount.t
  | Buy_quantity of Quantity.t
  | Sell_quantity of Quantity.t
  | Sell_amount of Money.Amount.t
  | Sell_all
[@@deriving sexp, compare, equal]

(** [Buy] for the two buy sizings, [Sell] otherwise. *)
val side : t -> Side.t

(** ["amount"], ["quantity"] or ["all"]: how the order is sized. *)
val sizing : t -> string

(** Builds a request from its wire parts: a side, a sizing (["amount"], ["quantity"],
    ["all"]) and the one value that sizing needs. Fails on an unknown sizing, a missing or
    extra value, and [all] on a buy. *)
val of_parts
  :  side:Side.t
  -> sizing:string
  -> ?amount:Money.Amount.t
  -> ?quantity:Quantity.t
  -> unit
  -> t Or_error.t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
