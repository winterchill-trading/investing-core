open! Core
module Amount = Money.Amount

module Holding = struct
  type t =
    { position : Position.t
    ; quote : Price_history.Quote.t option
    ; valuation : Position.Valuation.t option
    ; day_change : Amount.t option
    }
  [@@deriving sexp_of]
end

type t =
  { currency : Money.Currency.t
  ; value : Amount.t
  ; cost_basis : Amount.t
  ; unrealised : Amount.t
  ; realised : Amount.t
  ; day_change : Amount.t
  ; holdings : Holding.t list
  ; unpriced : Symbol.t list
  ; other_currencies : Symbol.t list
  }
[@@deriving sexp_of]

let summarize ?staleness currency ~positions ~prices ~today =
  let mine, others =
    List.partition_tf positions ~f:(fun p ->
      Money.Currency.equal (Position.currency p) currency)
  in
  let mine = List.sort mine ~compare:(fun (a : Position.t) b -> Symbol.compare a.symbol b.symbol) in
  let holdings =
    List.filter_map mine ~f:(fun (position : Position.t) ->
      if Position.is_flat position
      then None
      else (
        let quote = Price_history.quote ?staleness prices position.symbol ~today |> Result.ok in
        let valuation =
          Option.map quote ~f:(fun q -> Position.value_at position (Price_history.Quote.price q))
        in
        let day_change =
          Option.bind quote ~f:(fun q ->
            Option.map (Price_history.Quote.change q) ~f:(fun per_share ->
              Amount.of_q
                ~rounding:Half_even
                currency
                (Q.mul per_share (Quantity.to_q position.quantity))))
        in
        Some { Holding.position; quote; valuation; day_change }))
  in
  let zero = Amount.zero currency in
  let sum f = List.fold ~init:zero ~f:(fun acc x -> Amount.add_exn acc (f x)) in
  let priced = List.filter_map holdings ~f:(fun h -> Option.map h.valuation ~f:(fun v -> h, v)) in
  { currency
  ; value = sum (fun (_, (v : Position.Valuation.t)) -> v.value) priced
  ; cost_basis = sum (fun (h : Holding.t) -> h.position.cost_basis) holdings
  ; unrealised = sum (fun (_, (v : Position.Valuation.t)) -> v.unrealised) priced
  ; realised = sum (fun (p : Position.t) -> p.realised) mine
  ; day_change = sum (fun (h : Holding.t) -> Option.value h.day_change ~default:zero) holdings
  ; holdings
  ; unpriced =
      List.filter_map holdings ~f:(fun h ->
        Option.some_if (Option.is_none h.valuation) h.position.symbol)
  ; other_currencies = List.map others ~f:(fun p -> p.symbol)
  }
;;
