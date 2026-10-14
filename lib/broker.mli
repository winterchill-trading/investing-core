(** The brokerage port: what an executing broker must offer.

    Orders go to the broker as market orders for an exact quantity (the cash-to-shares
    conversion already happened in {!Placement}). Placing is idempotent per
    [idempotency_key]: placing again with the same key returns the first acknowledgement,
    and {!S.find} recovers it after a lost answer, so a caller that crashed between
    sending and recording can resend safely. Outcomes arrive later as {!Event.t}s, each
    with an [event_id] unique per broker, so a consumer books each one once. *)

open! Core
open Async_kernel

module Request : sig
  type t =
    { idempotency_key : string
    ; order_id : Order_id.t
    ; symbol : Symbol.t
    ; side : Side.t
    ; quantity : Quantity.t
    ; requested_at : Time_ns.Alternate_sexp.t
    }
  [@@deriving sexp, compare, equal]

  (** The request for a pending order, keyed by the order id. *)
  val of_order : Order.t -> at:Time_ns.t -> t
end

module Ack : sig
  type t = { broker_ref : string } [@@deriving sexp, compare, equal]
end

module Event : sig
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

  val event_id : t -> string
  val order_id : t -> Order_id.t

  (** The {!Order.Event.t} to apply. Fails when a fill's quantity is not the order's
      (market orders here fill whole). *)
  val to_order_event : t -> Order.t -> Order.Event.t Or_error.t
end

module Cancel_result : sig
  type t =
    | Cancelled (** no fill will follow *)
    | Too_late (** already filled or rejected; its event follows or has been sent *)
  [@@deriving sexp, compare, equal]
end

module type S = sig
  type t

  (** Short identifier, e.g. ["simulated"]. *)
  val name : t -> string

  (** Name to show customers. *)
  val display_name : t -> string

  val place : t -> Request.t -> Ack.t Deferred.Or_error.t
  val cancel : t -> broker_ref:string -> Cancel_result.t Deferred.Or_error.t
  val find : t -> idempotency_key:string -> Ack.t option Deferred.Or_error.t

  (** Fills and rejections, in the order they happen. One reader per broker value. *)
  val events : t -> Event.t Pipe.Reader.t
end
