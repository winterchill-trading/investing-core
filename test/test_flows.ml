open! Core
open Async_kernel
open Investing_core
open Helpers

let%expect_test "buy by amount: hold, fill at a higher price with spread, settle" =
  let b = ledger () in
  let o = order (Buy_amount (usd "100.00")) in
  let b = book b (Booking.buy_placed b o ~at:t0) in
  show_balances b;
  let time_source = Time_source.create ~now:t0 () in
  let broker =
    Sim_broker.create
      ~config:{ Sim_broker.Config.default with spread_bps = 10 }
      ~time_source
      ~reference_price:(fun symbol ~at ->
        Price_history.latest
          prices
          symbol
          ~on_or_before:(Time_ns.to_date at ~zone:Time_float.Zone.utc))
      ()
  in
  let ack =
    Sim_broker.place broker (Broker.Request.of_order o ~at:t0)
    |> Deferred.peek
    |> Option.value_exn
    |> Or_error.ok_exn
  in
  let o = apply_exn o (Sent { at = t0 }) in
  let o = apply_exn o (Acknowledged { broker_ref = ack.broker_ref; at = t0 }) in
  print_s [%sexp (Order.cancellable o : (unit, Order.Refusal.t) Result.t)];
  Time_source.advance_directly time_source ~to_:(at_sec 3);
  Sim_broker.emit_due broker;
  print_s [%sexp (Pipe.length (Sim_broker.events broker) : int)];
  Time_source.advance_directly time_source ~to_:(at_sec 4);
  Sim_broker.emit_due broker;
  let event = Pipe.read_now' (Sim_broker.events broker) in
  let event =
    match event with
    | `Ok q -> Queue.to_list q |> List.hd_exn
    | `Eof | `Nothing_available -> assert false
  in
  print_s [%sexp (event : Broker.Event.t)];
  let after = apply_exn o (Broker.Event.to_order_event event o |> Or_error.ok_exn) in
  print_s [%sexp (after.status : Order.Status.t)];
  let entries = Booking.transition chart b ~before:o ~after ~at:(at_sec 4) in
  show_entries entries;
  let b = book b entries in
  show_balances b;
  [%expect
    {|
      available            900.00 USD
      held                 100.00 USD
      brokerage clearing   0.00 USD
    (Ok ())
    0
    (Filled (event_id sim-ad5a5baaef7323b92a04:1)
     (broker_ref sim-ad5a5baaef7323b92a04) (order_id o-1) (quantity 2.409638)
     (price 41.5415) (price_date (2026-10-07)) (at "2026-10-07 21:00:04Z"))
    (Filled
     ((quantity 2.409638) (price 41.5415) (price_date (2026-10-07))
      (gross "100.10 USD") (at "2026-10-07 21:00:04Z")))
      order:o-1:settlement (Hold_over_capture(hold order:o-1)(reason"fill cost above the hold"))
        Dr customer:1/usd/pending       100.00 USD
        Dr customer:1/usd               0.10 USD
        Cr clearing:brokerage/USD       100.10 USD
      available            899.90 USD
      held                 0.00 USD
      brokerage clearing   -100.10 USD
    |}]
;;

let%expect_test "a fill below the estimate returns the rest of the hold; cancel and \
                 reject release it"
  =
  let b = ledger () in
  let o = order ~id:"o-2" (Buy_quantity (Quantity.of_string "2")) in
  let b = book b (Booking.buy_placed b o ~at:t0) in
  let sent = apply_exn o (Sent { at = t0 }) in
  let filled =
    apply_exn
      sent
      (Filled { price = Price.of_string "41"; price_date = None; at = at_sec 1 })
  in
  let entries = Booking.transition chart b ~before:sent ~after:filled ~at:(at_sec 1) in
  show_entries entries;
  let b = book b entries in
  show_balances b;
  (* a cancel of an unsent order, then a broker rejection of a sent one *)
  let o3 = order ~id:"o-3" (Buy_amount (usd "50.00")) in
  let b = book b (Booking.buy_placed b o3 ~at:(at_sec 2)) in
  let cancelled = apply_exn o3 (Cancelled { at = at_sec 3 }) in
  let b =
    book b (Booking.transition chart b ~before:o3 ~after:cancelled ~at:(at_sec 3))
  in
  let o4 = order ~id:"o-4" (Buy_amount (usd "50.00")) in
  let b = book b (Booking.buy_placed b o4 ~at:(at_sec 4)) in
  let o4 = apply_exn o4 (Sent { at = at_sec 4 }) in
  let rejected = apply_exn o4 (Rejected { reason = "no_price"; at = at_sec 5 }) in
  let entries = Booking.transition chart b ~before:o4 ~after:rejected ~at:(at_sec 5) in
  show_entries entries;
  let b = book b entries in
  show_balances b;
  [%expect
    {|
    order:o-2:settlement (Hold_capture order:o-2)
      Dr customer:1/usd/pending       83.00 USD
      Cr customer:1/usd               1.00 USD
      Cr clearing:brokerage/USD       82.00 USD
    available            918.00 USD
    held                 0.00 USD
    brokerage clearing   -82.00 USD
    order:o-4:release (Hold_release order:o-4)
      Dr customer:1/usd/pending       50.00 USD
      Cr customer:1/usd               50.00 USD
    available            918.00 USD
    held                 0.00 USD
    brokerage clearing   -82.00 USD
    |}]
;;

let%expect_test "a fill the account cannot cover is refused by the ledger" =
  let b = ledger ~deposit:(usd "100.00") () in
  let o = order (Buy_amount (usd "100.00")) |> fun o -> apply_exn o (Sent { at = t0 }) in
  let b = book b (Booking.buy_placed b o ~at:t0) in
  let filled =
    apply_exn
      o
      (Filled { price = Price.of_string "45"; price_date = None; at = at_sec 1 })
  in
  print_s
    [%sexp
      (Booking.transition chart b ~before:o ~after:filled ~at:(at_sec 1)
       |> Or_error.map ~f:List.length
       : int Or_error.t)];
  [%expect
    {|
    (Error
     ("entry would take an account below zero" (id customer:1/usd)
      (balance_after "-8.44 USD") (idempotency_key order:o-1:settlement)))
    |}]
;;

let%expect_test "sell: proceeds credited, nothing booked on reject" =
  let b = ledger () in
  let position =
    Position.buy
      (Position.empty (sym "ACME") Money.Currency.usd)
      ~quantity:(Quantity.of_string "3")
      ~cost:(usd "120.00")
    |> Or_error.ok_exn
  in
  let o =
    order ~id:"s-1" ~position:(Some position) (Sell_quantity (Quantity.of_string "1"))
  in
  let position = Position.reserve position o.quantity |> Or_error.ok_exn in
  let o = apply_exn o (Sent { at = t0 }) in
  let filled =
    apply_exn
      o
      (Filled { price = Price.of_string "41.333"; price_date = None; at = at_sec 1 })
  in
  let entries = Booking.transition chart b ~before:o ~after:filled ~at:(at_sec 1) in
  show_entries entries;
  let b = book b entries in
  show_balances b;
  let fill =
    match filled.status with
    | Filled f -> f
    | _ -> assert false
  in
  let position, sale =
    Position.sell position ~quantity:fill.quantity ~proceeds:fill.gross |> Or_error.ok_exn
  in
  print_s [%sexp (sale : Position.Sale.t), (position : Position.t)];
  let o2 = order ~id:"s-2" ~position:(Some position) Sell_all in
  let rejected =
    apply_exn o2 (Rejected { reason = "rejected_by_broker"; at = at_sec 2 })
  in
  show_entries (Booking.transition chart b ~before:o2 ~after:rejected ~at:(at_sec 2));
  [%expect
    {|
      order:s-1:proceeds (Transfer trade_proceeds)
        Dr clearing:brokerage/USD       41.33 USD
        Cr customer:1/usd               41.33 USD
      available            1041.33 USD
      held                 0.00 USD
      brokerage clearing   41.33 USD
    (((cost_removed "40.00 USD") (realised "1.33 USD"))
     ((symbol ACME) (quantity 2) (reserved 0) (cost_basis "80.00 USD")
      (realised "1.33 USD")))
    |}]
;;
