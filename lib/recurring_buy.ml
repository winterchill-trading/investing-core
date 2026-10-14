open! Core

module Cadence = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Weekly
        | Monthly
        | Every_n_days of int
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1
end

module Status = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Active
        | Paused of { reason : string }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1
end

module Stable = struct
  module V1 = struct
    type t =
      { id : string
      ; account : Ledger.Account_id.Stable.V1.t
      ; symbol : Symbol.Stable.V1.t
      ; amount : Money.Amount.Stable.V1.t
      ; cadence : Cadence.Stable.V1.t
      ; start : Date.Stable.V1.t
      ; status : Status.Stable.V1.t
      ; consecutive_failures : int
      ; max_failures : int
      ; resumed_on : Date.Stable.V1.t option
      }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

include Stable.V1

(* Leaves room for "rb-", the date and Booking's prefixes inside ledger keys. *)
let max_id_length = 60

let create ~id ~account ~symbol ~amount ~cadence ~start ?(max_failures = 3) () =
  let open Or_error.Let_syntax in
  let%bind () =
    if String.length id > max_id_length
    then Or_error.error_s [%message "recurring buy id too long" id]
    else Ledger.Validated_id.check id
  in
  let%bind () =
    if Money.Amount.is_positive amount
    then Ok ()
    else Or_error.error_s [%message "amount must be positive" ~amount:(Money.Amount.to_string amount)]
  in
  let%bind () =
    match (cadence : Cadence.t) with
    | Every_n_days n when n < 1 -> Or_error.error_s [%message "interval must be at least a day" (n : int)]
    | Weekly | Monthly | Every_n_days _ -> Ok ()
  in
  let%map () =
    if max_failures < 1
    then Or_error.error_s [%message "max_failures must be positive" (max_failures : int)]
    else Ok ()
  in
  { id
  ; account
  ; symbol
  ; amount
  ; cadence
  ; start
  ; status = Active
  ; consecutive_failures = 0
  ; max_failures
  ; resumed_on = None
  }
;;

let nth t n =
  match t.cadence with
  | Weekly -> Date.add_days t.start (7 * n)
  | Every_n_days d -> Date.add_days t.start (d * n)
  | Monthly -> Date.add_months t.start n
;;

(* Index of the last date on or before [d], or -1. Monthly dates are not evenly spaced,
   so estimate from the month difference and step to the exact index. *)
let index_on_or_before t d =
  if Date.( < ) d t.start
  then -1
  else (
    match t.cadence with
    | Weekly -> Date.diff d t.start / 7
    | Every_n_days n -> Date.diff d t.start / n
    | Monthly ->
      let guess =
        ((Date.year d - Date.year t.start) * 12)
        + (Month.to_int (Date.month d) - Month.to_int (Date.month t.start))
      in
      let rec down i = if i > 0 && Date.( > ) (nth t i) d then down (i - 1) else i in
      let rec up i = if Date.( <= ) (nth t (i + 1)) d then up (i + 1) else i in
      up (down (Int.max 0 guess)))
;;

let dates_between t ~from ~until =
  let last = index_on_or_before t until in
  let first = index_on_or_before t (Date.add_days from (-1)) + 1 in
  List.range first (last + 1) |> List.map ~f:(nth t)
;;

let due t ~today ~last_run =
  match t.status with
  | Paused _ -> None
  | Active ->
    let i = index_on_or_before t today in
    if i < 0
    then None
    else (
      let date = nth t i in
      let skipped =
        Option.exists last_run ~f:(fun last -> Date.( >= ) last date)
        || Option.exists t.resumed_on ~f:(fun r -> Date.( < ) date r)
      in
      if skipped then None else Some date)
;;

let order_id t ~date =
  Order_id.of_string (sprintf "rb-%s-%s" t.id (Date.to_string_iso8601_basic date))
;;

let request t = Order_request.Buy_amount t.amount
let succeeded t = { t with consecutive_failures = 0 }

let failed t ~reason =
  let consecutive_failures = t.consecutive_failures + 1 in
  let status =
    if consecutive_failures >= t.max_failures then Status.Paused { reason } else t.status
  in
  { t with consecutive_failures; status }
;;

let pause t ~reason = { t with status = Paused { reason } }
let resume t ~today =
  { t with status = Active; consecutive_failures = 0; resumed_on = Some today }
;;
