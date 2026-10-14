open! Core

module Stable = struct
  module V1 = struct
    type t =
      | Buy_amount of Money.Amount.Stable.V1.t
      | Buy_quantity of Quantity.Stable.V1.t
      | Sell_quantity of Quantity.Stable.V1.t
      | Sell_amount of Money.Amount.Stable.V1.t
      | Sell_all
    [@@deriving bin_io, sexp, compare, equal]
  end
end

type t = Stable.V1.t =
  | Buy_amount of Money.Amount.t
  | Buy_quantity of Quantity.t
  | Sell_quantity of Quantity.t
  | Sell_amount of Money.Amount.t
  | Sell_all
[@@deriving sexp, compare, equal]

let side = function
  | Buy_amount _ | Buy_quantity _ -> Side.Buy
  | Sell_quantity _ | Sell_amount _ | Sell_all -> Sell
;;

let sizing = function
  | Buy_amount _ | Sell_amount _ -> "amount"
  | Buy_quantity _ | Sell_quantity _ -> "quantity"
  | Sell_all -> "all"
;;

let of_parts ~side ~sizing ?amount ?quantity () =
  let fail msg =
    Or_error.error_s [%message msg ~side:(side : Side.t) ~sizing:(sizing : string)]
  in
  match sizing, amount, quantity, (side : Side.t) with
  | "amount", Some a, None, Buy -> Ok (Buy_amount a)
  | "amount", Some a, None, Sell -> Ok (Sell_amount a)
  | "quantity", None, Some q, Buy -> Ok (Buy_quantity q)
  | "quantity", None, Some q, Sell -> Ok (Sell_quantity q)
  | "all", None, None, Sell -> Ok Sell_all
  | "all", _, _, Buy -> fail "only a sell can be sized as all"
  | ("amount" | "quantity" | "all"), _, _, _ -> fail "wrong values for this sizing"
  | _ -> fail "unknown sizing"
;;
