(** Order identifiers, chosen by the caller (a UUID, a database key). The id appears in
    ledger idempotency keys and hold ids, so it uses the ledger's id alphabet
    ([A-Z a-z 0-9 _ - . : / @ +]) and is at most 100 characters, leaving room for the
    prefixes and suffixes {!Booking} adds. *)

open! Core

include Ledger.Validated_id.S

(** 100. *)
val max_length : int
