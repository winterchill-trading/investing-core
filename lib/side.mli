(** Whether an order buys or sells. *)

open! Core

type t =
  | Buy
  | Sell
[@@deriving sexp, compare, equal, hash, enumerate, quickcheck]

(** ["buy"], ["sell"]. *)
val to_string : t -> string

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal, hash]
  end
end
