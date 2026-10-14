open! Core

module Origin = struct
  module Stable = struct
    module V1 = struct
      type t =
        | Feed
        | Seed
        | Simulated
      [@@deriving bin_io, sexp, compare, equal, enumerate, quickcheck]
    end
  end

  include Stable.V1

  let rank = function
    | Feed -> 3
    | Seed -> 2
    | Simulated -> 1
  ;;

  let to_string = function
    | Feed -> "feed"
    | Seed -> "seed"
    | Simulated -> "simulated"
  ;;
end

module Stable = struct
  module V1 = struct
    type t =
      { symbol : Symbol.Stable.V1.t
      ; date : Date.Stable.V1.t
      ; close : Price.Stable.V1.t
      ; origin : Origin.Stable.V1.t
      }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

type t = Stable.V1.t =
  { symbol : Symbol.t
  ; date : Date.t
  ; close : Price.t
  ; origin : Origin.t
  }
[@@deriving sexp, compare, equal, quickcheck]

let preferred a b = if Origin.rank a.origin > Origin.rank b.origin then a else b
