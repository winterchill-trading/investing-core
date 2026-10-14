(** A customer's positions valued at the latest closes, in one currency.

    Positions in another currency are left out and named in [other_currencies] (convert
    them with an FX library and summarise per currency). A position whose instrument has
    no usable close is valued at nothing, counted in [cost_basis], and named in
    [unpriced], so a missing price never hides money. Flat positions are kept only for
    their realised result. *)

open! Core

module Holding : sig
  type t =
    { position : Position.t
    ; quote : Price_history.Quote.t option
    ; valuation : Position.Valuation.t option
    ; day_change : Money.Amount.t option
    (** [quantity * (close - previous close)], rounded half-even *)
    }
  [@@deriving sexp_of]
end

type t =
  { currency : Money.Currency.t
  ; value : Money.Amount.t
  ; cost_basis : Money.Amount.t
  ; unrealised : Money.Amount.t (** of the priced holdings only *)
  ; realised : Money.Amount.t
  ; day_change : Money.Amount.t
  ; holdings : Holding.t list (** non-flat positions, sorted by symbol *)
  ; unpriced : Symbol.t list
  ; other_currencies : Symbol.t list
  }
[@@deriving sexp_of]

(** Values [positions] in [currency] at the latest usable closes on [today]. *)
val summarize
  :  ?staleness:Staleness.t
  -> Money.Currency.t
  -> positions:Position.t list
  -> prices:Price_history.t
  -> today:Date.t
  -> t
