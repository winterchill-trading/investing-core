open! Core
module Amount = Money.Amount

module Stable = struct
  module V1 = struct
    module Wire = struct
      type t =
        { symbol : Symbol.Stable.V1.t
        ; quantity : Quantity.Stable.V1.t
        ; reserved : Quantity.Stable.V1.t
        ; cost_basis : Amount.Stable.V1.t
        ; realised : Amount.Stable.V1.t
        }
      [@@deriving bin_io, sexp, compare, equal]
    end

    type t = Wire.t =
      { symbol : Symbol.t
      ; quantity : Quantity.t
      ; reserved : Quantity.t
      ; cost_basis : Amount.t
      ; realised : Amount.t
      }
    [@@deriving compare, equal, sexp_of]

    let validate (t : t) =
      if not (Money.Currency.equal (Amount.currency t.cost_basis) (Amount.currency t.realised))
      then Or_error.error_s [%message "position amounts in two currencies" ~position:(t : t)]
      else if Quantity.( > ) t.reserved t.quantity
      then Or_error.error_s [%message "more reserved than held" ~position:(t : t)]
      else if Amount.is_negative t.cost_basis
      then Or_error.error_s [%message "negative cost basis" ~position:(t : t)]
      else if Quantity.is_zero t.quantity && not (Amount.is_zero t.cost_basis)
      then Or_error.error_s [%message "cost basis without shares" ~position:(t : t)]
      else Ok t
    ;;

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Wire)
        (struct
          type nonrec t = t

          let to_binable = Fn.id
          let of_binable w = Or_error.ok_exn (validate w)
        end)

    let t_of_sexp sexp = Or_error.ok_exn (validate (Wire.t_of_sexp sexp))
  end
end

include Stable.V1

let empty symbol currency =
  { symbol
  ; quantity = Quantity.zero
  ; reserved = Quantity.zero
  ; cost_basis = Amount.zero currency
  ; realised = Amount.zero currency
  }
;;

let currency t = Amount.currency t.cost_basis
let available t = Quantity.sub t.quantity t.reserved |> Or_error.ok_exn
let is_flat t = Quantity.is_zero t.quantity

let reserve t q =
  if Quantity.( > ) q (available t)
  then
    Or_error.error_s
      [%message
        "not enough shares available"
          ~symbol:(t.symbol : Symbol.t)
          ~requested:(q : Quantity.t)
          ~available:(available t : Quantity.t)]
  else Ok { t with reserved = Quantity.add t.reserved q }
;;

let release t q =
  Or_error.map
    (Or_error.tag (Quantity.sub t.reserved q) ~tag:"release more than reserved")
    ~f:(fun reserved -> { t with reserved })
;;

let check_currency t amount what =
  if Money.Currency.equal (currency t) (Amount.currency amount)
  then Ok ()
  else
    Or_error.error_s
      [%message
        "amount in another currency"
          what
          ~symbol:(t.symbol : Symbol.t)
          ~amount:(Amount.to_string amount)]
;;

let buy t ~quantity ~cost =
  let open Or_error.Let_syntax in
  let%bind () = check_currency t cost "cost" in
  if Amount.is_negative cost
  then Or_error.error_s [%message "negative cost" ~cost:(Amount.to_string cost)]
  else
    Ok
      { t with
        quantity = Quantity.add t.quantity quantity
      ; cost_basis = Amount.add_exn t.cost_basis cost
      }
;;

module Sale = struct
  type t =
    { cost_removed : Amount.t
    ; realised : Amount.t
    }
  [@@deriving sexp, compare, equal]
end

let sell ?(from_reserved = true) t ~quantity ~proceeds =
  let open Or_error.Let_syntax in
  let%bind () = check_currency t proceeds "proceeds" in
  let%bind () =
    if Amount.is_negative proceeds
    then Or_error.error_s [%message "negative proceeds" ~proceeds:(Amount.to_string proceeds)]
    else Ok ()
  in
  let%bind reserved =
    if from_reserved
    then Or_error.tag (Quantity.sub t.reserved quantity) ~tag:"sell more than reserved"
    else if Quantity.( > ) quantity (available t)
    then Or_error.error_s [%message "sell more than available" (quantity : Quantity.t)]
    else Ok t.reserved
  in
  let%bind remaining = Or_error.tag (Quantity.sub t.quantity quantity) ~tag:"sell more than held" in
  let cost_removed =
    if Quantity.is_zero remaining
    then t.cost_basis
    else
      Amount.mul_ratio
        ~rounding:Half_even
        t.cost_basis
        (Q.of_ints (Quantity.to_micro quantity) (Quantity.to_micro t.quantity))
  in
  let realised = Amount.sub_exn proceeds cost_removed in
  Ok
    ( { t with
        quantity = remaining
      ; reserved
      ; cost_basis = Amount.sub_exn t.cost_basis cost_removed
      ; realised = Amount.add_exn t.realised realised
      }
    , { Sale.cost_removed; realised } )
;;

let average_cost t =
  if Quantity.is_zero t.quantity
  then None
  else
    Price.of_q ~rounding:Half_even (Q.div (Amount.to_q t.cost_basis) (Quantity.to_q t.quantity))
    |> Result.ok
;;

module Valuation = struct
  type t =
    { value : Amount.t
    ; unrealised : Amount.t
    ; unrealised_ratio : Q.t option
    }

  let sexp_of_t { value; unrealised; unrealised_ratio } =
    [%sexp
      { value : Amount.t
      ; unrealised : Amount.t
      ; unrealised_ratio : string option = Option.map unrealised_ratio ~f:Q.to_string
      }]
  ;;
end

let value_at t price =
  let value = Price.gross price t.quantity ~currency:(currency t) ~rounding:Half_even in
  let unrealised = Amount.sub_exn value t.cost_basis in
  let unrealised_ratio =
    if Amount.is_zero t.cost_basis
    then None
    else Some (Q.div (Amount.to_q unrealised) (Amount.to_q t.cost_basis))
  in
  { Valuation.value; unrealised; unrealised_ratio }
;;
