open! Core
open Investing_core
open Helpers

let show_apply o e =
  match Order.apply o e with
  | Ok o ->
    printf
      "ok: %s, %s\n"
      (Order.Status.name o.status)
      (Sexp.to_string [%sexp (o.submission : Order.Submission.t)]);
    o
  | Error r ->
    printf "refused: %s\n" (Order.Refusal.code r);
    o
;;

let%expect_test "submission and cancel rules" =
  let o = order (Buy_amount (usd "10.00")) in
  let o = show_apply o (Acknowledged { broker_ref = "b-1"; at = t0 }) in
  let o = show_apply o (Filled { price = Price.of_string "1"; price_date = None; at = t0 }) in
  let o = show_apply o (Sent { at = t0 }) in
  print_s [%sexp (Order.cancellable o : (unit, Order.Refusal.t) Result.t)];
  let o = show_apply o (Cancelled { at = t0 }) in
  let o = show_apply o (Acknowledged { broker_ref = "b-1"; at = t0 }) in
  let o = show_apply o (Acknowledged { broker_ref = "b-1"; at = t0 }) in
  let o = show_apply o (Acknowledged { broker_ref = "b-2"; at = t0 }) in
  let o = show_apply o (Cancelled { at = at_sec 1 }) in
  let o = show_apply o (Rejected { reason = "late"; at = at_sec 2 }) in
  print_s [%sexp (Order.closed_at o : Time_ns.Alternate_sexp.t option)];
  [%expect
    {|
    refused: not_sent_yet
    refused: not_sent_yet
    ok: pending, (Sent(at"2026-10-07 21:00:00Z"))
    (Error In_transit)
    refused: in_transit
    ok: pending, (Acknowledged(broker_ref b-1)(at"2026-10-07 21:00:00Z"))
    ok: pending, (Acknowledged(broker_ref b-1)(at"2026-10-07 21:00:00Z"))
    refused: already_acknowledged
    ok: cancelled, (Acknowledged(broker_ref b-1)(at"2026-10-07 21:00:00Z"))
    refused: already_cancelled
    ("2026-10-07 21:00:01Z")
    |}]
;;

let gen_event =
  let open Quickcheck.Generator.Let_syntax in
  let%bind s = Int.gen_incl 0 100 in
  let at = at_sec s in
  Quickcheck.Generator.of_list
    [ Order.Event.Sent { at }
    ; Acknowledged { broker_ref = "b-1"; at }
    ; Acknowledged { broker_ref = "b-2"; at }
    ; Filled { price = Price.of_string "42"; price_date = None; at }
    ; Rejected { reason = "r"; at }
    ; Cancelled { at }
    ]
;;

let%expect_test "random event streams: final is final, fills are whole, cancels never in transit" =
  let seen = String.Hash_set.create () in
  Quickcheck.test
    (List.gen_with_length 8 gen_event)
    ~sexp_of:[%sexp_of: Order.Event.t list]
    ~f:(fun events ->
      let start = order (Buy_quantity (Quantity.of_string "1.5")) in
      ignore
        (List.fold events ~init:start ~f:(fun o e ->
           match Order.apply o e with
           | Error _ -> o
           | Ok o' ->
             Hash_set.add seen (Order.Status.name o'.status);
             if Order.Status.is_final o.status then assert (Order.equal o o');
             (match o'.status, o.submission, e with
              | Cancelled _, Sent _, _ -> assert false
              | Filled f, _, _ ->
                assert (Quantity.equal f.quantity o.quantity);
                (* buy costs round up: 1.5 x 42 = 63.00 exactly *)
                assert (Money.Amount.equal f.gross (usd "63.00"))
              | _ -> ());
             assert (Bool.equal (Order.Status.is_final o'.status) (Option.is_some (Order.closed_at o')));
             o')
         : Order.t));
  print_s [%sexp (Hash_set.to_list seen |> List.sort ~compare:String.compare : string list)];
  [%expect {| (cancelled filled pending rejected) |}]
;;
