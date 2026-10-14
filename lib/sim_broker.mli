(** A simulated broker for demos and tests: it accepts every order, then after a delay
    fills it whole at the reference price moved by a spread (up for buys, down for
    sells), or rejects it when there is no reference price or the configured outcome is
    to reject.

    Time comes from an Async [Time_source], so tests drive it with a synthetic clock.
    Nothing happens on its own: due orders are decided by {!emit_due}, which a service
    calls from a periodic job ({!start} sets one up) and a test calls after advancing
    its clock. {!fill_now} and {!reject_now} decide one order at once, for demo
    controls. State lives in memory and is lost with the value. *)

open! Core
open Async_kernel

module Config : sig
  type t =
    { fill_delay : Time_ns.Span.t option
    (** how long after placing an order is decided; [None] waits for {!fill_now} or
        {!reject_now} *)
    ; spread_bps : int (** added to the price for buys, taken off for sells *)
    ; outcome : [ `Fill | `Reject ] (** what a due order becomes *)
    }
  [@@deriving sexp, compare, equal]

  (** Four seconds, no spread, fill. *)
  val default : t
end

type t

(** [reference_price symbol ~at] is the close to fill at (usually the latest close in a
    {!Price_history} on [at]'s date); [None] rejects the order. *)
val create
  :  ?config:Config.t
  -> ?display_name:string (** default ["Simulated broker"] *)
  -> time_source:[> read ] Time_source.T1.t
  -> reference_price:(Symbol.t -> at:Time_ns.t -> Close.t option)
  -> unit
  -> t

include Broker.S with type t := t

val config : t -> Config.t

(** Applies to orders placed afterwards; orders already waiting keep the delay, spread
    and outcome they were placed with. *)
val set_config : t -> Config.t -> unit

(** Decides every open order whose due time has passed, oldest first. *)
val emit_due : t -> unit

(** Decides one open order now. Fails for an unknown reference or an order no longer
    open. *)
val fill_now : t -> broker_ref:string -> unit Or_error.t

val reject_now : t -> broker_ref:string -> reason:string -> unit Or_error.t

(** Calls {!emit_due} every [every] (default one second) on the time source until
    [stop] is determined. *)
val start : ?every:Time_ns.Span.t -> ?stop:unit Deferred.t -> t -> unit

module Order_state : sig
  type t =
    | Open of { due_at : Time_ns.Alternate_sexp.t option }
    | Filled
    | Rejected
    | Cancelled
  [@@deriving sexp, compare, equal]
end

(** Every order the broker has seen, by reference, with its state. *)
val orders : t -> (string * Broker.Request.t * Order_state.t) list
