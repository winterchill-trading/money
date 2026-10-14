(** How a quotient is turned into a whole number of minor units.

    [Down] and [Up] round toward negative and positive infinity. For a fee you pay, round
    [Down]; for a fee you charge, round [Up], so rounding never works against you. The
    default for everything else is [Half_even] (banker's rounding), which has no bias over
    many operations. *)

open! Core

type t =
  | Down (** toward negative infinity (floor) *)
  | Up (** toward positive infinity (ceiling) *)
  | Toward_zero (** truncate *)
  | Away_from_zero
  | Half_even (** nearest, ties to the even neighbour *)
  | Half_up (** nearest, ties away from zero *)
[@@deriving sexp, compare, equal, enumerate, quickcheck]

(** [Half_even]. *)
val default : t

(** Lowercase name, e.g. ["half_even"]. *)
val to_string : t -> string

(** Accepts [to_string] output and the constructor names, ignoring case. Raises on any
    other string. *)
val of_string : string -> t

(** [div t n d] is [n / d] rounded with [t]. Raises [Division_by_zero] when [d] is zero. *)
val div : t -> Z.t -> Z.t -> Z.t

(** [round t q] is the rational [q] rounded to an integer with [t]. *)
val round : t -> Q.t -> Z.t

(** Versioned serializers whose bin_prot shape never changes. *)
module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
