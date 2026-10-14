(** Ledger entries for the cash legs of orders. Pure: each function takes the current
    {!Ledger.Balances.t} and returns the entries to book, already checked against it, so
    the caller appends them to its journal (or drops them). Shares are not in the ledger;
    {!Position} tracks them.

    - Buy placed: a hold of [estimate.hold] on the customer's cash account
      ({!Ledger.Hold}), so the cash cannot be spent twice while the order is pending.
    - Buy filled: one entry captures the fill's cost from the hold to the brokerage
      settlement account and returns the rest of the hold. A cost above the hold (the
      price rose since the estimate) is one over-capture entry taking the difference from
      the available balance; when the account cannot pay it the ledger refuses the entry,
      and the caller rejects the order and releases the hold instead.
    - Buy rejected or cancelled: the hold is released.
    - Sell filled: the proceeds move from the brokerage settlement account to the
      customer. A sell places no hold; nothing is booked when it is rejected or
      cancelled.

    The brokerage settlement account is a clearing account that may go negative: after a
    buy it shows what is owed to the broker, after a sale what the broker owes. It
    returns to zero when the broker settles. Every entry's reference is the order id,
    and its idempotency key is [order:<id>:<leg>] with leg [hold], [settlement],
    [release] or [proceeds], so booking the same transition twice is caught by the
    journal. *)

open! Core

module Chart : sig
  type t = { brokerage_settlement : Money.Currency.t -> Ledger.Account_id.t }

  (** [clearing:brokerage/<currency>]. *)
  val default : t

  (** The accounts the chart names for these currencies, ready to open. *)
  val accounts : t -> currencies:Money.Currency.t list -> Ledger.Account.t list
end

(** [order:<id>]. *)
val hold_id : Order_id.t -> Ledger.Hold_id.t Or_error.t

(** [order:<id>:<leg>]. *)
val idempotency_key : Order_id.t -> leg:string -> Ledger.Idempotency_key.t Or_error.t

(** The hold for a pending buy. Fails for a sell or an order with no hold amount. *)
val buy_placed : Ledger.Balances.t -> Order.t -> at:Time_ns.t -> Ledger.Entry.t list Or_error.t

(** The entries for an order that just moved from [before] to [after] (as returned by
    {!Order.apply}): settlement or proceeds on a fill, a release for a buy that was
    rejected or cancelled, nothing otherwise. [at] is the ledger time of the booking. *)
val transition
  :  Chart.t
  -> Ledger.Balances.t
  -> before:Order.t
  -> after:Order.t
  -> at:Time_ns.t
  -> Ledger.Entry.t list Or_error.t

(** Applies entries to balances in order, as a journal would. *)
val apply : Ledger.Balances.t -> Ledger.Entry.t list -> Ledger.Balances.t Or_error.t
