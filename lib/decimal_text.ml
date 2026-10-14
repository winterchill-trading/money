open! Core

let to_string n ~digits:k =
  let s = Z.to_string (Z.abs n) in
  let body =
    if k = 0
    then s
    else (
      let s =
        if String.length s <= k then String.make (k + 1 - String.length s) '0' ^ s else s
      in
      let len = String.length s in
      String.sub s ~pos:0 ~len:(len - k) ^ "." ^ String.sub s ~pos:(len - k) ~len:k)
  in
  if Z.sign n < 0 then "-" ^ body else body
;;

let q_of_string s =
  let digits x = (not (String.is_empty x)) && String.for_all x ~f:Char.is_digit in
  match String.lsplit2 s ~on:'/' with
  | Some (n, d) ->
    if digits n && digits d && not (String.for_all d ~f:(Char.equal '0'))
    then Some (Q.make (Z.of_string n) (Z.of_string d))
    else None
  | None ->
    (match String.lsplit2 s ~on:'.' with
     | None -> if digits s then Some (Q.of_bigint (Z.of_string s)) else None
     | Some (i, f) ->
       if digits i && digits f
       then Some (Q.make (Z.of_string (i ^ f)) (Z.pow (Z.of_int 10) (String.length f)))
       else None)
;;

(* A reduced fraction has a terminating decimal exactly when its denominator is
   [2^a * 5^b]; it then needs [max a b] fractional digits. *)
let q_to_string q =
  let rec strip d p n =
    if Z.(equal (rem d p) zero) then strip Z.(d / p) p (n + 1) else d, n
  in
  let num = Q.num q
  and den = Q.den q in
  let rest, twos = strip den (Z.of_int 2) 0 in
  let rest, fives = strip rest (Z.of_int 5) 0 in
  if not (Z.equal rest Z.one)
  then Z.to_string num ^ "/" ^ Z.to_string den
  else (
    let k = Int.max twos fives in
    let units = Z.(num * pow (of_int 10) k / den) in
    to_string units ~digits:k)
;;
