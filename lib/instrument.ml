open! Core

module Kind = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Stock
        | Etf
        | Fund
      [@@deriving bin_io, sexp, compare, equal, enumerate, quickcheck]
    end
  end

  include Stable.V1

  let to_string = function
    | Stock -> "stock"
    | Etf -> "etf"
    | Fund -> "fund"
  ;;

  let of_string_or_error s =
    match List.find all ~f:(fun k -> String.Caseless.equal (to_string k) s) with
    | Some k -> Ok k
    | None -> Or_error.error_s [%message "unknown instrument kind" ~kind:s]
  ;;
end

let max_name_length = 200

module Stable = struct
  module V1 = struct
    module Wire = struct
      type t =
        { symbol : Symbol.Stable.V1.t
        ; name : string
        ; kind : Kind.Stable.V1.t
        ; isin : Isin.Stable.V1.t option
        ; category : string
        ; description : string
        ; listing : Listing.Stable.V1.t
        }
      [@@deriving bin_io, sexp, compare, equal]
    end

    type t = Wire.t =
      { symbol : Symbol.t
      ; name : string
      ; kind : Kind.t
      ; isin : Isin.t option
      ; category : string
      ; description : string
      ; listing : Listing.t
      }
    [@@deriving compare, equal, sexp_of]

    let validate (t : Wire.t) =
      let name = String.strip t.name in
      if String.is_empty name
      then Or_error.error_s [%message "instrument name is empty" ~symbol:(t.symbol : Symbol.t)]
      else if String.length name > max_name_length
      then
        Or_error.error_s [%message "instrument name too long" ~symbol:(t.symbol : Symbol.t)]
      else Ok { t with name }
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

let create ~symbol ~name ~kind ?isin ?(category = "") ?(description = "") listing =
  validate { symbol; name; kind; isin; category; description; listing }
;;

let currency t = t.listing.currency
let with_status t status = { t with listing = Listing.with_status t.listing status }

let matches t ~query =
  let query = String.strip query in
  String.is_empty query
  || List.exists [ Symbol.to_string t.symbol; t.name; t.category ] ~f:(fun field ->
    String.Caseless.is_substring field ~substring:query)
;;
