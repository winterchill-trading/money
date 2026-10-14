(** An exchange rate: one unit of [base] costs [price] units of [quote], as quoted by
    [source] at [at].

    The price is an exact positive rational, so [inverse] loses nothing and a conversion
    rounds exactly once, at the end. Prices are written as decimals (["1.0845"]) or, when
    the decimal would not terminate (the inverse of 1.0845), as a fraction
    (["2000/2169"]). *)

open! Core

(** A validated rate. [t_of_sexp] validates like [create] and raises on failure. *)
type t [@@deriving sexp, compare, equal]

(** Fails unless [price] is positive and [base] differs from [quote]. *)
val create
  :  base:Currency.t
  -> quote:Currency.t
  -> price:Q.t
  -> at:Time_ns.t
  -> source:string
  -> t Or_error.t

(** Exact price parsing: ["1.0845"], ["150"], ["2000/2169"]. No exponents, no floats. *)
val price_of_string : string -> Q.t Or_error.t

(** The decimal form when it terminates, the reduced fraction otherwise. *)
val price_to_string : Q.t -> string

(** The currency being priced. *)
val base : t -> Currency.t

(** The currency the price is in. *)
val quote : t -> Currency.t

(** Units of [quote] per one unit of [base], always positive. *)
val price : t -> Q.t

(** When the rate was quoted. *)
val at : t -> Time_ns.t

(** Free text naming where the rate came from. *)
val source : t -> string

(** [convert t amount] turns an amount of [base] into [quote], rounding once to the quote
    currency's minor unit ([Half_even] by default). Fails if [amount] is not in [base]. *)
val convert : ?rounding:Rounding.t -> t -> Amount.t -> Amount.t Or_error.t

(** The same quote seen from the other side: [quote] in [base] at [1 / price]. *)
val inverse : t -> t

(** JSON object with every number as a string and the time in ISO 8601 UTC:
    [{"base":"EUR","quote":"USD","price":"1.0845","at":"...Z","source":"..."}].
    [t_of_yojson] validates like [create] and raises on failure. *)
include Ppx_yojson_conv_lib.Yojsonable.S with type t := t

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
