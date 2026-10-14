open! Core
module Amount = Money.Amount
module Account_id = Ledger.Account_id

module Chart = struct
  type t = { brokerage_settlement : Money.Currency.t -> Account_id.t }

  let default =
    { brokerage_settlement =
        (fun currency ->
          (* Currency text forms ("USD", "USDC@polygon") only use ledger id characters. *)
          Account_id.of_string ("clearing:brokerage/" ^ Money.Currency.to_string currency))
    }
  ;;

  let accounts t ~currencies =
    List.map currencies ~f:(fun currency ->
      Ledger.Account.create
        ~purpose:Clearing
        ~allow_negative:true
        (t.brokerage_settlement currency)
        Asset)
    |> List.dedup_and_sort ~compare:(fun (a : Ledger.Account.t) b ->
      Account_id.compare a.id b.id)
  ;;
end

let hold_id id = Ledger.Hold_id.of_string_or_error ("order:" ^ Order_id.to_string id)

let idempotency_key id ~leg =
  Ledger.Idempotency_key.of_string_or_error
    (sprintf "order:%s:%s" (Order_id.to_string id) leg)
;;

let apply balances entries =
  List.fold_result entries ~init:balances ~f:(fun b (entry : Ledger.Entry.t) ->
    Ledger.Balances.apply b { seq = Ledger.Balances.next_seq b; event = Posted entry })
;;

(* Entries are returned only once they apply cleanly, so a caller never appends an entry
   the journal would refuse for a reason visible now. *)
let checked balances entries =
  let open Or_error.Let_syntax in
  let%bind entries in
  let%map (_ : Ledger.Balances.t) = apply balances entries in
  entries
;;

let reference (order : Order.t) = Order_id.to_string order.id

let buy_placed balances (order : Order.t) ~at =
  let open Or_error.Let_syntax in
  checked balances
  @@
  match Order.side order, order.estimate.hold with
  | Sell, _ ->
    Or_error.error_s [%message "a sell places no hold" ~order:(order.id : Order_id.t)]
  | Buy, None ->
    Or_error.error_s [%message "buy without a hold" ~order:(order.id : Order_id.t)]
  | Buy, Some amount ->
    let%bind hold_id = hold_id order.id in
    let%bind idempotency_key = idempotency_key order.id ~leg:"hold" in
    let%map entry =
      Ledger.Hold.place
        balances
        ~hold_id
        ~account:order.account
        ~amount
        ~idempotency_key
        ~reference:(reference order)
        ~effective_at:order.created_at
        ~recorded_at:at
        ()
    in
    [ entry ]
;;

let buy_filled (chart : Chart.t) balances (order : Order.t) (fill : Order.Fill.t) ~at =
  let open Or_error.Let_syntax in
  let%bind hold_id = hold_id order.id in
  let%bind idempotency_key = idempotency_key order.id ~leg:"settlement" in
  let%bind hold =
    Option.value_map
      order.estimate.hold
      ~default:(Or_error.error_string "buy without a hold")
      ~f:Or_error.return
  in
  let to_ = chart.brokerage_settlement (Order.currency order) in
  let%map entry =
    if Amount.( <= ) fill.gross hold
    then
      Ledger.Hold.capture
        balances
        ~hold_id
        ~amount:fill.gross
        ~release_remainder:true
        ~to_
        ~idempotency_key
        ~reference:(reference order)
        ~effective_at:fill.at
        ~recorded_at:at
        ()
    else
      Ledger.Hold.over_capture
        balances
        ~hold_id
        ~amount:fill.gross
        ~reason:"fill cost above the hold"
        ~to_
        ~idempotency_key
        ~reference:(reference order)
        ~effective_at:fill.at
        ~recorded_at:at
        ()
  in
  [ entry ]
;;

let buy_released balances (order : Order.t) ~effective_at ~at =
  let open Or_error.Let_syntax in
  let%bind hold_id = hold_id order.id in
  let%bind idempotency_key = idempotency_key order.id ~leg:"release" in
  let%map entry =
    Ledger.Hold.release
      balances
      ~hold_id
      ~idempotency_key
      ~reference:(reference order)
      ~effective_at
      ~recorded_at:at
      ()
  in
  [ entry ]
;;

let sell_filled (chart : Chart.t) (order : Order.t) (fill : Order.Fill.t) ~at =
  let open Or_error.Let_syntax in
  if Amount.is_zero fill.gross
  then Ok []
  else (
    let%bind idempotency_key = idempotency_key order.id ~leg:"proceeds" in
    let%map entry =
      Ledger.Entry.create
        ~idempotency_key
        ~kind:(Transfer "trade_proceeds")
        ~reference:(reference order)
        ~effective_at:fill.at
        ~recorded_at:at
        [ Ledger.Posting.debit
            (chart.brokerage_settlement (Order.currency order))
            fill.gross
        ; Ledger.Posting.credit order.account fill.gross
        ]
    in
    [ entry ])
;;

let transition chart balances ~(before : Order.t) ~(after : Order.t) ~at =
  checked balances
  @@
  match before.status, after.status, Order.side after with
  | Pending, Filled fill, Buy -> buy_filled chart balances after fill ~at
  | Pending, Filled fill, Sell -> sell_filled chart after fill ~at
  | Pending, (Rejected { at = effective_at; _ } | Cancelled { at = effective_at }), Buy ->
    buy_released balances after ~effective_at ~at
  | Pending, (Rejected _ | Cancelled _), Sell -> Ok []
  | Pending, Pending, _ -> Ok []
  | (Filled _ | Rejected _ | Cancelled _), _, _ ->
    Or_error.error_s
      [%message
        "order was already final"
          ~order:(after.id : Order_id.t)
          ~status:(Order.Status.name before.status)]
;;
