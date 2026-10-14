open! Core
open Async_kernel

module type S = sig
  type t

  val name : t -> string
  val attribution : t -> string

  val closes
    :  t
    -> symbols:Symbol.t list
    -> from:Date.t
    -> to_:Date.t
    -> Close.t list Deferred.Or_error.t
end

let dates_between ~from ~to_ =
  if Date.( > ) from to_ then [] else Date.dates_between ~min:from ~max:to_
;;

module Simulated = struct
  type t =
    { seed : int
    ; daily_bps : int
    ; decimals : int
    ; origin : Close.Origin.t
    ; anchor_date : Date.t
    ; start_prices : Price.t Symbol.Map.t
    }

  let max_daily_bps = 2_000

  let rec previous_weekday d =
    if Date.is_weekend d then previous_weekday (Date.add_days d (-1)) else d
  ;;

  let create
    ?(seed = 0)
    ?(daily_bps = 150)
    ?(decimals = 2)
    ?(origin = Close.Origin.Simulated)
    ~anchor_date
    ~start_prices
    ()
    =
    if daily_bps < 0 || daily_bps > max_daily_bps
    then Or_error.error_s [%message "daily_bps out of range" (daily_bps : int)]
    else if decimals < 0 || decimals > 8
    then Or_error.error_s [%message "decimals out of range" (decimals : int)]
    else (
      match Symbol.Map.of_alist start_prices with
      | `Duplicate_key symbol ->
        Or_error.error_s [%message "symbol given twice" (symbol : Symbol.t)]
      | `Ok start_prices ->
        Ok
          { seed
          ; daily_bps
          ; decimals
          ; origin
          ; anchor_date = previous_weekday anchor_date
          ; start_prices
          })
  ;;

  (* The step into [date], in basis points within [-daily_bps, daily_bps]. MD5 rather than
     [Hashtbl.hash] so the walk is the same on every platform and OCaml version. *)
  let step_bps t symbol date =
    let digest =
      Md5.digest_string
        (sprintf "%d/%s/%s" t.seed (Symbol.to_string symbol) (Date.to_string date))
      |> Md5.to_binary
    in
    let n = ref 0 in
    for i = 0 to 5 do
      n := (!n lsl 8) lor Char.to_int digest.[i]
    done;
    (!n % ((2 * t.daily_bps) + 1)) - t.daily_bps
  ;;

  let move units ~bps ~forward =
    (* Forward multiplies by (1 + bps/10^4); backward undoes it. Half-even keeps the walk
       free of drift from rounding. Never below one unit (10^-8). *)
    let q =
      if forward
      then Q.mul (Q.of_int units) (Q.of_ints (10_000 + bps) 10_000)
      else Q.div (Q.of_int units) (Q.of_ints (10_000 + bps) 10_000)
    in
    Int.max 1 (Z.to_int (Money.Rounding.round Half_even q))
  ;;

  let units_on t symbol start date =
    let start = Price.to_units start in
    if Date.( >= ) date t.anchor_date
    then
      List.fold
        (Date.weekdays_between ~min:(Date.add_days t.anchor_date 1) ~max:date)
        ~init:start
        ~f:(fun units d -> move units ~bps:(step_bps t symbol d) ~forward:true)
    else
      (* Going back from the anchor undoes each weekday's step, latest first. *)
      List.fold
        (List.rev (Date.weekdays_between ~min:(Date.add_days date 1) ~max:t.anchor_date))
        ~init:start
        ~f:(fun units d -> move units ~bps:(step_bps t symbol d) ~forward:false)
  ;;

  (* The walk keeps all eight decimals; only the published close is rounded, so rounding
     never feeds back into later steps. *)
  let published t units =
    let unit = Int.pow 10 (8 - t.decimals) in
    let rounded =
      Z.to_int (Money.Rounding.round Half_even (Q.of_ints units unit)) * unit
    in
    Price.of_units (Int.max unit rounded) |> Or_error.ok_exn
  ;;

  let close t symbol date =
    if Date.is_weekend date
    then None
    else
      Option.map (Map.find t.start_prices symbol) ~f:(fun start ->
        let units = units_on t symbol start date in
        { Close.symbol; date; close = published t units; origin = t.origin })
  ;;

  let name _ = "simulated"
  let attribution _ = "Simulated prices, not market data"

  (* One pass per symbol across the range, computing each close from its neighbour in the
     same order [units_on] does (forward after the anchor, backward before it), so the
     result matches [close] exactly despite rounding at every step. *)
  let series t symbol ~from ~to_ =
    match Map.find t.start_prices symbol with
    | None -> []
    | Some start ->
      let days =
        if Date.( > ) from to_ then [] else Date.weekdays_between ~min:from ~max:to_
      in
      let before, after =
        List.partition_tf days ~f:(fun d -> Date.( < ) d t.anchor_date)
      in
      let forward =
        match after with
        | [] -> []
        | first :: rest ->
          List.folding_map rest ~init:(units_on t symbol start first) ~f:(fun u d ->
            let u' = move u ~bps:(step_bps t symbol d) ~forward:true in
            u', (d, u'))
          |> List.cons (first, units_on t symbol start first)
      in
      let backward =
        match List.rev before with
        | [] -> []
        | last :: earlier ->
          (* [prev] is the later neighbour whose step is undone to reach [d]. *)
          let last_units = units_on t symbol start last in
          let _, _, acc =
            List.fold
              earlier
              ~init:(last, last_units, [ last, last_units ])
              ~f:(fun (prev, u, acc) d ->
                let u = move u ~bps:(step_bps t symbol prev) ~forward:false in
                d, u, (d, u) :: acc)
          in
          acc
      in
      List.map (backward @ forward) ~f:(fun (date, units) ->
        { Close.symbol; date; close = published t units; origin = t.origin })
  ;;

  let closes t ~symbols ~from ~to_ =
    Deferred.Or_error.return
      (List.concat_map symbols ~f:(fun symbol -> series t symbol ~from ~to_))
  ;;
end

module Fixed = struct
  type t =
    { name : string
    ; history : Price_history.t
    }

  let create ?(name = "fixed") history = { name; history }
  let name t = t.name
  let attribution _ = ""

  let closes t ~symbols ~from ~to_ =
    let dates = dates_between ~from ~to_ in
    Deferred.Or_error.return
      (List.concat_map symbols ~f:(fun symbol ->
         List.filter_map dates ~f:(fun date -> Price_history.on t.history symbol date)))
  ;;
end
