open! Core

module T = struct
  type t =
    { currency : Currency.t
    ; units : Z.t
    }

  let compare a b =
    match Currency.compare a.currency b.currency with
    | 0 -> Z.compare a.units b.units
    | c -> c
  ;;

  let hash_fold_t state t =
    Int.hash_fold_t (Currency.hash_fold_t state t.currency) (Z.hash t.units)
  ;;

  let hash t = Hash.get_hash_value (hash_fold_t (Hash.create ()) t)
end

include T

let currency t = t.currency
let zero currency = { currency; units = Z.zero }
let of_minor_units currency units = { currency; units }
let of_minor_units_int currency n = { currency; units = Z.of_int n }
let minor_units t = t.units
let minor_units_int t = if Z.fits_int t.units then Some (Z.to_int t.units) else None
let pow10 n = Z.pow (Z.of_int 10) n

let to_decimal_string t =
  Decimal_text.to_string t.units ~digits:(Currency.exponent t.currency)
;;

let to_string t = to_decimal_string t ^ " " ^ Currency.to_string t.currency

let of_decimal_string currency s =
  let fail reason = Or_error.error_s [%message reason ~input:s] in
  let e = Currency.exponent currency in
  let negative, rest =
    match String.chop_prefix s ~prefix:"-" with
    | Some rest -> true, rest
    | None -> false, s
  in
  let int_part, frac =
    match String.lsplit2 rest ~on:'.' with
    | Some (i, f) -> i, Some f
    | None -> rest, None
  in
  let all_digits x = String.for_all x ~f:Char.is_digit in
  if String.is_empty int_part || not (all_digits int_part)
  then fail "amount: expected digits before the decimal point"
  else (
    match frac with
    | Some f when String.is_empty f || not (all_digits f) ->
      fail "amount: expected digits after the decimal point"
    | _ ->
      let frac = Option.value frac ~default:"" in
      let kept, extra =
        if String.length frac <= e
        then frac, ""
        else String.sub frac ~pos:0 ~len:e, String.drop_prefix frac e
      in
      if not (String.for_all extra ~f:(Char.equal '0'))
      then fail "amount: more fractional digits than the currency has"
      else (
        let padded = kept ^ String.make (e - String.length kept) '0' in
        let units = Z.of_string (int_part ^ padded) in
        Ok { currency; units = (if negative then Z.neg units else units) }))
;;

let of_string_or_error s =
  match String.lsplit2 s ~on:' ' with
  | None -> Or_error.error_s [%message "amount: expected \"<decimal> <currency>\"" s]
  | Some (value, code) ->
    let%bind.Or_error currency = Currency.of_string_or_error code in
    of_decimal_string currency value
;;

let of_string s = Or_error.ok_exn (of_string_or_error s)
let sexp_of_t t = Sexp.Atom (to_string t)

let t_of_sexp sexp =
  match sexp with
  | Sexp.Atom s ->
    (match of_string_or_error s with
     | Ok t -> t
     | Error e -> of_sexp_error (Error.to_string_hum e) sexp)
  | Sexp.List _ -> of_sexp_error "amount: expected an atom" sexp
;;

let is_positive t = Int.(Z.sign t.units > 0)
let is_negative t = Int.(Z.sign t.units < 0)
let is_zero t = Z.equal t.units Z.zero
let sign t = Z.sign t.units
let neg t = { t with units = Z.neg t.units }
let abs t = { t with units = Z.abs t.units }

let same_currency op a b =
  if Currency.equal a.currency b.currency
  then Ok ()
  else
    Or_error.error_s
      [%message
        "currency mismatch" op ~_:(to_string a : string) ~_:(to_string b : string)]
;;

let add a b =
  let%map.Or_error () = same_currency "add" a b in
  { a with units = Z.add a.units b.units }
;;

let sub a b =
  let%map.Or_error () = same_currency "sub" a b in
  { a with units = Z.sub a.units b.units }
;;

let add_exn a b = Or_error.ok_exn (add a b)
let sub_exn a b = Or_error.ok_exn (sub a b)
let sum currency ts = List.fold_result ts ~init:(zero currency) ~f:add

let compare_value a b =
  let%map.Or_error () = same_currency "compare" a b in
  Z.compare a.units b.units
;;

let scale t n = { t with units = Z.mul t.units (Z.of_int n) }

let mul_ratio ?(rounding = Rounding.default) t q =
  { t with units = Rounding.div rounding (Z.mul t.units (Q.num q)) (Q.den q) }
;;

let mul_bps ?rounding t ~bps =
  mul_ratio ?rounding t (Q.make (Z.of_int bps) (Z.of_int 10_000))
;;

let to_q t = Q.make t.units (pow10 (Currency.exponent t.currency))

let of_q ?(rounding = Rounding.default) currency q =
  { currency
  ; units =
      Rounding.round rounding (Q.mul q (Q.of_bigint (pow10 (Currency.exponent currency))))
  }
;;

let fixed_decimal_digits = 8

let to_fixed_decimal (type a : immediate) (module F : Fixed_decimal.S with type t = a) t =
  let e = Currency.exponent t.currency in
  let units =
    if e <= fixed_decimal_digits
    then Ok (Z.mul t.units (pow10 (fixed_decimal_digits - e)))
    else (
      let q, r = Z.div_rem t.units (pow10 (e - fixed_decimal_digits)) in
      if Z.equal r Z.zero
      then Ok q
      else
        Or_error.error_s
          [%message "amount has more than 8 fractional digits" ~_:(to_string t : string)])
  in
  let%bind.Or_error units in
  if Z.fits_int units
  then Ok (F.of_units (Z.to_int units))
  else
    Or_error.error_s
      [%message "amount out of fixed-decimal range" ~_:(to_string t : string)]
;;

let of_fixed_decimal
  (type a : immediate)
  (module F : Fixed_decimal.S with type t = a)
  currency
  (x : a)
  =
  let e = Currency.exponent currency in
  let fd = Z.of_int (F.to_units x) in
  if e >= fixed_decimal_digits
  then Ok { currency; units = Z.mul fd (pow10 (e - fixed_decimal_digits)) }
  else (
    let q, r = Z.div_rem fd (pow10 (fixed_decimal_digits - e)) in
    if Z.equal r Z.zero
    then Ok { currency; units = q }
    else
      Or_error.error_s
        [%message
          "value has more fractional digits than the currency"
            ~value:(F.to_string x)
            ~currency:(Currency.to_string currency)])
;;

let yojson_of_t t =
  `Assoc
    [ "amount", `String (to_decimal_string t)
    ; "currency", `String (Currency.to_string t.currency)
    ]
;;

let t_of_yojson json =
  match json with
  | `Assoc fields ->
    (match
       ( List.Assoc.find fields ~equal:String.equal "amount"
       , List.Assoc.find fields ~equal:String.equal "currency" )
     with
     | Some (`String amount), Some (`String code) ->
       Or_error.ok_exn
         (let%bind.Or_error currency = Currency.of_string_or_error code in
          of_decimal_string currency amount)
     | _ -> raise_s [%message "amount: expected string fields amount and currency"])
  | _ -> raise_s [%message "amount: expected a JSON object"]
;;

let generator_currencies =
  Currency.[ eur; usd; jpy; btc; btc_lightning; eth; usdc; usdt_tron ]
;;

let quickcheck_generator_in currency =
  let open Quickcheck.Generator.Let_syntax in
  (* Mostly ints, sometimes products of two ints so ETH-sized values exceed 63 bits. *)
  let%map units =
    Quickcheck.Generator.weighted_union
      [ 4.0, Int.quickcheck_generator >>| Z.of_int
      ; ( 1.0
        , let%map a = Int.quickcheck_generator
          and b = Int.quickcheck_generator in
          Z.mul (Z.of_int a) (Z.of_int b) )
      ]
  in
  { currency; units }
;;

let quickcheck_generator =
  Quickcheck.Generator.bind
    (Quickcheck.Generator.of_list generator_currencies)
    ~f:quickcheck_generator_in
;;

let quickcheck_shrinker = Quickcheck.Shrinker.empty ()

(* Last, so its [<] and [=] on [t] do not shadow the int ones above. *)
include Comparable.Make (struct
    include T

    let sexp_of_t = sexp_of_t
    let t_of_sexp = t_of_sexp
  end)

module Stable = struct
  module V1 = struct
    type nonrec t = t

    let compare = compare
    let equal = equal
    let sexp_of_t = sexp_of_t
    let t_of_sexp = t_of_sexp

    module Wire = struct
      (* Minor units as a decimal string: wide values need no special encoding and the
         bytes stay readable in a hex dump. *)
      type t =
        { currency : Currency.Stable.V1.t
        ; minor_units : string
        }
      [@@deriving bin_io]
    end

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Wire)
        (struct
          type nonrec t = t

          let to_binable (t : t) : Wire.t =
            { currency = t.currency; minor_units = Z.to_string t.units }
          ;;

          let of_binable (w : Wire.t) : t =
            { currency = w.currency; units = Z.of_string w.minor_units }
          ;;
        end)
  end
end
