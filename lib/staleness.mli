(** How old an end-of-day price may be.

    Closes are published once a trading day, so a price is never current: over a weekend
    Friday's close is three days old and still the latest there is. A price older than
    [stale_after] days is shown with a warning; one older than [refuse_after] days is not
    used to price an order at all. Ages are calendar days between the close's date and
    today. *)

open! Core

type t = private
  { stale_after : int
  ; refuse_after : int
  }
[@@deriving sexp, compare, equal]

(** Fails unless [0 <= stale_after <= refuse_after]. *)
val create : stale_after:int -> refuse_after:int -> t Or_error.t

(** Stale after 4 days (covers a weekend plus a holiday), refused after 10. *)
val default : t

module Verdict : sig
  type t =
    | Fresh
    | Stale of { age_days : int } (** usable, but say how old it is *)
    | Too_old of { age_days : int } (** do not price orders with it *)
  [@@deriving sexp, compare, equal]
end

(** [classify t ~today ~date] judges a close dated [date]. A date after [today] counts as
    age 0. *)
val classify : t -> today:Date.t -> date:Date.t -> Verdict.t
