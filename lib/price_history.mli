(** End-of-day closes for many instruments: the reference prices orders are estimated and
    simulated fills are priced at.

    For each symbol and date one close is kept, the {!Close.preferred} one, so loading
    seed data after a feed's closes does not overwrite them. An immutable value. *)

open! Core

type t [@@deriving sexp_of]

val empty : t

(** Adds or replaces (by preference) the close for its symbol and date. *)
val add : t -> Close.t -> t

(** [List.fold ~init:t ~f:add]. *)
val add_all : t -> Close.t list -> t

val of_list : Close.t list -> t

(** Symbols with at least one close, sorted. *)
val symbols : t -> Symbol.t list

(** The latest close of [symbol] dated on or before [on_or_before] (default: the latest of
    all). *)
val latest : ?on_or_before:Date.t -> t -> Symbol.t -> Close.t option

(** The latest close strictly before [date]: the previous close to measure a day's change
    against. *)
val before : t -> Symbol.t -> Date.t -> Close.t option

(** The close of [symbol] on exactly [date]. *)
val on : t -> Symbol.t -> Date.t -> Close.t option

(** Closes of [symbol] dated in [[until - days + 1, until]], oldest first. Fails unless
    [days >= 1]. *)
val window : t -> Symbol.t -> until:Date.t -> days:int -> Close.t list Or_error.t

(** Lowest and highest close in {!window}; [None] when it is empty. *)
val low_high : t -> Symbol.t -> until:Date.t -> days:int -> (Price.t * Price.t) option

(** The price to estimate an order with today, if one may be used.

    - [Error (No_price)]: there is no close on or before [today];
    - [Error (Too_old)]: the latest close is past the staleness refusal limit;
    - [Ok quote] otherwise, with the previous close for the day's change and whether the
      price is stale. *)
module Quote : sig
  type t =
    { close : Close.t
    ; previous : Close.t option
    ; verdict : Staleness.Verdict.t (** [Fresh] or [Stale] *)
    }
  [@@deriving sexp_of]

  val price : t -> Price.t

  (** [close - previous] as an exact rational in the instrument's currency per share. *)
  val change : t -> Q.t option

  (** [(close - previous) / previous], e.g. [1/50] for +2 %. *)
  val change_ratio : t -> Q.t option
end

module Unavailable : sig
  type t =
    | No_price of { symbol : Symbol.t }
    | Too_old of
        { symbol : Symbol.t
        ; date : Date.t
        ; age_days : int
        }
  [@@deriving sexp, compare, equal]
end

val quote
  :  ?staleness:Staleness.t (** default {!Staleness.default} *)
  -> t
  -> Symbol.t
  -> today:Date.t
  -> (Quote.t, Unavailable.t) Result.t
