(** A market order and its life.

    {v
    pending --fill-----> filled
            --reject---> rejected   (cash or shares released)
            --cancel---> cancelled  (cash or shares released)
    v}

    While pending, an order also tracks how far it got towards the broker ([submission]):
    not sent yet, sent with no answer, or acknowledged with the broker's reference. That
    decides whether it can be cancelled ({!cancellable}): an order not sent yet is
    cancelled here; one whose submission is in flight cannot be, because the broker may be
    executing it; an acknowledged one is cancelled once the broker confirms (the caller
    asks the broker first, then applies [Cancelled]).

    {!apply} is the only way to change an order and refuses every transition the diagram
    does not have, so filled, rejected and cancelled are final. *)

open! Core

module Submission : sig
  type t =
    | Not_sent
    | Sent of { at : Time_ns.Alternate_sexp.t } (** sent; no answer yet *)
    | Acknowledged of
        { broker_ref : string
        ; at : Time_ns.Alternate_sexp.t
        }
  [@@deriving sexp, compare, equal]
end

module Fill : sig
  type t =
    { quantity : Quantity.t
    ; price : Price.t
    ; price_date : Date.t option (** the close the price came from, if any *)
    ; gross : Money.Amount.t
    (** [quantity * price]: rounded up for a buy (cost), down for a sale (proceeds) *)
    ; at : Time_ns.Alternate_sexp.t
    }
  [@@deriving sexp, compare, equal]
end

module Status : sig
  type t =
    | Pending
    | Filled of Fill.t
    | Rejected of
        { reason : string (** a code, e.g. [no_price] or [insufficient_funds] *)
        ; at : Time_ns.Alternate_sexp.t
        }
    | Cancelled of { at : Time_ns.Alternate_sexp.t }
  [@@deriving sexp, compare, equal]

  (** ["pending"], ["filled"], ["rejected"], ["cancelled"]. *)
  val name : t -> string

  val is_final : t -> bool
end

module Estimate : sig
  type t =
    { price : Price.t
    ; price_date : Date.t
    ; gross : Money.Amount.t
    ; hold : Money.Amount.t option
    }
  [@@deriving sexp, compare, equal]
end

type t = private
  { id : Order_id.t
  ; account : Ledger.Account_id.t (** the customer's cash account *)
  ; symbol : Symbol.t
  ; request : Order_request.t
  ; quantity : Quantity.t (** exact; fixed when the order is placed *)
  ; estimate : Estimate.t
  ; submission : Submission.t
  ; status : Status.t
  ; created_at : Time_ns.Alternate_sexp.t
  }
[@@deriving sexp, compare, equal]

(** A new pending, unsent order from a {!Placement.plan}. *)
val create
  :  id:Order_id.t
  -> account:Ledger.Account_id.t
  -> symbol:Symbol.t
  -> request:Order_request.t
  -> plan:Placement.Plan.t
  -> at:Time_ns.t
  -> t

val side : t -> Side.t

(** The instrument currency every amount of the order is in. *)
val currency : t -> Money.Currency.t

module Event : sig
  type t =
    | Sent of { at : Time_ns.Alternate_sexp.t }
    | Acknowledged of
        { broker_ref : string
        ; at : Time_ns.Alternate_sexp.t
        }
    | Filled of
        { price : Price.t
        ; price_date : Date.t option
        ; at : Time_ns.Alternate_sexp.t
        } (** the whole quantity executed at [price]; the gross is computed by {!apply} *)
    | Rejected of
        { reason : string
        ; at : Time_ns.Alternate_sexp.t
        }
    | Cancelled of { at : Time_ns.Alternate_sexp.t }
  [@@deriving sexp, compare, equal]
end

module Refusal : sig
  type t =
    | Already_filled
    | Already_rejected
    | Already_cancelled
    | In_transit (** cancel while the submission has no answer yet *)
    | Not_sent_yet (** a fill or acknowledgement for an order never sent *)
    | Already_acknowledged of { broker_ref : string }
    (** a second acknowledgement with another reference *)
  [@@deriving sexp, compare, equal]

  (** A stable snake_case code, e.g. ["already_filled"]. *)
  val code : t -> string
end

(** The new order, or why the event does not apply. Re-sending an acknowledgement with the
    same reference is accepted and changes nothing. *)
val apply : t -> Event.t -> (t, Refusal.t) Result.t

(** [Ok ()] when a cancel may proceed: always for an unsent order, after the broker
    confirms for an acknowledged one. *)
val cancellable : t -> (unit, Refusal.t) Result.t

(** When the order became final. *)
val closed_at : t -> Time_ns.t option

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
