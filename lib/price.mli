(** A positive price per share, in the instrument's currency, with up to eight decimal
    places (closing prices are usually quoted to two or four).

    The currency is not part of the value: an instrument's prices are all in its listing
    currency, and the functions that turn a price into money take that currency. Products
    of a price and a quantity are exact rationals rounded once, in a direction the caller
    names. *)

open! Core

type t : immediate [@@deriving sexp, compare, equal, hash, quickcheck]

include Comparable.S with type t := t

(** Parses ["187.45"]. Refuses zero, negative values, a non-zero digit after the eighth
    decimal and malformed input. *)
val of_string_or_error : string -> t Or_error.t

(** [of_string_or_error] that raises. *)
val of_string : string -> t

(** Shortest decimal form, e.g. ["187.45"]. *)
val to_string : t -> string

(** [of_units n] is [n * 10^-8]. Fails unless [n > 0]. *)
val of_units : int -> t Or_error.t

(** The number of [10^-8] units. *)
val to_units : t -> int

(** The exact rational value. *)
val to_q : t -> Q.t

(** [of_q ~rounding q] rounds to eight decimals. Fails unless the result is positive and
    in range. *)
val of_q : rounding:Money.Rounding.t -> Q.t -> t Or_error.t

(** [gross t quantity ~currency ~rounding] is [t * quantity] in [currency], rounded to a
    minor unit with [rounding]. A buy's cost rounds [Up] and a sale's proceeds round
    [Down], so rounding never favours the customer at the house's expense. *)
val gross
  :  t
  -> Quantity.t
  -> currency:Money.Currency.t
  -> rounding:Money.Rounding.t
  -> Money.Amount.t

(** [quantity_for t amount ~rounding] is the number of shares [amount] buys at [t],
    rounded to six places with [rounding] ([Down] when cash is turned into shares). Fails
    on a negative amount. *)
val quantity_for
  :  t
  -> Money.Amount.t
  -> rounding:Money.Rounding.t
  -> Quantity.t Or_error.t

(** [adjust_bps t ~bps ~rounding] is [t * (1 + bps / 10_000)]: a price moved by a spread,
    up for a positive [bps] and down for a negative one. Fails when the result is not
    positive. *)
val adjust_bps : t -> bps:int -> rounding:Money.Rounding.t -> t Or_error.t

(** [change ~from ~to_] is [(to_ - from) / from], the relative move as an exact rational. *)
val change : from:t -> to_:t -> Q.t

module Stable : sig
  module V1 : sig
    (** Bin_prot is the [10^-8] unit count as an [int]; decoding refuses values that are
        not positive. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
  end
end
