(** Where an instrument trades: the exchange, the trading currency and whether orders are
    accepted.

    The exchange is a market identifier code (ISO 10383 MIC) such as [XNAS] or [XETR],
    four characters from [A-Z 0-9]. Prices, order values and cash legs of a listing are
    all in its currency. *)

open! Core

module Status : sig
  type t =
    | Active (** orders accepted *)
    | Halted (** trading suspended for now: new orders refused, positions kept *)
    | Delisted (** no longer traded: new orders refused *)
  [@@deriving sexp, compare, equal, enumerate, quickcheck]

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

type t = private
  { exchange : string (** MIC, e.g. [XNYS] *)
  ; currency : Money.Currency.t
  ; status : Status.t
  }
[@@deriving sexp, compare, equal]

(** Fails unless [exchange] is four characters from [A-Z 0-9]. *)
val create
  :  exchange:string
  -> currency:Money.Currency.t
  -> ?status:Status.t (** default [Active] *)
  -> unit
  -> t Or_error.t

(** The same listing with another status. *)
val with_status : t -> Status.t -> t

(** Whether new orders are accepted ([Active] only). *)
val accepts_orders : t -> bool

module Stable : sig
  module V1 : sig
    (** Decoding validates the exchange code again. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
