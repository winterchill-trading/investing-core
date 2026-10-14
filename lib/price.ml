open! Core
module F = Fixed_decimal.Make ()

let units_per_one = 100_000_000

module T = struct
  type t = int [@@deriving compare, equal, hash]

  let of_units n =
    if n <= 0
    then Or_error.error_s [%message "price must be positive" ~units:(n : int)]
    else Ok n
  ;;

  let to_string t = F.to_string (F.of_units t)

  let of_string_or_error s =
    let open Or_error.Let_syntax in
    let%bind v = Or_error.tag (F.of_string_exact s) ~tag:"price" in
    of_units (F.to_units v)
  ;;

  let of_string s = Or_error.ok_exn (of_string_or_error s)
  let sexp_of_t t = Sexp.Atom (to_string t)
  let t_of_sexp sexp = of_string (string_of_sexp sexp)
end

include T

let to_units t = t
let to_q t = Q.of_ints t units_per_one

let of_q ~rounding q =
  let units = Money.Rounding.round rounding (Q.mul q (Q.of_int units_per_one)) in
  if Z.fits_int units
  then of_units (Z.to_int units)
  else Or_error.error_s [%message "price out of range" ~price:(Q.to_string q)]
;;

let gross t quantity ~currency ~rounding =
  Money.Amount.of_q ~rounding currency (Q.mul (to_q t) (Quantity.to_q quantity))
;;

let quantity_for t amount ~rounding =
  if Money.Amount.is_negative amount
  then
    Or_error.error_s
      [%message "negative amount" ~amount:(Money.Amount.to_string amount : string)]
  else Quantity.of_q ~rounding (Q.div (Money.Amount.to_q amount) (to_q t))
;;

let adjust_bps t ~bps ~rounding =
  of_q ~rounding (Q.mul (to_q t) (Q.of_ints (10_000 + bps) 10_000))
;;

let change ~from ~to_ = Q.of_ints (to_ - from) from

let quickcheck_generator =
  (* From a cent to ten thousand, with two to eight decimals. *)
  Quickcheck.Generator.union
    [ Int.gen_incl 1 1_000_000 |> Quickcheck.Generator.map ~f:(fun c -> c * 1_000_000)
    ; Int.gen_incl 1 (10_000 * units_per_one)
    ]
;;

let quickcheck_observer = Int.quickcheck_observer
let quickcheck_shrinker = Quickcheck.Shrinker.filter Int.quickcheck_shrinker ~f:(fun n -> n > 0)

include Comparable.Make (struct
    include T
  end)

module Stable = struct
  module V1 = struct
    include T

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Int)
        (struct
          type t = int

          let to_binable = Fn.id
          let of_binable n = Or_error.ok_exn (of_units n)
        end)
  end
end
