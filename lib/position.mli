(** A customer's holding of one instrument, with its average cost basis.

    - [quantity] is every share held; [reserved] is the part promised to pending sells, so
      [available = quantity - reserved] is what a new sell may use.
    - [cost_basis] is what the shares held cost in total (in the instrument's currency). A
      buy adds its cost; a sell removes the sold fraction of it, so the average cost per
      share does not change on a sale. Selling everything removes all of it, so no minor
      unit is ever left behind on an empty position.
    - [realised] accumulates proceeds minus the cost removed, over the position's life.

    Values are immutable; every change returns a new position or an error, and none of
    them can make a quantity or the cost basis negative. *)

open! Core

type t = private
  { symbol : Symbol.t
  ; quantity : Quantity.t
  ; reserved : Quantity.t
  ; cost_basis : Money.Amount.t
  ; realised : Money.Amount.t
  }
[@@deriving sexp, compare, equal]

(** No shares, in [currency]. *)
val empty : Symbol.t -> Money.Currency.t -> t

(** The instrument currency of the cost basis and results. *)
val currency : t -> Money.Currency.t

(** [quantity - reserved]. *)
val available : t -> Quantity.t

(** No shares held. *)
val is_flat : t -> bool

(** Promises [q] shares to a pending sell. Fails when fewer than [q] are available. *)
val reserve : t -> Quantity.t -> t Or_error.t

(** Gives back a reservation (the sell was rejected or cancelled). Fails when fewer than
    [q] are reserved. *)
val release : t -> Quantity.t -> t Or_error.t

(** Adds [quantity] shares that cost [cost] in total. Fails on another currency or a
    negative cost. *)
val buy : t -> quantity:Quantity.t -> cost:Money.Amount.t -> t Or_error.t

(** What a sale did to the position. *)
module Sale : sig
  type t =
    { cost_removed : Money.Amount.t (** the sold shares' share of the cost basis *)
    ; realised : Money.Amount.t (** [proceeds - cost_removed]; negative for a loss *)
    }
  [@@deriving sexp, compare, equal]
end

(** Removes [quantity] shares sold for [proceeds]. With [~from_reserved:true] (the
    default) the shares come out of the reservation the sell made when it was placed. The
    cost removed is [cost_basis * quantity / held], rounded half-even, or the whole basis
    when every share is sold. Fails on another currency, negative proceeds, or more shares
    than held (or reserved). *)
val sell
  :  ?from_reserved:bool
  -> t
  -> quantity:Quantity.t
  -> proceeds:Money.Amount.t
  -> (t * Sale.t) Or_error.t

(** [cost_basis / quantity], rounded half-even to eight places; [None] when flat. *)
val average_cost : t -> Price.t option

(** A position valued at a price. *)
module Valuation : sig
  type t =
    { value : Money.Amount.t (** [quantity * price], rounded half-even *)
    ; unrealised : Money.Amount.t (** [value - cost_basis] *)
    ; unrealised_ratio : Q.t option (** [unrealised / cost_basis]; [None] at zero cost *)
    }
  [@@deriving sexp_of]
end

(** The position valued at [price]. *)
val value_at : t -> Price.t -> Valuation.t

module Stable : sig
  module V1 : sig
    (** Decoding checks the invariants again. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
