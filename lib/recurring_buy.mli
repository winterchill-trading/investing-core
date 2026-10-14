(** Recurring buys: spend a fixed amount on one instrument on a schedule.

    This is the hook a scheduler calls, not a scheduler: it says which dates are due,
    turns a due date into an order request with a deterministic order id (so running the
    same date twice places one order, whatever the retry), and counts failures, pausing
    the plan after too many in a row.

    Dates are counted by index from the start date: the [n]th monthly date is [start]
    plus [n] months, clamped to the end of a short month, so a plan started on 31 January
    runs on 28 (or 29) February and on 31 March. When runs were missed (the service was
    down), only the latest due date runs: buying several times at once later would not
    be what the customer scheduled. *)

open! Core

module Cadence : sig
  type t =
    | Weekly
    | Monthly
    | Every_n_days of int
  [@@deriving sexp, compare, equal]

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

module Status : sig
  type t =
    | Active
    | Paused of { reason : string }
  [@@deriving sexp, compare, equal]

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

type t = private
  { id : string (** ledger id alphabet, at most 60 characters *)
  ; account : Ledger.Account_id.t
  ; symbol : Symbol.t
  ; amount : Money.Amount.t
  ; cadence : Cadence.t
  ; start : Date.t
  ; status : Status.t
  ; consecutive_failures : int
  ; max_failures : int
  ; resumed_on : Date.t option (** dates before it are not run *)
  }
[@@deriving sexp, compare, equal]

(** Fails on an invalid id, a non-positive amount, [Every_n_days n] with [n < 1], or
    [max_failures < 1]. *)
val create
  :  id:string
  -> account:Ledger.Account_id.t
  -> symbol:Symbol.t
  -> amount:Money.Amount.t
  -> cadence:Cadence.t
  -> start:Date.t
  -> ?max_failures:int (** default 3 *)
  -> unit
  -> t Or_error.t

(** The [n]th date of the schedule, [n >= 0]. *)
val nth : t -> int -> Date.t

(** Scheduled dates in [[from, until]], ascending. *)
val dates_between : t -> from:Date.t -> until:Date.t -> Date.t list

(** The date to run today: the latest scheduled date on or before [today] that is after
    [last_run] (the last date run, if any) and not before [resumed_on]. [None] while
    paused or when nothing is due. *)
val due : t -> today:Date.t -> last_run:Date.t option -> Date.t option

(** [rb-<id>-<yyyymmdd>]: the order id for a run of the plan, the same on every retry. *)
val order_id : t -> date:Date.t -> Order_id.t

(** [Buy_amount amount]. *)
val request : t -> Order_request.t

(** A run that placed its order: the failure count starts again. *)
val succeeded : t -> t

(** A run that could not place its order; [reason] is kept when this pauses the plan. *)
val failed : t -> reason:string -> t

val pause : t -> reason:string -> t

(** Runs again from [today]: dates that passed while paused are never run, a date equal
    to [today] is. *)
val resume : t -> today:Date.t -> t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
