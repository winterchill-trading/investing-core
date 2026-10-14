(** One end-of-day closing price of one instrument. *)

open! Core

(** Where a close came from. When two closes exist for the same symbol and date, the one
    with the higher {!Origin.rank} wins: a close from a market-data feed replaces seed
    data bundled with the application, which replaces a simulated close. *)
module Origin : sig
  type t =
    | Feed (** fetched from a market-data source *)
    | Seed (** reference data loaded at startup *)
    | Simulated (** generated, e.g. by {!Market_data.Simulated} *)
  [@@deriving sexp, compare, equal, enumerate, quickcheck]

  (** [Feed] 3, [Seed] 2, [Simulated] 1. *)
  val rank : t -> int

  (** ["feed"], ["seed"], ["simulated"]. *)
  val to_string : t -> string

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

type t =
  { symbol : Symbol.t
  ; date : Date.t
  ; close : Price.t
  ; origin : Origin.t
  }
[@@deriving sexp, compare, equal, quickcheck]

(** [preferred a b] is the one to keep for the same symbol and date: the higher origin
    rank, and [b] (the newer) on a tie. *)
val preferred : t -> t -> t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
