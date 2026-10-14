open! Core
open Investing_core
open Helpers

let position symbol currency quantity cost =
  Position.buy
    (Position.empty (sym symbol) currency)
    ~quantity:(Quantity.of_string quantity)
    ~cost:(Amount.of_string cost)
  |> Or_error.ok_exn
;;

let%expect_test "summary in one currency, naming unpriced and foreign holdings" =
  let flat =
    let p = position "OLD" Money.Currency.usd "1" "10.00 USD" in
    let p, _ =
      Position.sell
        ~from_reserved:false
        p
        ~quantity:(Quantity.of_string "1")
        ~proceeds:(usd "12.50")
      |> Or_error.ok_exn
    in
    p
  in
  let s =
    Portfolio.summarize
      Money.Currency.usd
      ~positions:
        [ position "ACME" Money.Currency.usd "2.5" "95.00 USD"
        ; position "NOPX" Money.Currency.usd "1" "20.00 USD"
        ; position "EURO" Money.Currency.eur "1" "20.00 EUR"
        ; flat
        ]
      ~prices
      ~today
  in
  printf
    "value %s, cost %s, unrealised %s, realised %s, day %s\nunpriced %s, other %s\n"
    (Amount.to_string s.value)
    (Amount.to_string s.cost_basis)
    (Amount.to_string s.unrealised)
    (Amount.to_string s.realised)
    (Amount.to_string s.day_change)
    (Sexp.to_string [%sexp (s.unpriced : Symbol.t list)])
    (Sexp.to_string [%sexp (s.other_currencies : Symbol.t list)]);
  [%expect
    {|
    value 103.75 USD, cost 115.00 USD, unrealised 8.75 USD, realised 2.50 USD, day 3.75 USD
    unpriced (NOPX), other (EURO)
    |}]
;;
