open! Core

module Status = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Active
        | Halted
        | Delisted
      [@@deriving bin_io, sexp, compare, equal, enumerate, quickcheck]
    end
  end

  include Stable.V1
end

let check_exchange exchange =
  if String.length exchange = 4
     && String.for_all exchange ~f:(fun c -> Char.is_uppercase c || Char.is_digit c)
  then Ok ()
  else Or_error.error_s [%message "exchange must be a four-character MIC" exchange]
;;

module Stable = struct
  module V1 = struct
    module Wire = struct
      type t =
        { exchange : string
        ; currency : Money.Currency.Stable.V1.t
        ; status : Status.Stable.V1.t
        }
      [@@deriving bin_io, sexp, compare, equal]
    end

    type t = Wire.t =
      { exchange : string
      ; currency : Money.Currency.t
      ; status : Status.t
      }
    [@@deriving compare, equal, sexp_of]

    let validate (t : Wire.t) = Or_error.map (check_exchange t.exchange) ~f:(fun () -> t)

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

let create ~exchange ~currency ?(status = Status.Active) () =
  validate { exchange; currency; status }
;;

let with_status t status = { t with status }

let accepts_orders t =
  match t.status with
  | Active -> true
  | Halted | Delisted -> false
;;
