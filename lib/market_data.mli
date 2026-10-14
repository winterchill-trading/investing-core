(** Sources of end-of-day closes.

    A service fetches closes periodically from a {!S} and adds them to its
    {!Price_history}. Two implementations ship here: {!Simulated}, a deterministic random
    walk for demos and tests, and {!Fixed}, which serves closes it was given (seed data,
    fixtures). An HTTP fetcher for a real data vendor implements {!S} in the service that
    owns the credentials. *)

open! Core
open Async_kernel

module type S = sig
  type t

  (** Short identifier for logs and the [origin] shown with prices, e.g. ["simulated"]. *)
  val name : t -> string

  (** Attribution text a data licence asks to show next to its prices. *)
  val attribution : t -> string

  (** Closes of [symbols] dated in [[from, to_]], in any order. A symbol the source does
      not know yields no closes rather than an error, so one unknown symbol does not stop
      a batch. *)
  val closes
    :  t
    -> symbols:Symbol.t list
    -> from:Date.t
    -> to_:Date.t
    -> Close.t list Deferred.Or_error.t
end

(** A deterministic random walk, one per symbol, on weekdays only.

    Each weekday's close is the previous weekday's close moved by a step of at most
    [daily_bps] basis points either way. The step is derived from an MD5 hash of the seed,
    the symbol and the date, so the same configuration produces the same prices on every
    machine and for every query range. The walk is anchored at [anchor_date] with the
    symbol's starting price and runs in both directions from there. *)
module Simulated : sig
  type t

  (** [start_prices] gives each known symbol its price on [anchor_date] (a weekend anchor
      is moved to the Friday before). Closes are [Simulated] origin unless [origin] says
      otherwise. *)
  val create
    :  ?seed:int (** default [0] *)
    -> ?daily_bps:int (** default [150]; at most [2_000] *)
    -> ?decimals:int
         (** default [2]: closes are published rounded half-even to this many places,
             while the walk itself keeps eight *)
    -> ?origin:Close.Origin.t
    -> anchor_date:Date.t
    -> start_prices:(Symbol.t * Price.t) list
    -> unit
    -> t Or_error.t

  (** The close of [symbol] on [date]; [None] on a weekend or for an unknown symbol. *)
  val close : t -> Symbol.t -> Date.t -> Close.t option

  include S with type t := t
end

(** Serves the closes of a {!Price_history} it was created with. *)
module Fixed : sig
  type t

  val create : ?name:string (** default ["fixed"] *) -> Price_history.t -> t

  include S with type t := t
end
