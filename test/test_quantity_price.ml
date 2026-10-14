open! Core
open Investing_core

let usd = Money.Currency.usd
let jpy = Money.Currency.jpy

let show_result to_string r =
  match r with
  | Ok v -> print_endline (to_string v)
  | Error e -> print_s [%sexp (e : Error.t)]
;;

let%expect_test "quantity parsing keeps six places and refuses more" =
  List.iter
    [ "1"
    ; "0.5"
    ; "12.345678"
    ; "12.3456780"
    ; "12.3456781"
    ; "-1"
    ; "1e3"
    ; ""
    ; "."
    ; "007.10"
    ]
    ~f:(fun s -> show_result Quantity.to_string (Quantity.of_string_or_error s));
  [%expect
    {|
    1
    0.5
    12.345678
    12.345678
    ("more than six decimal places" (quantity 12.3456781))
    ("malformed quantity" (quantity -1))
    ("malformed quantity" (quantity 1e3))
    ("empty quantity" (quantity ""))
    ("empty quantity" (quantity .))
    7.1
    |}]
;;

let%expect_test "price parsing" =
  List.iter [ "187.45"; "0.00000001"; "0"; "-1"; "1.000000001" ] ~f:(fun s ->
    show_result Price.to_string (Price.of_string_or_error s));
  [%expect
    {|
    187.45
    0.00000001
    ("price must be positive" (units 0))
    ("price must be positive" (units -100000000))
    (price
     ("Fixed_decimal.of_string_exact: more than 8 fractional digits" 1.000000001
      (dropped 1)))
    |}]
;;

let%expect_test "gross rounds by direction" =
  let p = Price.of_string "187.4567" in
  let q = Quantity.of_string "0.333333" in
  printf
    "cost %s, proceeds %s, yen cost %s\n"
    (Money.Amount.to_string (Price.gross p q ~currency:usd ~rounding:Up))
    (Money.Amount.to_string (Price.gross p q ~currency:usd ~rounding:Down))
    (Money.Amount.to_string (Price.gross p q ~currency:jpy ~rounding:Up));
  [%expect {| cost 62.49 USD, proceeds 62.48 USD, yen cost 63 JPY |}];
  let shares =
    Price.quantity_for p (Money.Amount.of_string "100.00 USD") ~rounding:Down
    |> Or_error.ok_exn
  in
  printf
    "100.00 USD buys %s shares costing %s\n"
    (Quantity.to_string shares)
    (Money.Amount.to_string (Price.gross p shares ~currency:usd ~rounding:Up));
  [%expect {| 100.00 USD buys 0.533456 shares costing 100.00 USD |}]
;;

let%expect_test "spread adjustment" =
  let p = Price.of_string "100" in
  List.iter [ 25; -25; 0 ] ~f:(fun bps ->
    show_result Price.to_string (Price.adjust_bps p ~bps ~rounding:Up));
  [%expect {|
    100.25
    99.75
    100
    |}]
;;

let%expect_test "shares bought for an amount never cost more than the amount" =
  Quickcheck.test
    (Quickcheck.Generator.tuple2
       (* a cent or more: ten million dollars at a millionth of a cent is more shares than
          a quantity can hold *)
       (Price.quickcheck_generator
        |> Quickcheck.Generator.filter ~f:(fun p -> Price.to_units p >= 1_000_000))
       (* up to ten million dollars, the range orders are limited to *)
       (Int.gen_incl 0 1_000_000_000
        |> Quickcheck.Generator.map ~f:(Money.Amount.of_minor_units_int usd)))
    ~f:(fun (p, amount) ->
      let q = Price.quantity_for p amount ~rounding:Down |> Or_error.ok_exn in
      let cost = Price.gross p q ~currency:usd ~rounding:Up in
      assert (Money.Amount.( <= ) cost amount);
      (* one more millionth of a share would cost more than the amount *)
      let more = Quantity.add q (Quantity.of_micro 1 |> Or_error.ok_exn) in
      assert (
        Q.( > ) (Q.mul (Price.to_q p) (Quantity.to_q more)) (Money.Amount.to_q amount)))
;;

let%expect_test "quantity and price round trip" =
  Quickcheck.test Quantity.quickcheck_generator ~f:(fun q ->
    [%test_result: Quantity.t] ~expect:q (Quantity.of_string (Quantity.to_string q));
    [%test_result: Quantity.t]
      ~expect:q
      (Binable.of_string
         (module Quantity.Stable.V1)
         (Binable.to_string (module Quantity.Stable.V1) q)));
  Quickcheck.test Price.quickcheck_generator ~f:(fun p ->
    [%test_result: Price.t] ~expect:p (Price.of_string (Price.to_string p));
    [%test_result: Price.t] ~expect:p (Price.t_of_sexp (Price.sexp_of_t p)))
;;
