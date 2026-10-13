open! Core

module Stable = struct
  module V1 = struct
    type t =
      | Down
      | Up
      | Toward_zero
      | Away_from_zero
      | Half_even
      | Half_up
    [@@deriving bin_io, sexp, compare, equal, enumerate, quickcheck]
  end
end

include Stable.V1

let default = Half_even

let to_string t =
  match t with
  | Down -> "down"
  | Up -> "up"
  | Toward_zero -> "toward_zero"
  | Away_from_zero -> "away_from_zero"
  | Half_even -> "half_even"
  | Half_up -> "half_up"
;;

let of_string s =
  match List.find all ~f:(fun t -> String.Caseless.equal (to_string t) s) with
  | Some t -> t
  | None -> raise_s [%message "Rounding.of_string: unknown mode" s]
;;

let div t n d =
  if Z.equal d Z.zero then raise Division_by_zero;
  (* Work with a positive divisor so [Z.fdiv]'s remainder is in [0, d). *)
  let n, d = if Z.sign d < 0 then Z.neg n, Z.neg d else n, d in
  let q = Z.fdiv n d in
  let r = Z.sub n (Z.mul q d) in
  if Z.equal r Z.zero
  then q
  else (
    let succ = Z.succ q in
    match t with
    | Down -> q
    | Up -> succ
    | Toward_zero -> if Z.sign q < 0 then succ else q
    | Away_from_zero -> if Z.sign q < 0 then q else succ
    | Half_even | Half_up ->
      let c = Z.compare (Z.shift_left r 1) d in
      if c < 0
      then q
      else if c > 0
      then succ
      else (
        match t with
        | Half_even -> if Z.is_even q then q else succ
        (* The exact value is [q + 1/2]; it is negative exactly when [q < 0]. *)
        | _ -> if Z.sign q < 0 then q else succ))
;;

let round t q = div t (Q.num q) (Q.den q)
