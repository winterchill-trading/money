(** A fee schedule: a fixed part plus basis points of the amount, clamped to an optional
    minimum and maximum.

    [compute] charges on the absolute value of the amount and always returns a
    non-negative fee in the schedule's currency. The percentage part is rounded in our
    favour: [Down] for a fee we pay ([Payable]), [Up] for a fee we charge ([Receivable]).
    The minimum and maximum bound the total, fixed part included. *)

open! Core

module Side : sig
  type t =
    | Payable (** we pay it: round down *)
    | Receivable (** we charge it: round up *)
  [@@deriving sexp, compare, equal, enumerate, quickcheck]

  val rounding : t -> Rounding.t
end

type t [@@deriving sexp, compare, equal]

(** Fails if any amount is in another currency or negative, if [bps] is negative, or if
    [min] exceeds [max]. *)
val create
  :  ?fixed:Amount.t
  -> ?bps:int
  -> ?min:Amount.t
  -> ?max:Amount.t
  -> Currency.t
  -> t Or_error.t

val currency : t -> Currency.t
val fixed : t -> Amount.t
val bps : t -> int
val min : t -> Amount.t option
val max : t -> Amount.t option

(** Fails if [amount] is in another currency. *)
val compute : t -> side:Side.t -> Amount.t -> Amount.t Or_error.t

(** JSON object with strings for every number:
    [{"currency":"EUR","fixed":"0.25","bps":"150","min":"1.00","max":null}]. *)
include Ppx_yojson_conv_lib.Yojsonable.S with type t := t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
