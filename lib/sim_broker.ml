open! Core
open Async_kernel

module Config = struct
  type t =
    { fill_delay : Time_ns.Span.t option
    ; spread_bps : int
    ; outcome : [ `Fill | `Reject ]
    }
  [@@deriving sexp, compare, equal]

  let default =
    { fill_delay = Some (Time_ns.Span.of_sec 4.); spread_bps = 0; outcome = `Fill }
  ;;
end

module Order_state = struct
  type t =
    | Open of { due_at : Time_ns.Alternate_sexp.t option }
    | Filled
    | Rejected
    | Cancelled
  [@@deriving sexp, compare, equal]
end

type order =
  { broker_ref : string
  ; request : Broker.Request.t
  ; placed_seq : int
  ; config : Config.t (** as it was when the order was placed *)
  ; mutable state : Order_state.t
  }

type t =
  { display_name : string
  ; time_source : read Time_source.T1.t
  ; reference_price : Symbol.t -> at:Time_ns.t -> Close.t option
  ; mutable config : Config.t
  ; by_ref : order String.Table.t
  ; by_key : string String.Table.t
  ; mutable next_seq : int
  ; mutable next_event : int
  ; events_r : Broker.Event.t Pipe.Reader.t
  ; events_w : Broker.Event.t Pipe.Writer.t
  }

let create
  ?(config = Config.default)
  ?(display_name = "Simulated broker")
  ~time_source
  ~reference_price
  ()
  =
  let events_r, events_w = Pipe.create () in
  { display_name
  ; time_source = Time_source.read_only time_source
  ; reference_price
  ; config
  ; by_ref = String.Table.create ()
  ; by_key = String.Table.create ()
  ; next_seq = 0
  ; next_event = 0
  ; events_r
  ; events_w
  }
;;

let name _ = "simulated"
let display_name t = t.display_name
let config t = t.config
let set_config t config = t.config <- config
let now t = Time_source.now t.time_source

(* Derived from the key so the same request always gets the same reference, even from a
   fresh broker value. *)
let broker_ref_of_key key = "sim-" ^ String.prefix (Md5.to_hex (Md5.digest_string key)) 20

let place t (request : Broker.Request.t) =
  let broker_ref =
    match Hashtbl.find t.by_key request.idempotency_key with
    | Some broker_ref -> broker_ref
    | None ->
      let broker_ref = broker_ref_of_key request.idempotency_key in
      let due_at = Option.map t.config.fill_delay ~f:(fun d -> Time_ns.add (now t) d) in
      Hashtbl.set t.by_key ~key:request.idempotency_key ~data:broker_ref;
      Hashtbl.set
        t.by_ref
        ~key:broker_ref
        ~data:
          { broker_ref
          ; request
          ; placed_seq = t.next_seq
          ; config = t.config
          ; state = Open { due_at }
          };
      t.next_seq <- t.next_seq + 1;
      broker_ref
  in
  Deferred.Or_error.return { Broker.Ack.broker_ref }
;;

let find t ~idempotency_key =
  Deferred.Or_error.return
    (Hashtbl.find t.by_key idempotency_key
     |> Option.map ~f:(fun broker_ref -> { Broker.Ack.broker_ref }))
;;

let events t = t.events_r

let next_event_id t (o : order) =
  t.next_event <- t.next_event + 1;
  sprintf "%s:%d" o.broker_ref t.next_event
;;

let reject t (o : order) ~reason =
  o.state <- Rejected;
  Pipe.write_without_pushback_if_open
    t.events_w
    (Rejected
       { event_id = next_event_id t o
       ; broker_ref = o.broker_ref
       ; order_id = o.request.order_id
       ; reason
       ; at = now t
       })
;;

let fill t (o : order) =
  let at = now t in
  match t.reference_price o.request.symbol ~at with
  | None -> reject t o ~reason:"no_price"
  | Some close ->
    let bps =
      match o.request.side with
      | Buy -> o.config.spread_bps
      | Sell -> -o.config.spread_bps
    in
    let rounding : Money.Rounding.t =
      match o.request.side with
      | Buy -> Up
      | Sell -> Down
    in
    (match Price.adjust_bps close.close ~bps ~rounding with
     | Error _ -> reject t o ~reason:"no_price"
     | Ok price ->
       o.state <- Filled;
       Pipe.write_without_pushback_if_open
         t.events_w
         (Filled
            { event_id = next_event_id t o
            ; broker_ref = o.broker_ref
            ; order_id = o.request.order_id
            ; quantity = o.request.quantity
            ; price
            ; price_date = Some close.date
            ; at
            }))
;;

let decide t (o : order) =
  match o.config.outcome with
  | `Fill -> fill t o
  | `Reject -> reject t o ~reason:"rejected_by_broker"
;;

let emit_due t =
  let now = now t in
  Hashtbl.data t.by_ref
  |> List.filter ~f:(fun o ->
    match o.state with
    | Open { due_at = Some due } -> Time_ns.( <= ) due now
    | Open { due_at = None } | Filled | Rejected | Cancelled -> false)
  |> List.sort ~compare:(fun a b -> Int.compare a.placed_seq b.placed_seq)
  |> List.iter ~f:(decide t)
;;

let open_order t ~broker_ref =
  match Hashtbl.find t.by_ref broker_ref with
  | None -> Or_error.error_s [%message "unknown broker reference" broker_ref]
  | Some ({ state = Open _; _ } as o) -> Ok o
  | Some o ->
    Or_error.error_s
      [%message "order is not open" broker_ref ~state:(o.state : Order_state.t)]
;;

let fill_now t ~broker_ref = Or_error.map (open_order t ~broker_ref) ~f:(fill t)

let reject_now t ~broker_ref ~reason =
  Or_error.map (open_order t ~broker_ref) ~f:(reject t ~reason)
;;

let cancel t ~broker_ref =
  Deferred.return
    (match Hashtbl.find t.by_ref broker_ref with
     | None -> Or_error.error_s [%message "unknown broker reference" broker_ref]
     | Some ({ state = Open _; _ } as o) ->
       o.state <- Cancelled;
       Ok Broker.Cancel_result.Cancelled
     | Some { state = Cancelled; _ } -> Ok Broker.Cancel_result.Cancelled
     | Some { state = Filled | Rejected; _ } -> Ok Too_late)
;;

let start ?(every = Time_ns.Span.of_sec 1.) ?(stop = Deferred.never ()) t =
  Time_source.every ~stop t.time_source every (fun () -> emit_due t)
;;

let orders t =
  Hashtbl.data t.by_ref
  |> List.sort ~compare:(fun a b -> Int.compare a.placed_seq b.placed_seq)
  |> List.map ~f:(fun o -> o.broker_ref, o.request, o.state)
;;
