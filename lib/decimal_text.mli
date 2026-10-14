(** Shared decimal layout for amounts, prices and rates. Internal to the library. *)

(** [to_string n ~digits] is [n / 10^digits] written with exactly [digits] fractional
    digits: [to_string 1234 ~digits:2 = "12.34"], [to_string (-5) ~digits:3 = "-0.005"]. *)
val to_string : Z.t -> digits:int -> string

(** [q_of_string s] reads a non-negative exact rational written as digits (["150"]), a
    decimal (["1.0845"]) or a fraction (["2000/2169"]). No sign, exponent or float syntax;
    [None] on anything else. *)
val q_of_string : string -> Q.t option

(** The decimal form when it terminates (["0.5"], ["150"]), the reduced fraction otherwise
    (["1/3"]). *)
val q_to_string : Q.t -> string
