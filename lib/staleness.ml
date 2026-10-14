open! Core

type t =
  { stale_after : int
  ; refuse_after : int
  }
[@@deriving sexp, compare, equal]

let create ~stale_after ~refuse_after =
  if 0 <= stale_after && stale_after <= refuse_after
  then Ok { stale_after; refuse_after }
  else
    Or_error.error_s
      [%message "staleness limits out of order" (stale_after : int) (refuse_after : int)]
;;

let default = { stale_after = 4; refuse_after = 10 }

module Verdict = struct
  type t =
    | Fresh
    | Stale of { age_days : int }
    | Too_old of { age_days : int }
  [@@deriving sexp, compare, equal]
end

let classify t ~today ~date =
  let age_days = Int.max 0 (Date.diff today date) in
  if age_days > t.refuse_after
  then Verdict.Too_old { age_days }
  else if age_days > t.stale_after
  then Stale { age_days }
  else Fresh
;;
