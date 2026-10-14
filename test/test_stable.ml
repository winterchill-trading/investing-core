open! Core
open Investing_core
open Helpers

(* A changed digest means old bytes no longer decode: add a Stable.V2 instead of editing
   V1, and keep V1 readable. *)
let%expect_test "stable bin_prot digests" =
  List.iter
    [ "Symbol", [%bin_digest: Symbol.Stable.V1.t]
    ; "Isin", [%bin_digest: Isin.Stable.V1.t]
    ; "Quantity", [%bin_digest: Quantity.Stable.V1.t]
    ; "Price", [%bin_digest: Price.Stable.V1.t]
    ; "Listing", [%bin_digest: Listing.Stable.V1.t]
    ; "Instrument", [%bin_digest: Instrument.Stable.V1.t]
    ; "Close", [%bin_digest: Close.Stable.V1.t]
    ; "Side", [%bin_digest: Side.Stable.V1.t]
    ; "Order_id", [%bin_digest: Order_id.Stable.V1.t]
    ; "Order_request", [%bin_digest: Order_request.Stable.V1.t]
    ; "Order_limits", [%bin_digest: Order_limits.Stable.V1.t]
    ; "Order", [%bin_digest: Order.Stable.V1.t]
    ; "Position", [%bin_digest: Position.Stable.V1.t]
    ; "Recurring_buy", [%bin_digest: Recurring_buy.Stable.V1.t]
    ]
    ~f:(fun (name, digest) -> printf "%-14s %s\n" name digest);
  [%expect {|
    Symbol         d9a8da25d5656b016fb4dbdc2e4197fb
    Isin           d9a8da25d5656b016fb4dbdc2e4197fb
    Quantity       698cfa4093fe5e51523842d37b92aeac
    Price          698cfa4093fe5e51523842d37b92aeac
    Listing        1515c9de6cdf04e0a59724c9ced01cb1
    Instrument     1053622c2b1dbd6d87e8b14a6f5bda41
    Close          7f51265a92fe45376e9f6e4ae1db0aee
    Side           201e24d8d0d9507c88320f4f72b73cda
    Order_id       d9a8da25d5656b016fb4dbdc2e4197fb
    Order_request  45959ec6384ebb46fe8679706d145cce
    Order_limits   693c605174bb6ea96fd4b1b553663fa8
    Order          473b42d6cf199c145dedcbdea851ab97
    Position       dd2a2fed4d6f475d1988bc57df98178b
    Recurring_buy  dbc85858a26119d064e0debb51359bfb
    |}]
;;

let round_trip (type a) (module M : Binable.S with type t = a) ~sexp_of ~of_sexp ~equal (v : a) =
  let back = Binable.of_string (module M) (Binable.to_string (module M) v) in
  assert (equal back v);
  assert (equal (of_sexp (sexp_of v)) v)
;;

let%expect_test "records round trip through bin_prot and sexp" =
  let o = order (Buy_amount (usd "100.00")) in
  let o = apply_exn o (Sent { at = t0 }) in
  let o = apply_exn o (Filled { price = Price.of_string "41.6"; price_date = Some today; at = at_sec 4 }) in
  round_trip
    (module Order.Stable.V1)
    ~sexp_of:Order.Stable.V1.sexp_of_t
    ~of_sexp:Order.Stable.V1.t_of_sexp
    ~equal:Order.equal
    o;
  let i = instrument () in
  round_trip
    (module Instrument.Stable.V1)
    ~sexp_of:Instrument.Stable.V1.sexp_of_t
    ~of_sexp:Instrument.Stable.V1.t_of_sexp
    ~equal:Instrument.equal
    i;
  let p =
    Position.buy (Position.empty (sym "ACME") Money.Currency.usd) ~quantity:(Quantity.of_string "1.25") ~cost:(usd "50.00")
    |> Or_error.ok_exn
  in
  round_trip
    (module Position.Stable.V1)
    ~sexp_of:Position.Stable.V1.sexp_of_t
    ~of_sexp:Position.Stable.V1.t_of_sexp
    ~equal:Position.equal
    p;
  print_s [%sexp (o : Order.t)];
  [%expect {|
    ((id o-1) (account customer:1/usd) (symbol ACME)
     (request (Buy_amount "100.00 USD")) (quantity 2.409638)
     (estimate
      ((price 41.5) (price_date 2026-10-07) (gross "100.00 USD")
       (hold ("100.00 USD"))))
     (submission (Sent (at "2026-10-07 21:00:00Z")))
     (status
      (Filled
       ((quantity 2.409638) (price 41.6) (price_date (2026-10-07))
        (gross "100.25 USD") (at "2026-10-07 21:00:04Z"))))
     (created_at "2026-10-07 21:00:00Z"))
    |}]
;;

let%expect_test "decoding re-checks invariants" =
  let bad = Sexp.of_string "((symbol ACME)(quantity 1)(reserved 2)(cost_basis \"1.00 USD\")(realised \"0.00 USD\"))" in
  print_s [%sexp (Or_error.try_with (fun () -> Position.Stable.V1.t_of_sexp bad) : Position.t Or_error.t)];
  print_s
    [%sexp
      (Or_error.try_with (fun () ->
         Binable.of_string (module Quantity.Stable.V1) (Binable.to_string (module Int) (-5)))
       : Quantity.t Or_error.t)];
  [%expect {|
    (Error
     ("more reserved than held"
      (position
       ((symbol ACME) (quantity 1) (reserved 2) (cost_basis "1.00 USD")
        (realised "0.00 USD")))))
    (Error ("negative quantity" (micro -5)))
    |}]
;;
