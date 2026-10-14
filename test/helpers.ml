open! Core
open Investing_core
module Amount = Money.Amount

let usd s = Amount.of_string (s ^ " USD")
let sym = Symbol.of_string
let date = Date.of_string
let today = date "2026-10-07"
let t0 = Time_ns.of_string_with_utc_offset "2026-10-07 21:00:00Z"
let customer = Ledger.Account_id.of_string "customer:1/usd"
let bank = Ledger.Account_id.of_string "bank:central/usd"
let chart = Booking.Chart.default

let instrument ?(symbol = "ACME") ?(status = Listing.Status.Active) () =
  Instrument.create
    ~symbol:(sym symbol)
    ~name:"Acme Corp"
    ~kind:Stock
    ~category:"industrials"
    (Listing.create ~exchange:"XNAS" ~currency:Money.Currency.usd ~status ()
     |> Or_error.ok_exn)
  |> Or_error.ok_exn
;;

let prices =
  Price_history.of_list
    [ { symbol = sym "ACME"; date = date "2026-10-06"; close = Price.of_string "40"; origin = Feed }
    ; { symbol = sym "ACME"; date = today; close = Price.of_string "41.5"; origin = Feed }
    ]
;;

(** Balances with the customer's cash account, a bank account, the chart's accounts and
    [deposit] paid in. *)
let ledger ?(deposit = usd "1000.00") () =
  let accounts =
    Ledger.Account.create ~purpose:Customer_funds customer Liability
    :: Ledger.Account.create ~allow_negative:true bank Asset
    :: Booking.Chart.accounts chart ~currencies:[ Money.Currency.usd ]
  in
  let b =
    List.fold accounts ~init:Ledger.Balances.empty ~f:(fun b a ->
      Ledger.Balances.apply b { seq = Ledger.Balances.next_seq b; event = Account_opened a }
      |> Or_error.ok_exn)
  in
  let entry =
    Ledger.Entry.create
      ~idempotency_key:(Ledger.Idempotency_key.of_string "deposit-1")
      ~kind:(Transfer "deposit")
      ~code:Deposit
      ~effective_at:t0
      ~recorded_at:t0
      [ Ledger.Posting.debit bank deposit; Ledger.Posting.credit customer deposit ]
    |> Or_error.ok_exn
  in
  Booking.apply b [ entry ] |> Or_error.ok_exn
;;

let book b entries = Booking.apply b (Or_error.ok_exn entries) |> Or_error.ok_exn

let show_balances b =
  let cur = Money.Currency.usd in
  let line name id f = printf "  %-20s %s\n" name (Amount.to_string (f b id cur)) in
  line "available" customer Ledger.Balances.available;
  line "held" customer Ledger.Balances.held;
  line "brokerage clearing" (chart.brokerage_settlement cur) Ledger.Balances.balance
;;

let show_entries entries =
  List.iter (Or_error.ok_exn entries) ~f:(fun (e : Ledger.Entry.t) ->
    printf
      "  %s %s\n"
      (Ledger.Idempotency_key.to_string e.idempotency_key)
      (Sexp.to_string [%sexp (e.kind : Ledger.Entry.Kind.t)]);
    List.iter e.postings ~f:(fun p ->
      printf
        "    %s %-28s %s\n"
        (match p.side with
         | Debit -> "Dr"
         | Credit -> "Cr")
        (Ledger.Account_id.to_string p.account)
        (Amount.to_string p.amount)))
;;

let plan ?(position = None) ?(instrument = instrument ()) request =
  Placement.plan ~instrument ~prices ~today ~position request
;;

let order ?(id = "o-1") ?position request =
  let plan = plan ?position request |> Result.ok |> Option.value_exn in
  Order.create
    ~id:(Order_id.of_string id)
    ~account:customer
    ~symbol:(sym "ACME")
    ~request
    ~plan
    ~at:t0
;;

let apply_exn o e =
  match Order.apply o e with
  | Ok o -> o
  | Error r -> raise_s [%message "refused" (r : Order.Refusal.t)]
;;

let at_sec s = Time_ns.add t0 (Time_ns.Span.of_int_sec s)
