(** Share quantities with six decimal places: whole shares and fractions down to a
    millionth of a share.

    A quantity is never negative. It is stored as an immediate [int] count of millionths
    (micro-shares), so it never allocates and covers up to about 4.6 * 10^12 shares. The
    text form is the decimal value without trailing zeros: ["1"], ["0.5"], ["12.345678"].

    Conversions that can lose a digit name their rounding, because brokerage rounds by
    direction: a cash amount turns into a quantity rounded down (never buy more than was
    paid for), and fractional digits beyond the sixth are refused on input rather than
    cut. *)

open! Core

type t : immediate [@@deriving sexp, compare, equal, hash, quickcheck]

include Comparable.S with type t := t

(** 6. *)
val decimals : int

(** Nothing. *)
val zero : t

(** One whole share. *)
val one : t

val is_zero : t -> bool
val is_positive : t -> bool

(** [of_micro n] is [n] millionths of a share. Fails when [n] is negative. *)
val of_micro : int -> t Or_error.t

(** The number of millionths of a share. *)
val to_micro : t -> int

(** [of_int n] is [n] whole shares. Fails when [n] is negative or too large. *)
val of_int : int -> t Or_error.t

(** Parses ["12.5"], ["0.000001"], ["3"]. Refuses a sign, an exponent, a non-zero digit
    after the sixth fractional one, and values out of range. *)
val of_string_or_error : string -> t Or_error.t

(** [of_string_or_error] that raises. *)
val of_string : string -> t

(** Shortest decimal form: ["1"], ["0.5"], ["12.345678"]. *)
val to_string : t -> string

(** As a [Fixed_decimal] value of a type the caller chose (eight decimal places, so
    nothing is lost). *)
val to_fixed_decimal
  : ('a : immediate).
  (module Fixed_decimal.S with type t = 'a) -> t -> 'a

(** Fails when the value is negative or has a non-zero seventh or eighth decimal. *)
val of_fixed_decimal
  : ('a : immediate).
  (module Fixed_decimal.S with type t = 'a) -> 'a -> t Or_error.t

(** The exact rational number of shares. *)
val to_q : t -> Q.t

(** [of_q ~rounding q] rounds [q] shares to a millionth. Fails when the result is negative
    or out of range. *)
val of_q : rounding:Money.Rounding.t -> Q.t -> t Or_error.t

(** [add a b] is [a + b]. *)
val add : t -> t -> t

(** [sub a b] is [a - b]; fails when [b > a], since a quantity is never negative. *)
val sub : t -> t -> t Or_error.t

module Stable : sig
  module V1 : sig
    (** Bin_prot is the micro-share count as an [int]; decoding refuses a negative count. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
  end
end
