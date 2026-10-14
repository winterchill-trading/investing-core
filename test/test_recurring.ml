open! Core
open Investing_core
open Helpers

let plan cadence start =
  Recurring_buy.create
    ~id:"plan-1"
    ~account:customer
    ~symbol:(sym "ACME")
    ~amount:(usd "25.00")
    ~cadence
    ~start:(date start)
    ()
  |> Or_error.ok_exn
;;

let%expect_test "monthly dates are counted from the start and clamp to month end" =
  let p = plan Monthly "2026-01-31" in
  print_s
    [%sexp
      (Recurring_buy.dates_between p ~from:(date "2026-01-01") ~until:(date "2026-06-30")
       : Date.t list)];
  print_s [%sexp (Recurring_buy.nth p 13 : Date.t)];
  [%expect
    {|
    (2026-01-31 2026-02-28 2026-03-31 2026-04-30 2026-05-31 2026-06-30)
    2027-02-28
    |}]
;;

let%expect_test "only the latest missed date runs, once" =
  let p = plan Weekly "2026-09-01" in
  let due today last_run =
    Recurring_buy.due p ~today:(date today) ~last_run:(Option.map last_run ~f:date)
  in
  let dues =
    [ due "2026-08-31" None
    ; due "2026-09-01" None
    ; due "2026-09-20" (Some "2026-09-01")
    ; due "2026-09-20" (Some "2026-09-15")
    ]
  in
  print_s [%sexp (dues : Date.t option list)];
  print_s [%sexp (Recurring_buy.order_id p ~date:(date "2026-09-15") : Order_id.t)];
  [%expect
    {|
    (() (2026-09-01) (2026-09-15) ())
    rb-plan-1-20260915
    |}]
;;

let%expect_test "three failures in a row pause the plan; resuming skips passed dates" =
  let p = plan Weekly "2026-09-01" in
  let p = Recurring_buy.failed p ~reason:"insufficient_funds" in
  let p = Recurring_buy.succeeded p in
  let p = Recurring_buy.failed p ~reason:"insufficient_funds" in
  let p = Recurring_buy.failed p ~reason:"insufficient_funds" in
  print_s [%sexp (p.status : Recurring_buy.Status.t), (p.consecutive_failures : int)];
  let p = Recurring_buy.failed p ~reason:"no_price" in
  print_s [%sexp (p.status : Recurring_buy.Status.t)];
  print_s [%sexp (Recurring_buy.due p ~today:(date "2026-09-08") ~last_run:None : Date.t option)];
  let p = Recurring_buy.resume p ~today:(date "2026-09-10") in
  print_s [%sexp (Recurring_buy.due p ~today:(date "2026-09-10") ~last_run:None : Date.t option)];
  print_s [%sexp (Recurring_buy.due p ~today:(date "2026-09-15") ~last_run:None : Date.t option)];
  [%expect
    {|
    (Active 2)
    (Paused (reason no_price))
    ()
    ()
    (2026-09-15)
    |}]
;;

let%expect_test "dates_between agrees with nth for every cadence" =
  Quickcheck.test
    (Quickcheck.Generator.tuple3
       (Quickcheck.Generator.of_list
          [ Recurring_buy.Cadence.Weekly; Monthly; Every_n_days 1; Every_n_days 10 ])
       (Int.gen_incl 0 1_000)
       (Int.gen_incl 0 400))
    ~sexp_of:[%sexp_of: Recurring_buy.Cadence.t * int * int]
    ~f:(fun (cadence, offset, span) ->
      let p = plan cadence "2024-01-31" in
      let from = Date.add_days (date "2024-01-01") offset in
      let until = Date.add_days from span in
      let expected =
        (* enough occurrences to pass the latest [until] at one a day *)
        List.init 1_500 ~f:(Recurring_buy.nth p)
        |> List.filter ~f:(fun d -> Date.between d ~low:from ~high:until)
      in
      [%test_result: Date.t list] ~expect:expected (Recurring_buy.dates_between p ~from ~until))
;;
