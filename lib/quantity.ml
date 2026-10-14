open! Core

let decimals = 6

(* One share is 10^6 micro-shares. Fixed_decimal counts 10^-8 units, so a quantity is a
   Fixed_decimal value whose last two digits are zero; we keep our own int to make the
   six-place rule part of the type. *)
let scale = 1_000_000

(* Keeps [to_fixed_decimal] in range: Fixed_decimal holds about 4.6 * 10^10 whole units. *)
let max_micro = Int.max_value / 100

module T = struct
  type t = int [@@deriving compare, equal, hash]

  let to_string t =
    let whole = t / scale
    and frac = t mod scale in
    if frac = 0
    then Int.to_string whole
    else (
      let digits = sprintf "%06d" frac in
      let digits = String.rstrip digits ~drop:(Char.equal '0') in
      sprintf "%d.%s" whole digits)
  ;;

  let of_micro n =
    if n < 0
    then Or_error.error_s [%message "negative quantity" ~micro:(n : int)]
    else if n > max_micro
    then Or_error.error_s [%message "quantity out of range" ~micro:(n : int)]
    else Ok n
  ;;

  let of_string_or_error s =
    let fail reason = Or_error.error_s [%message reason ~quantity:(s : string)] in
    let whole, frac =
      match String.lsplit2 s ~on:'.' with
      | None -> s, ""
      | Some (w, f) -> w, f
    in
    let all_digits x = String.for_all x ~f:Char.is_digit in
    if String.is_empty whole && String.is_empty frac
    then fail "empty quantity"
    else if not (all_digits whole && all_digits frac)
    then fail "malformed quantity"
    else (
      let kept, extra =
        if String.length frac <= decimals
        then frac, ""
        else String.prefix frac decimals, String.drop_prefix frac decimals
      in
      if not (String.for_all extra ~f:(Char.equal '0'))
      then fail "more than six decimal places"
      else if String.length (String.lstrip whole ~drop:(Char.equal '0')) > 12
      then fail "quantity out of range"
      else (
        let whole = if String.is_empty whole then 0 else Int.of_string whole in
        let kept = kept ^ String.make (decimals - String.length kept) '0' in
        of_micro ((whole * scale) + Int.of_string kept)))
  ;;

  let of_string s = Or_error.ok_exn (of_string_or_error s)
  let sexp_of_t t = Sexp.Atom (to_string t)
  let t_of_sexp sexp = of_string (string_of_sexp sexp)
end

include T

let zero = 0
let one = scale
let is_zero t = t = 0
let is_positive t = t > 0
let to_micro t = t

let of_int n =
  if n > max_micro / scale
  then Or_error.error_s [%message "quantity out of range" ~shares:(n : int)]
  else of_micro (n * scale)
;;

let to_fixed_decimal (type a : immediate) (module F : Fixed_decimal.S with type t = a) t =
  F.of_units (t * 100)
;;

let of_fixed_decimal (type a : immediate) (module F : Fixed_decimal.S with type t = a) v =
  let units = F.to_units v in
  if units mod 100 <> 0
  then
    Or_error.error_s [%message "more than six decimal places" ~quantity:(F.to_string v)]
  else of_micro (units / 100)
;;

let to_q t = Q.of_ints t scale

let of_q ~rounding q =
  let micro = Money.Rounding.round rounding (Q.mul q (Q.of_int scale)) in
  if Z.fits_int micro
  then of_micro (Z.to_int micro)
  else Or_error.error_s [%message "quantity out of range" ~shares:(Q.to_string q)]
;;

let add a b = a + b

let sub a b =
  if b > a
  then
    Or_error.error_s
      [%message "quantity would go negative" ~from:(to_string a) ~minus:(to_string b)]
  else Ok (a - b)
;;

let quickcheck_generator =
  Quickcheck.Generator.weighted_union
    [ 1., Quickcheck.Generator.return 0
    ; 3., Int.gen_incl 1 scale
    ; 3., Int.gen_incl 1 (1_000 * scale)
    ; 1., Int.gen_incl 1 1_000 |> Quickcheck.Generator.map ~f:(fun n -> n * scale)
    ]
;;

let quickcheck_observer = Int.quickcheck_observer
let quickcheck_shrinker = Int.quickcheck_shrinker

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
          let of_binable n = Or_error.ok_exn (of_micro n)
        end)
  end
end
