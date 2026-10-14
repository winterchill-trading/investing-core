(** Ticker symbols such as [AAPL], [BRK.B] or [VWCE-DE].

    A symbol is 1 to 12 characters from [A-Z 0-9 . -], starting with a letter or a digit.
    Input is upper-cased first, so ["aapl"] reads as [AAPL]. The alphabet is a subset of
    the ledger's id characters, so a symbol can appear inside ledger keys and references
    without escaping. *)

open! Core

type t [@@deriving quickcheck]

include Identifiable.S with type t := t

(** [of_string] raises on an invalid symbol; this is the non-raising form. *)
val of_string_or_error : string -> t Or_error.t

(** 12. *)
val max_length : int

module Stable : sig
  module V1 : sig
    (** Bin_prot is the plain string; decoding validates it again. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
  end
end
