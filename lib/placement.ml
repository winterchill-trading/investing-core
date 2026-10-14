open! Core
module Amount = Money.Amount

module Refusal = struct
  type t =
    | Not_tradable of
        { symbol : Symbol.t
        ; status : Listing.Status.t
        }
    | Currency_mismatch of
        { expected : Money.Currency.t
        ; got : Money.Currency.t
        }
    | Not_positive
    | Price_unavailable of Price_history.Unavailable.t
    | Too_small_for_one_unit
    | No_holdings of { symbol : Symbol.t }
    | Holdings_reserved of { symbol : Symbol.t }
    | Exceeds_holdings of { available : Quantity.t }
    | Below_minimum of { minimum : Amount.t }
    | Above_maximum of { maximum : Amount.t }
  [@@deriving sexp, compare, equal]

  let code = function
    | Not_tradable _ -> "not_tradable"
    | Currency_mismatch _ -> "currency_mismatch"
    | Not_positive -> "not_positive"
    | Price_unavailable (No_price _) -> "price_unavailable"
    | Price_unavailable (Too_old _) -> "price_too_old"
    | Too_small_for_one_unit -> "too_small_for_one_unit"
    | No_holdings _ -> "no_holdings"
    | Holdings_reserved _ -> "holdings_reserved"
    | Exceeds_holdings _ -> "exceeds_holdings"
    | Below_minimum _ -> "below_minimum"
    | Above_maximum _ -> "above_maximum"
  ;;
end

module Plan = struct
  type t =
    { side : Side.t
    ; quantity : Quantity.t
    ; quote : Price_history.Quote.t
    ; estimated_gross : Amount.t
    ; hold : Amount.t option
    ; reserve : Quantity.t option
    }
  [@@deriving sexp_of]
end

let plan
  ?staleness
  ?limits
  ~(instrument : Instrument.t)
  ~prices
  ~today
  ~(position : Position.t option)
  (request : Order_request.t)
  =
  let open Result.Let_syntax in
  let currency = Instrument.currency instrument in
  let symbol = instrument.symbol in
  let limits = Option.value limits ~default:(Order_limits.default currency) in
  let%bind () =
    if Listing.accepts_orders instrument.listing
    then Ok ()
    else Error (Refusal.Not_tradable { symbol; status = instrument.listing.status })
  in
  let check_amount a =
    if not (Money.Currency.equal (Amount.currency a) currency)
    then
      Error (Refusal.Currency_mismatch { expected = currency; got = Amount.currency a })
    else if not (Amount.is_positive a)
    then Error Refusal.Not_positive
    else Ok ()
  in
  let check_quantity q =
    if Quantity.is_positive q then Ok () else Error Refusal.Not_positive
  in
  let%bind () =
    match request with
    | Buy_amount a | Sell_amount a -> check_amount a
    | Buy_quantity q | Sell_quantity q -> check_quantity q
    | Sell_all -> Ok ()
  in
  let%bind quote =
    Price_history.quote ?staleness prices symbol ~today
    |> Result.map_error ~f:(fun u -> Refusal.Price_unavailable u)
  in
  let price = Price_history.Quote.price quote in
  let shares_for a =
    match Price.quantity_for price a ~rounding:Down with
    | Ok q when Quantity.is_positive q -> Ok q
    | Ok _ | Error _ -> Error Refusal.Too_small_for_one_unit
  in
  let gross q ~rounding = Price.gross price q ~currency ~rounding in
  let available =
    Option.value_map position ~default:Quantity.zero ~f:Position.available
  in
  let holding_refusal () =
    match position with
    | Some p when Quantity.is_positive p.quantity -> Refusal.Holdings_reserved { symbol }
    | Some _ | None -> Refusal.No_holdings { symbol }
  in
  let can_sell q =
    if Quantity.is_zero available
    then Error (holding_refusal ())
    else if Quantity.( > ) q available
    then Error (Refusal.Exceeds_holdings { available })
    else Ok ()
  in
  let check_limits value ~exempt_from_minimum =
    if Amount.( < ) value limits.minimum && not exempt_from_minimum
    then Error (Refusal.Below_minimum { minimum = limits.minimum })
    else if Amount.( > ) value limits.maximum
    then Error (Refusal.Above_maximum { maximum = limits.maximum })
    else Ok ()
  in
  let buy ~quantity ~hold ~limit_value =
    let estimated_gross = gross quantity ~rounding:Up in
    let%map () = check_limits limit_value ~exempt_from_minimum:false in
    { Plan.side = Buy
    ; quantity
    ; quote
    ; estimated_gross
    ; hold = Some (Option.value hold ~default:estimated_gross)
    ; reserve = None
    }
  in
  let sell ~quantity =
    let%bind () = can_sell quantity in
    let estimated_gross = gross quantity ~rounding:Down in
    let%map () =
      check_limits
        estimated_gross
        ~exempt_from_minimum:(Quantity.equal quantity available)
    in
    { Plan.side = Sell
    ; quantity
    ; quote
    ; estimated_gross
    ; hold = None
    ; reserve = Some quantity
    }
  in
  match request with
  | Buy_amount a ->
    (* The amount, not the slightly smaller estimated cost, is held and checked against
       the limits: it is what the customer asked to spend. *)
    let%bind quantity = shares_for a in
    buy ~quantity ~hold:(Some a) ~limit_value:a
  | Buy_quantity quantity ->
    buy ~quantity ~hold:None ~limit_value:(gross quantity ~rounding:Up)
  | Sell_quantity quantity -> sell ~quantity
  | Sell_amount a ->
    let%bind quantity = shares_for a in
    sell ~quantity
  | Sell_all ->
    if Quantity.is_zero available
    then Error (holding_refusal ())
    else sell ~quantity:available
;;
