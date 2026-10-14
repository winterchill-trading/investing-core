open! Core
open Async_kernel

module Request = struct
  type t =
    { idempotency_key : string
    ; order_id : Order_id.t
    ; symbol : Symbol.t
    ; side : Side.t
    ; quantity : Quantity.t
    ; requested_at : Time_ns.Alternate_sexp.t
    }
  [@@deriving sexp, compare, equal]

  let of_order (order : Order.t) ~at =
    { idempotency_key = "order:" ^ Order_id.to_string order.id
    ; order_id = order.id
    ; symbol = order.symbol
    ; side = Order.side order
    ; quantity = order.quantity
    ; requested_at = at
    }
  ;;
end

module Ack = struct
  type t = { broker_ref : string } [@@deriving sexp, compare, equal]
end

module Event = struct
  type t =
    | Filled of
        { event_id : string
        ; broker_ref : string
        ; order_id : Order_id.t
        ; quantity : Quantity.t
        ; price : Price.t
        ; price_date : Date.t option
        ; at : Time_ns.Alternate_sexp.t
        }
    | Rejected of
        { event_id : string
        ; broker_ref : string
        ; order_id : Order_id.t
        ; reason : string
        ; at : Time_ns.Alternate_sexp.t
        }
  [@@deriving sexp, compare, equal]

  let event_id = function
    | Filled { event_id; _ } | Rejected { event_id; _ } -> event_id
  ;;

  let order_id = function
    | Filled { order_id; _ } | Rejected { order_id; _ } -> order_id
  ;;

  let to_order_event t (order : Order.t) : Order.Event.t Or_error.t =
    match t with
    | Filled { quantity; price; price_date; at; _ } ->
      if Quantity.equal quantity order.quantity
      then Ok (Filled { price; price_date; at })
      else
        Or_error.error_s
          [%message
            "fill quantity differs from the order"
              ~order:(order.id : Order_id.t)
              ~ordered:(order.quantity : Quantity.t)
              ~filled:(quantity : Quantity.t)]
    | Rejected { reason; at; _ } -> Ok (Rejected { reason; at })
  ;;
end

module Cancel_result = struct
  type t =
    | Cancelled
    | Too_late
  [@@deriving sexp, compare, equal]
end

module type S = sig
  type t

  val name : t -> string
  val display_name : t -> string
  val place : t -> Request.t -> Ack.t Deferred.Or_error.t
  val cancel : t -> broker_ref:string -> Cancel_result.t Deferred.Or_error.t
  val find : t -> idempotency_key:string -> Ack.t option Deferred.Or_error.t
  val events : t -> Event.t Pipe.Reader.t
end
