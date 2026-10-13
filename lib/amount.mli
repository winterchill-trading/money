(** An exact amount of one currency, counted in minor units.

    The value is an arbitrary-precision integer of the currency's minor units (cents for
    EUR, satoshis for BTC, wei for ETH). Zarith stores integers that fit in 63 bits as
    plain immediate ints and only boxes larger ones, so EUR, BTC and USDC amounts stay
    machine ints while ETH amounts above about 4.6 ETH (4.6e18 wei) widen instead of
    overflowing or losing digits.

    There are no floats anywhere in this interface. The text form is the decimal value
    with exactly [Currency.exponent] fractional digits, a space and the currency:
    ["12.34 EUR"], ["0.00012345 BTC"], ["-5 JPY"].

    Arithmetic between two amounts requires the same currency and returns an error
    otherwise. *)

open! Core

type t [@@deriving sexp, compare, equal, hash]

(** Orders by currency, then by value. Useful for maps; to compare values check that the
    currencies match first. *)
include Comparable.S with type t := t

val currency : t -> Currency.t

(** {2 Construction} *)

val zero : Currency.t -> t
val of_minor_units : Currency.t -> Z.t -> t
val of_minor_units_int : Currency.t -> int -> t
val minor_units : t -> Z.t

(** [None] when the value does not fit in an [int]. *)
val minor_units_int : t -> int option

(** [of_decimal_string currency "12.34"]. Accepts an optional leading ['-'], at least one
    digit before an optional ['.'], and at most [Currency.exponent currency] fractional
    digits beyond which only zeros may follow. *)
val of_decimal_string : Currency.t -> string -> t Or_error.t

(** ["12.34"], always with exactly [Currency.exponent] fractional digits. *)
val to_decimal_string : t -> string

(** ["12.34 EUR"]. *)
val to_string : t -> string

(** Parses [to_string] output. *)
val of_string_or_error : string -> t Or_error.t

val of_string : string -> t

(** {2 Predicates} *)

val is_zero : t -> bool
val is_positive : t -> bool
val is_negative : t -> bool

(** -1, 0 or 1. *)
val sign : t -> int

(** {2 Arithmetic} *)

val neg : t -> t
val abs : t -> t

(** Fails when the currencies differ. *)
val add : t -> t -> t Or_error.t

val sub : t -> t -> t Or_error.t
val add_exn : t -> t -> t
val sub_exn : t -> t -> t

(** [sum currency ts] is [zero currency] for an empty list. Fails if any element has
    another currency. *)
val sum : Currency.t -> t list -> t Or_error.t

(** [compare_value a b] compares the values of two amounts of the same currency. *)
val compare_value : t -> t -> int Or_error.t

(** Exact multiplication by an integer. *)
val scale : t -> int -> t

(** [mul_ratio t q] is [t * q] rounded to a minor unit, [Half_even] by default. *)
val mul_ratio : ?rounding:Rounding.t -> t -> Q.t -> t

(** [mul_bps t ~bps] is [t * bps / 10_000], rounded like [mul_ratio]. *)
val mul_bps : ?rounding:Rounding.t -> t -> bps:int -> t

(** {2 Rationals and fixed-point values} *)

(** The value in major units, e.g. [1234/100] for ["12.34 EUR"]. *)
val to_q : t -> Q.t

(** [of_q currency q] rounds [q] major units to a minor unit, [Half_even] by default. *)
val of_q : ?rounding:Rounding.t -> Currency.t -> Q.t -> t

(** Converts to a [Fixed_decimal] value (8 fractional digits). Fails when digits would be
    lost (ETH with more than 8 significant decimals) or the value is out of range. *)
val to_fixed_decimal
  : ('a : immediate).
  (module Fixed_decimal.S with type t = 'a) -> t -> 'a Or_error.t

(** Fails when the value has more fractional digits than the currency allows, e.g. 0.001
    of EUR. *)
val of_fixed_decimal
  : ('a : immediate).
  (module Fixed_decimal.S with type t = 'a) -> Currency.t -> 'a -> t Or_error.t

(** {2 Serialization} *)

(** JSON object with string fields, never JSON numbers:
    [{"amount": "12.34", "currency": "EUR"}]. *)
include Ppx_yojson_conv_lib.Yojsonable.S with type t := t

(** Amounts over the built-in currencies, including ETH values wider than 63 bits. *)
val quickcheck_generator : t Quickcheck.Generator.t

val quickcheck_shrinker : t Quickcheck.Shrinker.t

(** Amounts of one currency. *)
val quickcheck_generator_in : Currency.t -> t Quickcheck.Generator.t

module Stable : sig
  module V1 : sig
    (** Bin_prot: the currency's text form and the minor units as a decimal string. Sexp:
        the text form. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
