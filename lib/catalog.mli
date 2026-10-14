(** The instruments a brokerage offers, keyed by symbol. An immutable value: adding an
    instrument returns a new catalog. *)

open! Core

type t [@@deriving sexp_of]

val empty : t

(** Fails when the symbol is already present. *)
val add : t -> Instrument.t -> t Or_error.t

(** [of_list] adds each instrument in order. *)
val of_list : Instrument.t list -> t Or_error.t

(** Replaces the instrument with the same symbol, or adds it. *)
val set : t -> Instrument.t -> t

val find : t -> Symbol.t -> Instrument.t option

(** [find], with an error naming the symbol when it is missing. *)
val find_or_error : t -> Symbol.t -> Instrument.t Or_error.t

(** Instruments matching [query] (see {!Instrument.matches}) and [kind], sorted by symbol. *)
val search : ?query:string -> ?kind:Instrument.Kind.t -> t -> Instrument.t list

(** Every instrument, sorted by symbol. *)
val to_list : t -> Instrument.t list

val length : t -> int
