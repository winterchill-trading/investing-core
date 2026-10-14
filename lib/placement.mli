(** Checks an order request against the instrument, the latest price and the customer's
    position, and sizes it. Pure: nothing is reserved or booked here; the caller places
    the hold ({!Booking.buy_placed}) or reserves the shares ({!Position.reserve}) with
    what the {!Plan.t} says, then creates the {!Order.t}.

    Rules, in the order they are checked:

    + the listing must accept orders;
    + an amount must be in the instrument's currency and positive, a quantity positive;
    + a price no older than the staleness limit must exist ({!Price_history.quote});
    + money becomes shares rounded down to a millionth; a buy's estimated cost rounds up
      and a sale's estimated proceeds round down;
    + a sell may use only shares that are not already reserved by another sell;
    + the estimated value must be within the {!Order_limits} (a sale of everything
      available is exempt from the minimum). *)

open! Core

module Refusal : sig
  type t =
    | Not_tradable of
        { symbol : Symbol.t
        ; status : Listing.Status.t
        }
    | Currency_mismatch of
        { expected : Money.Currency.t
        ; got : Money.Currency.t
        }
    | Not_positive (** a zero or negative amount, or a zero quantity *)
    | Price_unavailable of Price_history.Unavailable.t
    | Too_small_for_one_unit
    (** the amount does not buy or sell a millionth of a share *)
    | No_holdings of { symbol : Symbol.t } (** nothing held at all *)
    | Holdings_reserved of { symbol : Symbol.t }
    (** shares are held, but pending sells have reserved all of them *)
    | Exceeds_holdings of { available : Quantity.t }
    | Below_minimum of { minimum : Money.Amount.t }
    | Above_maximum of { maximum : Money.Amount.t }
  [@@deriving sexp, compare, equal]

  (** A stable snake_case code for each case, e.g. ["price_unavailable"], for API errors
      and message catalogues. *)
  val code : t -> string
end

module Plan : sig
  type t =
    { side : Side.t
    ; quantity : Quantity.t (** the exact quantity sent to the broker *)
    ; quote : Price_history.Quote.t (** the price the estimate used *)
    ; estimated_gross : Money.Amount.t
    (** [quantity * price]: rounded up for a buy (cost), down for a sale (proceeds) *)
    ; hold : Money.Amount.t option
    (** buys: cash to hold, the requested amount or the estimated cost *)
    ; reserve : Quantity.t option (** sells: shares to reserve *)
    }
  [@@deriving sexp_of]
end

val plan
  :  ?staleness:Staleness.t
  -> ?limits:Order_limits.t (** default {!Order_limits.default} in the instrument's currency *)
  -> instrument:Instrument.t
  -> prices:Price_history.t
  -> today:Date.t
  -> position:Position.t option (** [None] when nothing has ever been held *)
  -> Order_request.t
  -> (Plan.t, Refusal.t) Result.t
