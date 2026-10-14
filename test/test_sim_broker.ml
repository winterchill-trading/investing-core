open! Core
open Async_kernel
open Investing_core
open Helpers

let get d = Deferred.peek d |> Option.value_exn |> Or_error.ok_exn

let drain broker =
  match Pipe.read_now' (Sim_broker.events broker) with
  | `Ok q ->
    Queue.iter q ~f:(fun e ->
      match (e : Broker.Event.t) with
      | Filled { event_id; order_id; price; _ } ->
        printf
          "filled %s %s at %s\n"
          event_id
          (Order_id.to_string order_id)
          (Price.to_string price)
      | Rejected { event_id; order_id; reason; _ } ->
        printf "rejected %s %s: %s\n" event_id (Order_id.to_string order_id) reason)
  | `Nothing_available -> print_endline "no events"
  | `Eof -> print_endline "eof"
;;

let request ?(symbol = "ACME") ?(side = Side.Sell) id =
  { Broker.Request.idempotency_key = "order:" ^ id
  ; order_id = Order_id.of_string id
  ; symbol = sym symbol
  ; side
  ; quantity = Quantity.of_string "1"
  ; requested_at = t0
  }
;;

let%expect_test "placing is idempotent; cancel, manual decisions and missing prices" =
  let time_source = Time_source.create ~now:t0 () in
  let broker =
    Sim_broker.create
      ~config:{ fill_delay = None; spread_bps = 50; outcome = `Fill }
      ~time_source
      ~reference_price:(fun symbol ~at:_ -> Price_history.latest prices symbol)
      ()
  in
  let a = get (Sim_broker.place broker (request "a")) in
  let a' = get (Sim_broker.place broker (request "a")) in
  print_s [%sexp (Broker.Ack.equal a a' : bool)];
  print_s
    [%sexp
      (get (Sim_broker.find broker ~idempotency_key:"order:a") : Broker.Ack.t option)];
  let b = get (Sim_broker.place broker (request "b")) in
  let c = get (Sim_broker.place broker (request ~symbol:"NOPX" "c")) in
  (* no delay: nothing happens until a manual decision *)
  Time_source.advance_directly time_source ~to_:(at_sec 3600);
  Sim_broker.emit_due broker;
  drain broker;
  print_s
    [%sexp
      (get (Sim_broker.cancel broker ~broker_ref:b.broker_ref) : Broker.Cancel_result.t)];
  Sim_broker.fill_now broker ~broker_ref:a.broker_ref |> Or_error.ok_exn;
  Sim_broker.fill_now broker ~broker_ref:c.broker_ref |> Or_error.ok_exn;
  drain broker;
  print_s
    [%sexp
      (get (Sim_broker.cancel broker ~broker_ref:a.broker_ref) : Broker.Cancel_result.t)];
  print_s [%sexp (Sim_broker.fill_now broker ~broker_ref:b.broker_ref : unit Or_error.t)];
  print_s
    [%sexp
      (List.map (Sim_broker.orders broker) ~f:(fun (_, r, s) -> r.order_id, s)
       : (Order_id.t * Sim_broker.Order_state.t) list)];
  [%expect
    {|
    true
    (((broker_ref sim-2ba763f7bce24fa0caf6)))
    no events
    Cancelled
    filled sim-2ba763f7bce24fa0caf6:1 a at 41.2925
    rejected sim-10ef269dfa0be1c8e097:2 c: no_price
    Too_late
    (Error ("order is not open" sim-76175c1c3a54ddfa5cc3 (state Cancelled)))
    ((a Filled) (b Cancelled) (c Rejected))
    |}]
;;

let%expect_test "due orders are decided in placement order once their delay passes" =
  let time_source = Time_source.create ~now:t0 () in
  let broker =
    Sim_broker.create
      ~time_source
      ~reference_price:(fun symbol ~at:_ -> Price_history.latest prices symbol)
      ()
  in
  ignore (get (Sim_broker.place broker (request ~side:Buy "x")) : Broker.Ack.t);
  Time_source.advance_directly time_source ~to_:(at_sec 2);
  ignore (get (Sim_broker.place broker (request ~side:Buy "y")) : Broker.Ack.t);
  Sim_broker.set_config broker { Sim_broker.Config.default with outcome = `Reject };
  ignore (get (Sim_broker.place broker (request ~side:Buy "z")) : Broker.Ack.t);
  Time_source.advance_directly time_source ~to_:(at_sec 5);
  Sim_broker.emit_due broker;
  drain broker;
  [%expect {| filled sim-5e08e8ac6b20a971c678:1 x at 41.5 |}];
  Time_source.advance_directly time_source ~to_:(at_sec 6);
  Sim_broker.emit_due broker;
  drain broker;
  [%expect
    {|
    filled sim-c2e9c3787957817ccde9:2 y at 41.5
    rejected sim-a6dbda003854c2c4faf4:3 z: rejected_by_broker
    |}]
;;
