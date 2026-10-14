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

type t =
  { currency : Currency.t
  ; fixed : Amount.t
  ; bps : Q.t
  ; min : Amount.t option
  ; max : Amount.t option
  }
[@@deriving compare, equal]

(* Basis points in text: ["150"], ["0.5"], ["1/3"]. A whole number prints exactly as the
   [int] did before fractions were allowed, so old sexps and JSON still read. *)
module Bps_text = struct
  type t = Q.t

  let to_string = Decimal_text.q_to_string

  let of_string s =
    match Decimal_text.q_of_string s with
    | Some q -> Ok q
    | None ->
      Or_error.error_s
        [%message "fee: bps must be a non-negative decimal or fraction" ~bps:s]
  ;;

  let sexp_of_t q = Sexp.Atom (to_string q)

  let t_of_sexp sexp =
    match sexp with
    | Sexp.Atom s ->
      (match of_string s with
       | Ok q -> q
       | Error e -> of_sexp_error (Error.to_string_hum e) sexp)
    | Sexp.List _ -> of_sexp_error "fee: bps must be an atom" sexp
  ;;
end

(* The derived converters do not validate; [validate] runs after every read. *)
module Sexp_repr = struct
  type t =
    { currency : Currency.t
    ; fixed : Amount.t
    ; bps : Bps_text.t
    ; min : Amount.t option
    ; max : Amount.t option
    }
  [@@deriving sexp]
end

let currency t = t.currency
let fixed t = t.fixed
let bps_q t = t.bps

let bps t =
  if Z.equal (Q.den t.bps) Z.one && Z.fits_int (Q.num t.bps)
  then Z.to_int (Q.num t.bps)
  else
    raise_s [%message "Fee.bps: fractional basis points" ~bps:(Bps_text.to_string t.bps)]
;;

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
    if Q.is_real t.bps && Q.sign t.bps >= 0
    then Ok ()
    else Or_error.error_s [%message "fee: negative bps" ~bps:(Q.to_string t.bps)]
  in
  match t.min, t.max with
  | Some lo, Some hi when Amount.(lo > hi) ->
    Or_error.error_s
      [%message
        "fee: min exceeds max" ~min:(Amount.to_string lo) ~max:(Amount.to_string hi)]
  | _ -> Ok t
;;

let create ?fixed ?bps ?bps_q ?min ?max currency =
  let%bind.Or_error bps =
    match bps, bps_q with
    | Some _, Some _ -> Or_error.error_s [%message "fee: give bps or bps_q, not both"]
    | Some bps, None -> Ok (Q.of_int bps)
    | None, Some q -> Ok q
    | None, None -> Ok Q.zero
  in
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
      Amount.mul_bps_q ~rounding:(Side.rounding side) (Amount.abs amount) ~bps:t.bps
    in
    let fee = Amount.add_exn t.fixed pct in
    let fee = Option.fold t.min ~init:fee ~f:Amount.max in
    let fee = Option.fold t.max ~init:fee ~f:Amount.min in
    Ok fee)
;;

let sexp_of_t { currency; fixed; bps; min; max } =
  Sexp_repr.sexp_of_t { currency; fixed; bps; min; max }
;;

let t_of_sexp sexp =
  let { Sexp_repr.currency; fixed; bps; min; max } = Sexp_repr.t_of_sexp sexp in
  match validate { currency; fixed; bps; min; max } with
  | Ok t -> t
  | Error e -> of_sexp_error (Error.to_string_hum e) sexp
;;

let yojson_of_t t =
  let amount a = `String (Amount.to_decimal_string a) in
  let opt = Option.value_map ~default:`Null ~f:amount in
  `Assoc
    [ "currency", Currency.yojson_of_t t.currency
    ; "fixed", amount t.fixed
    ; "bps", `String (Bps_text.to_string t.bps)
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
       ~bps_q:(Or_error.ok_exn (Bps_text.of_string (string "bps")))
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

    (* The original wire shape, with whole basis points. Kept byte for byte so data
       written before fractional basis points still reads. *)
    module Wire = struct
      type t =
        { currency : Currency.Stable.V1.t
        ; fixed : Amount.Stable.V1.t
        ; bps : int
        ; min : Amount.Stable.V1.t option
        ; max : Amount.Stable.V1.t option
        }
      [@@deriving bin_io]
    end

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Wire)
        (struct
          type nonrec t = t

          let to_binable (t : t) : Wire.t =
            { currency = t.currency
            ; fixed = t.fixed
            ; bps = bps t
            ; min = t.min
            ; max = t.max
            }
          ;;

          let of_binable ({ currency; fixed; bps; min; max } : Wire.t) =
            Or_error.ok_exn (validate { currency; fixed; bps = Q.of_int bps; min; max })
          ;;
        end)
  end

  module V2 = struct
    type nonrec t = t

    let compare = compare
    let equal = equal
    let sexp_of_t = sexp_of_t
    let t_of_sexp = t_of_sexp

    module Wire = struct
      type t =
        { currency : Currency.Stable.V1.t
        ; fixed : Amount.Stable.V1.t
        ; bps : string (** [Bps_text] form: ["150"], ["0.5"], ["1/3"] *)
        ; min : Amount.Stable.V1.t option
        ; max : Amount.Stable.V1.t option
        }
      [@@deriving bin_io]
    end

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Wire)
        (struct
          type nonrec t = t

          let to_binable (t : t) : Wire.t =
            { currency = t.currency
            ; fixed = t.fixed
            ; bps = Bps_text.to_string t.bps
            ; min = t.min
            ; max = t.max
            }
          ;;

          let of_binable ({ currency; fixed; bps; min; max } : Wire.t) =
            Or_error.ok_exn
              (let%bind.Or_error bps = Bps_text.of_string bps in
               validate { currency; fixed; bps; min; max })
          ;;
        end)
  end
end
