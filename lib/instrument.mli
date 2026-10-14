(** A tradable security and its listing: what a customer picks when placing an order.

    The symbol identifies the instrument in this library (one listing per symbol; list a
    security twice under two symbols to trade it on two exchanges). The ISIN, when known,
    identifies the security itself across listings. *)

open! Core

module Kind : sig
  type t =
    | Stock
    | Etf (** exchange-traded fund *)
    | Fund (** a fund dealt at its net asset value rather than on an exchange *)
  [@@deriving sexp, compare, equal, enumerate, quickcheck]

  (** ["stock"], ["etf"], ["fund"]. *)
  val to_string : t -> string

  (** Accepts [to_string] output, ignoring case. *)
  val of_string_or_error : string -> t Or_error.t

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

type t = private
  { symbol : Symbol.t
  ; name : string
  ; kind : Kind.t
  ; isin : Isin.t option
  ; category : string (** free grouping such as [technology] or [broad-market] *)
  ; description : string
  ; listing : Listing.t
  }
[@@deriving sexp, compare, equal]

(** Fails on an empty name (after trimming) or a name longer than 200 characters. *)
val create
  :  symbol:Symbol.t
  -> name:string
  -> kind:Kind.t
  -> ?isin:Isin.t
  -> ?category:string (** default [""] *)
  -> ?description:string (** default [""] *)
  -> Listing.t
  -> t Or_error.t

(** The listing's trading currency. *)
val currency : t -> Money.Currency.t

(** The same instrument with another listing status (a halt, a delisting). *)
val with_status : t -> Listing.Status.t -> t

(** Case-insensitive substring match of [query] against the symbol, the name and the
    category. The empty query matches everything. *)
val matches : t -> query:string -> bool

module Stable : sig
  module V1 : sig
    (** Decoding validates the record again. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
