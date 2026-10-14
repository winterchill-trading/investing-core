open! Core

module Stable = struct
  module V1 = struct
    module Wire = struct
      type t =
        { minimum : Money.Amount.Stable.V1.t
        ; maximum : Money.Amount.Stable.V1.t
        }
      [@@deriving bin_io, sexp, compare, equal]
    end

    type t = Wire.t =
      { minimum : Money.Amount.t
      ; maximum : Money.Amount.t
      }
    [@@deriving compare, equal, sexp_of]

    let validate (t : t) =
      let module A = Money.Amount in
      if not (Money.Currency.equal (A.currency t.minimum) (A.currency t.maximum))
      then Or_error.error_s [%message "order limits in two currencies" ~limits:(t : t)]
      else if not (A.is_positive t.minimum && A.( <= ) t.minimum t.maximum)
      then Or_error.error_s [%message "order limits out of order" ~limits:(t : t)]
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

let create ~minimum ~maximum = validate { minimum; maximum }

let default currency =
  let major n = Money.Amount.of_q currency (Q.of_int n) in
  { minimum = major 1; maximum = major 1_000_000 }
;;

let currency t = Money.Amount.currency t.minimum
