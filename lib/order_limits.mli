(** The smallest and largest order a brokerage accepts, by estimated value in the
    instrument's currency. A sale of a whole position is exempt from the minimum, so a
    small remainder can always be sold. *)

open! Core

type t = private
  { minimum : Money.Amount.t
  ; maximum : Money.Amount.t
  }
[@@deriving sexp, compare, equal]

(** Fails unless both are in one currency and [0 < minimum <= maximum]. *)
val create : minimum:Money.Amount.t -> maximum:Money.Amount.t -> t Or_error.t

(** 1 to 1,000,000 major units of [currency]. *)
val default : Money.Currency.t -> t

val currency : t -> Money.Currency.t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
