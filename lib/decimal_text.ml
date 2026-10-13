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
