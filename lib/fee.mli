(** A fee schedule: a fixed part plus basis points of the amount, clamped to an optional
    minimum and maximum. Basis points are exact rationals, so half a basis point or a
    third of one is represented without rounding; the fee itself is rounded once.

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

(** [create ?fixed ?bps ?bps_q ?min ?max currency]. [bps] takes whole basis points,
    [bps_q] any non-negative rational number of them ([Q.of_string "0.5"],
    [Q.of_ints 1 3]); both default to zero.

    Fails if any amount is in another currency or negative, if the basis points are
    negative, if both [bps] and [bps_q] are given, or if [min] exceeds [max]. *)
val create
  :  ?fixed:Amount.t
  -> ?bps:int
  -> ?bps_q:Q.t
  -> ?min:Amount.t
  -> ?max:Amount.t
  -> Currency.t
  -> t Or_error.t

val currency : t -> Currency.t
val fixed : t -> Amount.t
(** The basis points of the schedule, exactly. *)
val bps_q : t -> Q.t

(** The basis points as a whole number. Raises if the schedule has fractional basis
    points. *)
val bps : t -> int
[@@deprecated "[since 0.1.0] use [bps_q], which also handles fractional basis points"]

val min : t -> Amount.t option
val max : t -> Amount.t option

(** Fails if [amount] is in another currency. *)
val compute : t -> side:Side.t -> Amount.t -> Amount.t Or_error.t

(** JSON object with strings for every number:
    [{"currency":"EUR","fixed":"0.25","bps":"150","min":"1.00","max":null}]. Fractional
    basis points are written as a decimal (["0.5"]) or a fraction (["1/3"]). *)
include Ppx_yojson_conv_lib.Yojsonable.S with type t := t

(** Sexp is the same for every version: a record whose [bps] field is an atom such as
    [150], [0.5] or [1/3]. *)
module Stable : sig
  module V1 : sig
    (** The original bin_prot shape with whole basis points. Writing a schedule with
        fractional basis points raises; use [V2] for those. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end

  module V2 : sig
    (** Basis points as text, so fractional values round-trip. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
