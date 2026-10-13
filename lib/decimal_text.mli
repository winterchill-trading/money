(** Shared decimal layout for amounts and prices. *)

(** [to_string n ~digits] is [n / 10^digits] written with exactly [digits] fractional
    digits: [to_string 1234 ~digits:2 = "12.34"], [to_string (-5) ~digits:3 = "-0.005"]. *)
val to_string : Z.t -> digits:int -> string
