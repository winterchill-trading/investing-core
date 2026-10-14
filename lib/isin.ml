open! Core

let is_code_char c = Char.is_uppercase c || Char.is_digit c

let check_digit body =
  if String.length body <> 11 || not (String.for_all body ~f:is_code_char)
  then Or_error.error_s [%message "ISIN body must be eleven characters" body]
  else (
    (* Expand letters to two digits, then Luhn: double every second digit from the right,
       starting with the rightmost one, since the check digit will be appended after it. *)
    let digits =
      String.concat_map body ~f:(fun c ->
        if Char.is_digit c
        then String.of_char c
        else Int.to_string (Char.to_int c - Char.to_int 'A' + 10))
    in
    let n = String.length digits in
    let sum = ref 0 in
    for i = 0 to n - 1 do
      let d = Char.get_digit_exn digits.[n - 1 - i] in
      let d = if i % 2 = 0 then d * 2 else d in
      sum := !sum + (d / 10) + (d % 10)
    done;
    Ok (Char.of_int_exn (Char.to_int '0' + ((10 - (!sum % 10)) % 10))))
;;

let of_string_or_error s =
  let s = String.uppercase s in
  let open Or_error.Let_syntax in
  let%bind () =
    if String.length s = 12
       && Char.is_uppercase s.[0]
       && Char.is_uppercase s.[1]
       && String.for_all s ~f:is_code_char
       && Char.is_digit s.[11]
    then Ok ()
    else Or_error.error_s [%message "malformed ISIN" ~isin:s]
  in
  let%bind expected = check_digit (String.prefix s 11) in
  if Char.equal expected s.[11]
  then Ok s
  else Or_error.error_s [%message "ISIN check digit mismatch" ~isin:s (expected : char)]
;;

module T = struct
  type t = string [@@deriving compare, equal, hash]

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

let country_prefix t = String.prefix t 2

module Stable = struct
  module V1 = T
end
