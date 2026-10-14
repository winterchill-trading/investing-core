open! Core
module Amount = Money.Amount
module Time = Time_ns.Stable.Alternate_sexp.V1

module Submission = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Not_sent
        | Sent of { at : Time.t }
        | Acknowledged of
            { broker_ref : string
            ; at : Time.t
            }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1
end

module Fill = struct
  module Stable = struct
    module V1 = struct
      type t =
        { quantity : Quantity.Stable.V1.t
        ; price : Price.Stable.V1.t
        ; price_date : Date.Stable.V1.t option
        ; gross : Amount.Stable.V1.t
        ; at : Time.t
        }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1
end

module Status = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Pending
        | Filled of Fill.Stable.V1.t
        | Rejected of
            { reason : string
            ; at : Time.t
            }
        | Cancelled of { at : Time.t }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1

  let name = function
    | Pending -> "pending"
    | Filled _ -> "filled"
    | Rejected _ -> "rejected"
    | Cancelled _ -> "cancelled"
  ;;

  let is_final = function
    | Pending -> false
    | Filled _ | Rejected _ | Cancelled _ -> true
  ;;
end

module Estimate = struct
  module Stable = struct
    module V1 = struct
      type t =
        { price : Price.Stable.V1.t
        ; price_date : Date.Stable.V1.t
        ; gross : Amount.Stable.V1.t
        ; hold : Amount.Stable.V1.t option
        }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1
end

module Stable = struct
  module V1 = struct
    type t =
      { id : Order_id.Stable.V1.t
      ; account : Ledger.Account_id.Stable.V1.t
      ; symbol : Symbol.Stable.V1.t
      ; request : Order_request.Stable.V1.t
      ; quantity : Quantity.Stable.V1.t
      ; estimate : Estimate.Stable.V1.t
      ; submission : Submission.Stable.V1.t
      ; status : Status.Stable.V1.t
      ; created_at : Time.t
      }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

include Stable.V1

let create ~id ~account ~symbol ~request ~(plan : Placement.Plan.t) ~at =
  let close = plan.quote.close in
  { id
  ; account
  ; symbol
  ; request
  ; quantity = plan.quantity
  ; estimate =
      { price = close.close
      ; price_date = close.date
      ; gross = plan.estimated_gross
      ; hold = plan.hold
      }
  ; submission = Not_sent
  ; status = Pending
  ; created_at = at
  }
;;

let side t = Order_request.side t.request
let currency t = Amount.currency t.estimate.gross

module Event = struct
  type t =
    | Sent of { at : Time.t }
    | Acknowledged of
        { broker_ref : string
        ; at : Time.t
        }
    | Filled of
        { price : Price.t
        ; price_date : Date.t option
        ; at : Time.t
        }
    | Rejected of
        { reason : string
        ; at : Time.t
        }
    | Cancelled of { at : Time.t }
  [@@deriving sexp, compare, equal]
end

module Refusal = struct
  type t =
    | Already_filled
    | Already_rejected
    | Already_cancelled
    | In_transit
    | Not_sent_yet
    | Already_acknowledged of { broker_ref : string }
  [@@deriving sexp, compare, equal]

  let code = function
    | Already_filled -> "already_filled"
    | Already_rejected -> "already_rejected"
    | Already_cancelled -> "already_cancelled"
    | In_transit -> "in_transit"
    | Not_sent_yet -> "not_sent_yet"
    | Already_acknowledged _ -> "already_acknowledged"
  ;;
end

let final_refusal : Status.t -> Refusal.t option = function
  | Pending -> None
  | Filled _ -> Some Already_filled
  | Rejected _ -> Some Already_rejected
  | Cancelled _ -> Some Already_cancelled
;;

let cancellable t =
  match final_refusal t.status, t.submission with
  | Some r, _ -> Error r
  | None, Sent _ -> Error Refusal.In_transit
  | None, (Not_sent | Acknowledged _) -> Ok ()
;;

let apply t (event : Event.t) =
  match final_refusal t.status with
  | Some r -> Error r
  | None ->
    (match event, t.submission with
     | Sent { at }, Not_sent -> Ok { t with submission = Sent { at } }
     (* A resend after a lost answer: still in flight. *)
     | Sent _, Sent _ -> Ok t
     | Sent _, Acknowledged _ -> Ok t
     | Acknowledged _, Not_sent -> Error Not_sent_yet
     | Acknowledged { broker_ref; at }, Sent _ ->
       Ok { t with submission = Acknowledged { broker_ref; at } }
     | Acknowledged { broker_ref; _ }, Acknowledged existing ->
       if String.equal broker_ref existing.broker_ref
       then Ok t
       else Error (Already_acknowledged { broker_ref = existing.broker_ref })
     | Filled _, Not_sent -> Error Not_sent_yet
     | Filled { price; price_date; at }, (Sent _ | Acknowledged _) ->
       let rounding : Money.Rounding.t =
         match side t with
         | Buy -> Up
         | Sell -> Down
       in
       let gross = Price.gross price t.quantity ~currency:(currency t) ~rounding in
       Ok
         { t with
           status = Filled { quantity = t.quantity; price; price_date; gross; at }
         }
     | Rejected { reason; at }, _ -> Ok { t with status = Rejected { reason; at } }
     | Cancelled { at }, _ ->
       Result.map (cancellable t) ~f:(fun () -> { t with status = Cancelled { at } }))
;;

let closed_at t =
  match t.status with
  | Pending -> None
  | Filled { at; _ } | Rejected { at; _ } | Cancelled { at } -> Some at
;;
