open! Core

type t =
  { base : Currency.t
  ; quote : Currency.t
  ; price : Q.t
  ; at : Time_ns.t
  ; source : string
  }

let base t = t.base
let quote t = t.quote
let price t = t.price
let at t = t.at
let source t = t.source

let create ~base ~quote ~price ~at ~source =
  if Currency.equal base quote
  then Or_error.error_s [%message "rate: base and quote are the same" (base : Currency.t)]
  else if Q.sign price <= 0 || not (Q.is_real price)
  then
    Or_error.error_s [%message "rate: price must be positive" ~price:(Q.to_string price)]
  else Ok { base; quote; price; at; source }
;;

let price_of_string s =
  let fail () = Or_error.error_s [%message "rate: malformed price" s] in
  let digits x = (not (String.is_empty x)) && String.for_all x ~f:Char.is_digit in
  match String.lsplit2 s ~on:'/' with
  | Some (n, d) ->
    if digits n && digits d && not (String.for_all d ~f:(Char.equal '0'))
    then Ok (Q.make (Z.of_string n) (Z.of_string d))
    else fail ()
  | None ->
    (match String.lsplit2 s ~on:'.' with
     | None -> if digits s then Ok (Q.of_bigint (Z.of_string s)) else fail ()
     | Some (i, f) ->
       if digits i && digits f
       then Ok (Q.make (Z.of_string (i ^ f)) (Z.pow (Z.of_int 10) (String.length f)))
       else fail ())
;;

(* A reduced fraction has a terminating decimal exactly when its denominator is
   [2^a * 5^b]; it then needs [max a b] fractional digits. *)
let price_to_string q =
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
    Decimal_text.to_string units ~digits:k)
;;

let convert ?rounding t amount =
  if not (Currency.equal (Amount.currency amount) t.base)
  then
    Or_error.error_s
      [%message
        "rate: amount is not in the base currency"
          ~amount:(Amount.to_string amount)
          ~base:(Currency.to_string t.base)]
  else Ok (Amount.of_q ?rounding t.quote (Q.mul (Amount.to_q amount) t.price))
;;

let inverse t = { t with base = t.quote; quote = t.base; price = Q.inv t.price }

module Sexpable = struct
  type t =
    { base : Currency.t
    ; quote : Currency.t
    ; price : string
    ; at : Time_ns.Alternate_sexp.t
    ; source : string
    }
  [@@deriving sexp]
end

let to_sexpable (t : t) : Sexpable.t =
  { base = t.base
  ; quote = t.quote
  ; price = price_to_string t.price
  ; at = t.at
  ; source = t.source
  }
;;

let of_parts ~base ~quote ~price ~at ~source =
  let%bind.Or_error price = price_of_string price in
  create ~base ~quote ~price ~at ~source
;;

let sexp_of_t t = Sexpable.sexp_of_t (to_sexpable t)

let t_of_sexp sexp =
  let { Sexpable.base; quote; price; at; source } = Sexpable.t_of_sexp sexp in
  match of_parts ~base ~quote ~price ~at ~source with
  | Ok t -> t
  | Error e -> of_sexp_error (Error.to_string_hum e) sexp
;;

let compare a b =
  Comparable.lexicographic
    [ (fun a b -> Currency.compare a.base b.base)
    ; (fun a b -> Currency.compare a.quote b.quote)
    ; (fun a b -> Q.compare a.price b.price)
    ; (fun a b -> Time_ns.compare a.at b.at)
    ; (fun a b -> String.compare a.source b.source)
    ]
    a
    b
;;

let equal a b = compare a b = 0

let yojson_of_t t =
  `Assoc
    [ "base", Currency.yojson_of_t t.base
    ; "quote", Currency.yojson_of_t t.quote
    ; "price", `String (price_to_string t.price)
    ; "at", `String (Time_ns.to_string_iso8601_basic t.at ~zone:Time_float.Zone.utc)
    ; "source", `String t.source
    ]
;;

let t_of_yojson json =
  let field name =
    match json with
    | `Assoc fields ->
      (match List.Assoc.find fields ~equal:String.equal name with
       | Some (`String s) -> s
       | _ -> raise_s [%message "rate: expected a string field" name])
    | _ -> raise_s [%message "rate: expected a JSON object"]
  in
  Or_error.ok_exn
    (of_parts
       ~base:(Currency.of_string (field "base"))
       ~quote:(Currency.of_string (field "quote"))
       ~price:(field "price")
       ~at:(Time_ns.of_string_with_utc_offset (field "at"))
       ~source:(field "source"))
;;

module Stable = struct
  module V1 = struct
    type nonrec t = t

    let compare = compare
    let equal = equal
    let sexp_of_t = sexp_of_t
    let t_of_sexp = t_of_sexp

    module Wire = struct
      type t =
        { base : Currency.Stable.V1.t
        ; quote : Currency.Stable.V1.t
        ; price : string (** [price_to_string] form *)
        ; at_ns_since_epoch : Int63.Stable.V1.t
        ; source : string
        }
      [@@deriving bin_io]
    end

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (Wire)
        (struct
          type nonrec t = t

          let to_binable (t : t) : Wire.t =
            { base = t.base
            ; quote = t.quote
            ; price = price_to_string t.price
            ; at_ns_since_epoch = Time_ns.to_int63_ns_since_epoch t.at
            ; source = t.source
            }
          ;;

          let of_binable (w : Wire.t) : t =
            Or_error.ok_exn
              (of_parts
                 ~base:w.base
                 ~quote:w.quote
                 ~price:w.price
                 ~at:(Time_ns.of_int63_ns_since_epoch w.at_ns_since_epoch)
                 ~source:w.source)
          ;;
        end)
  end
end
