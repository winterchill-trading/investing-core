open! Core

module Stable = struct
  module V1 = struct
    type t =
      | Buy
      | Sell
    [@@deriving bin_io, sexp, compare, equal, hash, enumerate, quickcheck]
  end
end

include Stable.V1

let to_string = function
  | Buy -> "buy"
  | Sell -> "sell"
;;
