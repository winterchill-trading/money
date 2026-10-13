open! Core

module Side = struct
  type t =
    | Payable
    | Receivable
  [@@deriving sexp, compare, equal, enumerate, quickcheck]

  let rounding = function
    | Payable -> Rounding.Down
    | Receivable -> Rounding.Up
  ;;
end

(* The derived converters do not validate; [Stable.V1] below wraps them. *)
module Repr = struct
  type t =
    { currency : Currency.Stable.V1.t
    ; fixed : Amount.Stable.V1.t
    ; bps : int
    ; min : Amount.Stable.V1.t option
    ; max : Amount.Stable.V1.t option
    }
  [@@deriving bin_io, sexp, compare, equal]
end

type t = Repr.t =
  { currency : Currency.t
  ; fixed : Amount.t
  ; bps : int
  ; min : Amount.t option
  ; max : Amount.t option
  }
[@@deriving compare, equal]

let currency t = t.currency
let fixed t = t.fixed
let bps t = t.bps
let min t = t.min
let max t = t.max

let validate t =
  let open Or_error.Let_syntax in
  let check_amount name a =
    if not (Currency.equal (Amount.currency a) t.currency)
    then
      Or_error.error_s
        [%message
          "fee: amount in another currency"
            name
            ~amount:(Amount.to_string a)
            ~currency:(Currency.to_string t.currency)]
    else if Amount.is_negative a
    then
      Or_error.error_s [%message "fee: negative amount" name ~amount:(Amount.to_string a)]
    else Ok ()
  in
  let%bind () = check_amount "fixed" t.fixed in
  let%bind () = Option.value_map t.min ~default:(Ok ()) ~f:(check_amount "min") in
  let%bind () = Option.value_map t.max ~default:(Ok ()) ~f:(check_amount "max") in
  let%bind () =
    if t.bps >= 0
    then Ok ()
    else Or_error.error_s [%message "fee: negative bps" (t.bps : int)]
  in
  match t.min, t.max with
  | Some lo, Some hi when Amount.(lo > hi) ->
    Or_error.error_s
      [%message
        "fee: min exceeds max" ~min:(Amount.to_string lo) ~max:(Amount.to_string hi)]
  | _ -> Ok t
;;

let create ?fixed ?(bps = 0) ?min ?max currency =
  validate
    { currency
    ; fixed = Option.value fixed ~default:(Amount.zero currency)
    ; bps
    ; min
    ; max
    }
;;

let compute t ~side amount =
  if not (Currency.equal (Amount.currency amount) t.currency)
  then
    Or_error.error_s
      [%message
        "fee: amount in another currency"
          ~amount:(Amount.to_string amount)
          ~currency:(Currency.to_string t.currency)]
  else (
    let pct =
      Amount.mul_bps ~rounding:(Side.rounding side) (Amount.abs amount) ~bps:t.bps
    in
    let fee = Amount.add_exn t.fixed pct in
    let fee = Option.fold t.min ~init:fee ~f:Amount.max in
    let fee = Option.fold t.max ~init:fee ~f:Amount.min in
    Ok fee)
;;

let sexp_of_t = Repr.sexp_of_t

let t_of_sexp sexp =
  match validate (Repr.t_of_sexp sexp) with
  | Ok t -> t
  | Error e -> of_sexp_error (Error.to_string_hum e) sexp
;;

let yojson_of_t t =
  let amount a = `String (Amount.to_decimal_string a) in
  let opt = Option.value_map ~default:`Null ~f:amount in
  `Assoc
    [ "currency", Currency.yojson_of_t t.currency
    ; "fixed", amount t.fixed
    ; "bps", `String (Int.to_string t.bps)
    ; "min", opt t.min
    ; "max", opt t.max
    ]
;;

let t_of_yojson json =
  let fields =
    match json with
    | `Assoc fields -> fields
    | _ -> raise_s [%message "fee: expected a JSON object"]
  in
  let field name = List.Assoc.find fields ~equal:String.equal name in
  let string name =
    match field name with
    | Some (`String s) -> s
    | _ -> raise_s [%message "fee: expected a string field" name]
  in
  let currency = Currency.of_string (string "currency") in
  let amount s = Or_error.ok_exn (Amount.of_decimal_string currency s) in
  let opt name =
    match field name with
    | None | Some `Null -> None
    | Some (`String s) -> Some (amount s)
    | Some _ -> raise_s [%message "fee: expected a string or null" name]
  in
  Or_error.ok_exn
    (create
       currency
       ~fixed:(amount (string "fixed"))
       ~bps:(Int.of_string (string "bps"))
       ?min:(opt "min")
       ?max:(opt "max"))
;;

module Stable = struct
  module V1 = struct
    type nonrec t = t

    let compare = compare
    let equal = equal
    let sexp_of_t = sexp_of_t
    let t_of_sexp = t_of_sexp

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Repr)
        (struct
          type nonrec t = t

          let to_binable = Fn.id
          let of_binable t = Or_error.ok_exn (validate t)
        end)
  end
end
