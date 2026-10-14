open! Core
open Investing_core
open Helpers

let show request ?position ?instrument () =
  match plan ?position ?instrument request with
  | Error r ->
    printf "refused %s: %s\n" (Placement.Refusal.code r) (Sexp.to_string [%sexp (r : Placement.Refusal.t)])
  | Ok (p : Placement.Plan.t) ->
    printf
      "%s %s at %s, gross %s, hold %s, reserve %s\n"
      (Side.to_string p.side)
      (Quantity.to_string p.quantity)
      (Price.to_string (Price_history.Quote.price p.quote))
      (Amount.to_string p.estimated_gross)
      (Option.value_map p.hold ~default:"-" ~f:Amount.to_string)
      (Option.value_map p.reserve ~default:"-" ~f:Quantity.to_string)
;;

let held quantity cost reserved =
  let p =
    Position.buy
      (Position.empty (sym "ACME") Money.Currency.usd)
      ~quantity:(Quantity.of_string quantity)
      ~cost:(usd cost)
    |> Or_error.ok_exn
  in
  Some (Position.reserve p (Quantity.of_string reserved) |> Or_error.ok_exn)
;;

let%expect_test "buys" =
  show (Buy_amount (usd "100.00")) ();
  show (Buy_quantity (Quantity.of_string "2.5")) ();
  show (Buy_amount (usd "0.99")) ();
  show (Buy_amount (usd "1000000.01")) ();
  show (Buy_quantity (Quantity.of_string "0")) ();
  show (Buy_amount (Amount.of_string "100.00 EUR")) ();
  show (Buy_amount (usd "100.00")) ~instrument:(instrument ~status:Halted ()) ();
  show (Buy_amount (usd "100.00")) ~instrument:(instrument ~symbol:"NOPX" ()) ();
  [%expect
    {|
    buy 2.409638 at 41.5, gross 100.00 USD, hold 100.00 USD, reserve -
    buy 2.5 at 41.5, gross 103.75 USD, hold 103.75 USD, reserve -
    refused below_minimum: (Below_minimum(minimum"1.00 USD"))
    refused above_maximum: (Above_maximum(maximum"1000000.00 USD"))
    refused not_positive: Not_positive
    refused currency_mismatch: (Currency_mismatch(expected USD)(got EUR))
    refused not_tradable: (Not_tradable(symbol ACME)(status Halted))
    refused price_unavailable: (Price_unavailable(No_price(symbol NOPX)))
    |}]
;;

let%expect_test "sells" =
  show (Sell_quantity (Quantity.of_string "1")) ~position:(held "3" "120.00" "0") ();
  show (Sell_amount (usd "50.00")) ~position:(held "3" "120.00" "0") ();
  show Sell_all ~position:(held "3" "120.00" "1") ();
  show (Sell_quantity (Quantity.of_string "2.5")) ~position:(held "3" "120.00" "1") ();
  show Sell_all ~position:(held "3" "120.00" "3") ();
  show Sell_all ~position:None ();
  (* the whole of a small position may be sold below the minimum, a part may not *)
  show Sell_all ~position:(held "0.01" "0.40" "0") ();
  show (Sell_quantity (Quantity.of_string "0.01")) ~position:(held "0.02" "0.80" "0") ();
  [%expect
    {|
    sell 1 at 41.5, gross 41.50 USD, hold -, reserve 1
    sell 1.204819 at 41.5, gross 49.99 USD, hold -, reserve 1.204819
    sell 2 at 41.5, gross 83.00 USD, hold -, reserve 2
    refused exceeds_holdings: (Exceeds_holdings(available 2))
    refused holdings_reserved: (Holdings_reserved(symbol ACME))
    refused no_holdings: (No_holdings(symbol ACME))
    sell 0.01 at 41.5, gross 0.41 USD, hold -, reserve 0.01
    refused below_minimum: (Below_minimum(minimum"1.00 USD"))
    |}]
;;

let%expect_test "stale and old prices" =
  let check today =
    match
      Placement.plan
        ~instrument:(instrument ())
        ~prices
        ~today:(date today)
        ~position:None
        (Buy_amount (usd "10.00"))
    with
    | Ok p -> printf "%s: ok, %s\n" today (Sexp.to_string [%sexp (p.quote.verdict : Staleness.Verdict.t)])
    | Error r -> printf "%s: %s\n" today (Placement.Refusal.code r)
  in
  List.iter [ "2026-10-12"; "2026-10-18" ] ~f:check;
  [%expect
    {|
    2026-10-12: ok, (Stale(age_days 5))
    2026-10-18: price_too_old
    |}]
;;

let%expect_test "a buy's hold always covers its estimated cost" =
  Quickcheck.test
    (Quickcheck.Generator.union
       [ Int.gen_incl 100 100_000_000
         |> Quickcheck.Generator.map ~f:(fun c ->
           Order_request.Buy_amount (Amount.of_minor_units_int Money.Currency.usd c))
       ; Int.gen_incl 1 10_000_000_000
         |> Quickcheck.Generator.map ~f:(fun m ->
           Order_request.Buy_quantity (Quantity.of_micro m |> Or_error.ok_exn))
       ])
    ~sexp_of:[%sexp_of: Order_request.t]
    ~f:(fun request ->
      match plan request with
      | Error (Below_minimum _ | Above_maximum _) -> ()
      | Error r -> raise_s [%sexp (r : Placement.Refusal.t)]
      | Ok p ->
        let hold = Option.value_exn p.hold in
        assert (Amount.( <= ) p.estimated_gross hold);
        assert (Quantity.is_positive p.quantity))
;;
