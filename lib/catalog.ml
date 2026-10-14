open! Core

type t = Instrument.t Symbol.Map.t [@@deriving sexp_of]

let empty = Symbol.Map.empty

let add t (instrument : Instrument.t) =
  match Map.add t ~key:instrument.symbol ~data:instrument with
  | `Ok t -> Ok t
  | `Duplicate ->
    Or_error.error_s
      [%message "instrument already listed" ~symbol:(instrument.symbol : Symbol.t)]
;;

let of_list instruments = List.fold_result instruments ~init:empty ~f:add
let set t (instrument : Instrument.t) = Map.set t ~key:instrument.symbol ~data:instrument
let find t symbol = Map.find t symbol

let find_or_error t symbol =
  match find t symbol with
  | Some i -> Ok i
  | None -> Or_error.error_s [%message "unknown instrument" (symbol : Symbol.t)]
;;

let search ?(query = "") ?kind t =
  Map.data t
  |> List.filter ~f:(fun (i : Instrument.t) ->
    Instrument.matches i ~query
    && Option.for_all kind ~f:(fun k -> Instrument.Kind.equal k i.kind))
;;

let to_list t = Map.data t
let length t = Map.length t
