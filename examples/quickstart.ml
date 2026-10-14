(* A buy by amount from price to position: simulated closes, a plan, a ledger hold, a
   simulated fill with a spread, the settlement entry, the position and a portfolio
   summary. Everything is in memory and deterministic. *)

open! Core
open Async_kernel
open Investing_core
module Amount = Money.Amount

let ok = Or_error.ok_exn
let usd = Money.Currency.usd
let today = Date.of_string "2026-10-07"
let now = Time_ns.of_string_with_utc_offset "2026-10-07 21:00:00Z"

(* The results of these calls are already determined: the simulated source and broker
   answer synchronously, so the example needs no Async scheduler. *)
let get d = Option.value_exn (Deferred.peek d) |> ok

let () =
  (* 1. An instrument and thirty days of simulated closes. *)
  let symbol = Symbol.of_string "ACME" in
  let instrument =
    Instrument.create
      ~symbol
      ~name:"Acme Corp"
      ~kind:Stock
      ~isin:(Isin.of_string "US0378331005")
      (Listing.create ~exchange:"XNAS" ~currency:usd () |> ok)
    |> ok
  in
  let source =
    Market_data.Simulated.create
      ~anchor_date:today
      ~start_prices:[ symbol, Price.of_string "41.50" ]
      ()
    |> ok
  in
  let closes =
    Market_data.Simulated.closes
      source
      ~symbols:[ symbol ]
      ~from:(Date.add_days today (-30))
      ~to_:today
    |> get
  in
  let prices = Price_history.of_list closes in
  (* 2. Plan a 250.00 USD buy: shares rounded down, the amount held. *)
  let request = Order_request.Buy_amount (Amount.of_string "250.00 USD") in
  let plan =
    match Placement.plan ~instrument ~prices ~today ~position:None request with
    | Ok plan -> plan
    | Error refusal -> raise_s [%sexp (refusal : Placement.Refusal.t)]
  in
  printf
    "plan: buy %s %s at %s, hold %s\n"
    (Quantity.to_string plan.quantity)
    (Symbol.to_string symbol)
    (Price.to_string (Price_history.Quote.price plan.quote))
    (Amount.to_string (Option.value_exn plan.hold));
  (* 3. The customer's ledger account with 1,000.00 USD, and the hold. *)
  let customer = Ledger.Account_id.of_string "customer:42/usd" in
  let bank = Ledger.Account_id.of_string "bank:omnibus/usd" in
  let chart = Booking.Chart.default in
  let balances =
    List.fold
      (Ledger.Account.create ~purpose:Customer_funds customer Liability
       :: Ledger.Account.create ~allow_negative:true bank Asset
       :: Booking.Chart.accounts chart ~currencies:[ usd ])
      ~init:Ledger.Balances.empty
      ~f:(fun b account ->
        Ledger.Balances.apply
          b
          { seq = Ledger.Balances.next_seq b; event = Account_opened account }
        |> ok)
  in
  let deposit = Amount.of_string "1000.00 USD" in
  let balances =
    Booking.apply
      balances
      [ Ledger.Entry.create
          ~idempotency_key:(Ledger.Idempotency_key.of_string "deposit-1")
          ~kind:(Transfer "deposit")
          ~effective_at:now
          ~recorded_at:now
          [ Ledger.Posting.debit bank deposit; Ledger.Posting.credit customer deposit ]
        |> ok
      ]
    |> ok
  in
  let order =
    Order.create
      ~id:(Order_id.of_string "ord-1")
      ~account:customer
      ~symbol
      ~request
      ~plan
      ~at:now
  in
  let balances =
    Booking.apply balances (Booking.buy_placed balances order ~at:now |> ok) |> ok
  in
  printf
    "after hold: available %s, held %s\n"
    (Amount.to_string (Ledger.Balances.available balances customer usd))
    (Amount.to_string (Ledger.Balances.held balances customer usd));
  (* 4. A simulated broker with a 5 bps spread and a 4-second delay. *)
  let time_source = Time_source.create ~now () in
  let broker =
    Sim_broker.create
      ~config:{ Sim_broker.Config.default with spread_bps = 5 }
      ~time_source
      ~reference_price:(fun symbol ~at:_ -> Price_history.latest prices symbol)
      ()
  in
  let ack = Sim_broker.place broker (Broker.Request.of_order order ~at:now) |> get in
  let order = Order.apply order (Sent { at = now }) |> Result.ok |> Option.value_exn in
  let order =
    Order.apply order (Acknowledged { broker_ref = ack.broker_ref; at = now })
    |> Result.ok
    |> Option.value_exn
  in
  let later = Time_ns.add now (Time_ns.Span.of_int_sec 4) in
  Time_source.advance_directly time_source ~to_:later;
  Sim_broker.emit_due broker;
  let event =
    match Pipe.read_now (Sim_broker.events broker) with
    | `Ok event -> event
    | `Eof | `Nothing_available -> failwith "no fill"
  in
  let filled =
    Order.apply order (Broker.Event.to_order_event event order |> ok)
    |> Result.ok
    |> Option.value_exn
  in
  let fill =
    match filled.status with
    | Filled fill -> fill
    | Pending | Rejected _ | Cancelled _ -> failwith "not filled"
  in
  printf
    "fill: %s at %s, cost %s\n"
    (Quantity.to_string fill.quantity)
    (Price.to_string fill.price)
    (Amount.to_string fill.gross);
  (* 5. Settle the cash leg and update the position. *)
  let entries =
    Booking.transition chart balances ~before:order ~after:filled ~at:later |> ok
  in
  let balances = Booking.apply balances entries |> ok in
  printf
    "after fill: available %s, held %s, owed to broker %s\n"
    (Amount.to_string (Ledger.Balances.available balances customer usd))
    (Amount.to_string (Ledger.Balances.held balances customer usd))
    (Amount.to_string
       (Amount.neg
          (Ledger.Balances.balance balances (chart.brokerage_settlement usd) usd)));
  let position =
    Position.buy (Position.empty symbol usd) ~quantity:fill.quantity ~cost:fill.gross
    |> ok
  in
  let summary = Portfolio.summarize usd ~positions:[ position ] ~prices ~today in
  printf
    "portfolio: value %s, cost %s, unrealised %s, average cost %s\n"
    (Amount.to_string summary.value)
    (Amount.to_string summary.cost_basis)
    (Amount.to_string summary.unrealised)
    (Price.to_string (Option.value_exn (Position.average_cost position)))
;;
