open! Core
open Investing_core

let show_result to_string r =
  match r with
  | Ok v -> print_endline (to_string v)
  | Error e -> print_s [%sexp (e : Error.t)]
;;

let%expect_test "symbols are upper-cased and checked" =
  List.iter [ "aapl"; "BRK.B"; "VWCE-DE"; ""; ".X"; "TOOLONGSYMBOL1"; "A B" ] ~f:(fun s ->
    show_result Symbol.to_string (Symbol.of_string_or_error s));
  [%expect
    {|
    AAPL
    BRK.B
    VWCE-DE
    "empty symbol"
    ("symbol must start with a letter or digit" (symbol .X))
    ("symbol too long" (symbol TOOLONGSYMBOL1) (max_length 12))
    ("invalid character in symbol" (symbol "A B") (c " "))
    |}]
;;

let%expect_test "ISIN check digits" =
  List.iter
    [ "US0378331005"
    ; "us0378331005"
    ; "DE000BAY0017"
    ; "IE00B4L5Y983"
    ; "US0378331006"
    ; "US037833100"
    ; "1S0378331005"
    ]
    ~f:(fun s -> show_result Isin.to_string (Isin.of_string_or_error s));
  [%expect
    {|
    US0378331005
    US0378331005
    DE000BAY0017
    IE00B4L5Y983
    ("ISIN check digit mismatch" (isin US0378331006) (expected 5))
    ("malformed ISIN" (isin US037833100))
    ("malformed ISIN" (isin 1S0378331005))
    |}]
;;

let%expect_test "symbols round trip through every form" =
  Quickcheck.test Symbol.quickcheck_generator ~f:(fun s ->
    [%test_result: Symbol.t] ~expect:s (Symbol.of_string (Symbol.to_string s));
    [%test_result: Symbol.t]
      ~expect:s
      (Binable.of_string
         (module Symbol.Stable.V1)
         (Binable.to_string (module Symbol.Stable.V1) s)))
;;
