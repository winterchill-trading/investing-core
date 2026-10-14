(** International Securities Identification Numbers (ISO 6166), e.g. [US0378331005].

    Twelve characters: a two-letter country prefix, nine alphanumeric characters and a
    check digit, computed by the Luhn algorithm over the code with letters expanded to two
    digits (A = 10 ... Z = 35). Input is upper-cased first. *)

open! Core

type t [@@deriving sexp, compare, equal, hash]

include Stringable.S with type t := t

(** Fails on a wrong length, alphabet, prefix or check digit. *)
val of_string_or_error : string -> t Or_error.t

(** The two-letter prefix, e.g. ["US"]. *)
val country_prefix : t -> string

(** [check_digit body] is the digit that completes the eleven-character [body]. Fails when
    [body] is not eleven characters from [A-Z 0-9]. *)
val check_digit : string -> char Or_error.t

module Stable : sig
  module V1 : sig
    (** The twelve characters; decoding validates them again. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
  end
end
