open! Core

type t = Close.t Date.Map.t Symbol.Map.t [@@deriving sexp_of]

let empty = Symbol.Map.empty

let add t (close : Close.t) =
  Map.update t close.symbol ~f:(fun by_date ->
    let by_date = Option.value by_date ~default:Date.Map.empty in
    Map.update by_date close.date ~f:(function
      | None -> close
      | Some existing -> Close.preferred existing close))
;;

let add_all t closes = List.fold closes ~init:t ~f:add
let of_list closes = add_all empty closes
let symbols t = Map.keys t
let dates t symbol = Map.find t symbol |> Option.value ~default:Date.Map.empty

let latest ?on_or_before t symbol =
  let by_date = dates t symbol in
  match on_or_before with
  | None -> Map.max_elt by_date |> Option.map ~f:snd
  | Some date ->
    Map.closest_key by_date `Less_or_equal_to date |> Option.map ~f:snd
;;

let before t symbol date =
  Map.closest_key (dates t symbol) `Less_than date |> Option.map ~f:snd
;;

let on t symbol date = Map.find (dates t symbol) date

let window t symbol ~until ~days =
  if days < 1
  then Or_error.error_s [%message "window must cover at least one day" (days : int)]
  else (
    let from = Date.add_days until (-(days - 1)) in
    Ok
      (Map.subrange (dates t symbol) ~lower_bound:(Incl from) ~upper_bound:(Incl until)
       |> Map.data))
;;

let low_high t symbol ~until ~days =
  match window t symbol ~until ~days with
  | Error _ | Ok [] -> None
  | Ok ((first : Close.t) :: rest) ->
    Some
      (List.fold rest ~init:(first.close, first.close) ~f:(fun (lo, hi) (c : Close.t) ->
         Price.min lo c.close, Price.max hi c.close))
;;

module Quote = struct
  type t =
    { close : Close.t
    ; previous : Close.t option
    ; verdict : Staleness.Verdict.t
    }
  [@@deriving sexp_of]

  let price t = t.close.close

  let change t =
    Option.map t.previous ~f:(fun p ->
      Q.sub (Price.to_q t.close.close) (Price.to_q p.close))
  ;;

  let change_ratio t =
    Option.map t.previous ~f:(fun p -> Price.change ~from:p.close ~to_:t.close.close)
  ;;
end

module Unavailable = struct
  type t =
    | No_price of { symbol : Symbol.t }
    | Too_old of
        { symbol : Symbol.t
        ; date : Date.t
        ; age_days : int
        }
  [@@deriving sexp, compare, equal]
end

let quote ?(staleness = Staleness.default) t symbol ~today =
  match latest ~on_or_before:today t symbol with
  | None -> Error (Unavailable.No_price { symbol })
  | Some (close : Close.t) ->
    (match Staleness.classify staleness ~today ~date:close.date with
     | Too_old { age_days } ->
       Error (Unavailable.Too_old { symbol; date = close.date; age_days })
     | (Fresh | Stale _) as verdict ->
       Ok { Quote.close; previous = before t symbol close.date; verdict })
;;
