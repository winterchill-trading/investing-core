open! Core

let max_length = 12

let valid_char = function
  | 'A' .. 'Z' | '0' .. '9' | '.' | '-' -> true
  | _ -> false
;;

let of_string_or_error s =
  let s = String.uppercase s in
  let len = String.length s in
  if len = 0
  then Or_error.error_string "empty symbol"
  else if len > max_length
  then Or_error.error_s [%message "symbol too long" s (max_length : int)]
  else if not (Char.is_alphanum s.[0])
  then Or_error.error_s [%message "symbol must start with a letter or digit" s]
  else (
    match String.find s ~f:(Fn.non valid_char) with
    | Some c -> Or_error.error_s [%message "invalid character in symbol" s (c : char)]
    | None -> Ok s)
;;

module T = struct
  type t = string [@@deriving compare, equal, hash]

  let module_name = "Investing_core.Symbol"
  let to_string t = t
  let of_string s = Or_error.ok_exn (of_string_or_error s)
  let sexp_of_t = sexp_of_string
  let t_of_sexp sexp = of_string (string_of_sexp sexp)

  include
    Binable.Of_binable_without_uuid [@alert "-legacy"]
      (String)
      (struct
        type t = string

        let to_binable = Fn.id
        let of_binable = of_string
      end)
end

include T
include Identifiable.Make (T)

let quickcheck_generator =
  let open Quickcheck.Generator.Let_syntax in
  let%bind first = Quickcheck.Generator.of_list (String.to_list "ABCXYZ09") in
  let%bind len = Int.gen_incl 0 (max_length - 1) in
  let%map rest =
    String.gen_with_length len (Quickcheck.Generator.of_list (String.to_list "ABZ19.-"))
  in
  String.of_char first ^ rest
;;

let quickcheck_observer = String.quickcheck_observer
let quickcheck_shrinker : t Quickcheck.Shrinker.t = Quickcheck.Shrinker.empty ()

module Stable = struct
  module V1 = T
end
