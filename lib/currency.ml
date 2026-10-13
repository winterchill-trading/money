open! Core

module Kind = struct
  type t =
    | Fiat
    | Crypto
  [@@deriving sexp, compare, equal, enumerate]
end

module T = struct
  type t =
    { id : string
    ; code : string
    ; network : string option
    ; exponent : int
    ; kind : Kind.t
    }

  (* Identity is the text form alone: the registry guarantees one record per id. *)
  let compare a b = String.compare a.id b.id
  let hash t = String.hash t.id
  let hash_fold_t state t = String.hash_fold_t state t.id
end

include T

let code t = t.code
let network t = t.network
let exponent t = t.exponent
let kind t = t.kind
let to_string t = t.id

let make_id ~code ~network =
  match network with
  | None -> code
  | Some network -> code ^ "@" ^ network
;;

let registry : t String.Table.t = String.Table.create ()

let of_string_or_error s =
  match Hashtbl.find registry s with
  | Some t -> Ok t
  | None -> Or_error.error_s [%message "unknown currency" s]
;;

let of_string s = Or_error.ok_exn (of_string_or_error s)

let valid_code code =
  let n = String.length code in
  n >= 2
  && n <= 12
  && String.for_all code ~f:(fun c -> Char.is_uppercase c || Char.is_digit c)
;;

let valid_network network =
  let n = String.length network in
  n >= 1
  && n <= 32
  && String.for_all network ~f:(fun c ->
    Char.is_lowercase c || Char.is_digit c || Char.equal c '-')
;;

let register ~code ?network ~exponent ~kind () =
  let open Or_error.Let_syntax in
  let%bind () =
    if valid_code code
    then Ok ()
    else Or_error.error_s [%message "currency code must be 2-12 of A-Z0-9" code]
  in
  let%bind () =
    match network with
    | Some n when not (valid_network n) ->
      Or_error.error_s [%message "network must be 1-32 of a-z0-9-" n]
    | _ -> Ok ()
  in
  let%bind () =
    if exponent >= 0 && exponent <= 36
    then Ok ()
    else Or_error.error_s [%message "exponent must be in [0, 36]" code (exponent : int)]
  in
  let%bind () =
    match kind, network with
    | Kind.Fiat, Some _ -> Or_error.error_s [%message "fiat currency with a network" code]
    | Kind.Fiat, None
      when String.length code <> 3 || not (String.for_all code ~f:Char.is_alpha) ->
      Or_error.error_s [%message "fiat code must be three letters" code]
    | _ -> Ok ()
  in
  let id = make_id ~code ~network in
  let t = { id; code; network; exponent; kind } in
  match Hashtbl.find registry id with
  | None ->
    Hashtbl.set registry ~key:id ~data:t;
    Ok t
  | Some existing ->
    if Int.equal existing.exponent exponent && Kind.equal existing.kind kind
    then Ok existing
    else
      Or_error.error_s
        [%message
          "currency already registered differently"
            id
            ~registered_exponent:(existing.exponent : int)
            ~registered_kind:(existing.kind : Kind.t)]
;;

let all () = Hashtbl.data registry |> List.sort ~compare

let builtin ~code ?network ~exponent kind =
  Or_error.ok_exn (register ~code ?network ~exponent ~kind ())
;;

(* ISO 4217 minor units. Codes with exponent 0 or 3 are the ones most often gotten wrong;
   the rest are 2. *)
let () =
  List.iter
    [ "AED", 2
    ; "AUD", 2
    ; "BGN", 2
    ; "BHD", 3
    ; "BRL", 2
    ; "CAD", 2
    ; "CHF", 2
    ; "CLP", 0
    ; "CNY", 2
    ; "CZK", 2
    ; "DKK", 2
    ; "EUR", 2
    ; "GBP", 2
    ; "HKD", 2
    ; "HUF", 2
    ; "IDR", 2
    ; "ILS", 2
    ; "INR", 2
    ; "ISK", 0
    ; "JOD", 3
    ; "JPY", 0
    ; "KRW", 0
    ; "KWD", 3
    ; "MXN", 2
    ; "NOK", 2
    ; "NZD", 2
    ; "OMR", 3
    ; "PHP", 2
    ; "PLN", 2
    ; "RON", 2
    ; "SAR", 2
    ; "SEK", 2
    ; "SGD", 2
    ; "THB", 2
    ; "TND", 3
    ; "TRY", 2
    ; "UAH", 2
    ; "USD", 2
    ; "VND", 0
    ; "ZAR", 2
    ]
    ~f:(fun (code, exponent) -> ignore (builtin ~code ~exponent Fiat : t))
;;

let eur = of_string "EUR"
let usd = of_string "USD"
let gbp = of_string "GBP"
let chf = of_string "CHF"
let jpy = of_string "JPY"
let btc = builtin ~code:"BTC" ~exponent:8 Crypto

(* 1 sat = 1000 msat, so 11 digits; 21M BTC is 2.1e18 msat, still a 63-bit int. *)
let btc_lightning = builtin ~code:"BTC" ~network:"lightning" ~exponent:11 Crypto
let eth = builtin ~code:"ETH" ~exponent:18 Crypto
let usdc = builtin ~code:"USDC" ~exponent:6 Crypto
let usdt = builtin ~code:"USDT" ~exponent:6 Crypto
let usdc_ethereum = builtin ~code:"USDC" ~network:"ethereum" ~exponent:6 Crypto
let usdc_polygon = builtin ~code:"USDC" ~network:"polygon" ~exponent:6 Crypto
let usdc_solana = builtin ~code:"USDC" ~network:"solana" ~exponent:6 Crypto
let usdt_ethereum = builtin ~code:"USDT" ~network:"ethereum" ~exponent:6 Crypto
let usdt_tron = builtin ~code:"USDT" ~network:"tron" ~exponent:6 Crypto
let sexp_of_t t = Sexp.Atom t.id

let t_of_sexp sexp =
  match sexp with
  | Sexp.Atom s ->
    (match of_string_or_error s with
     | Ok t -> t
     | Error e -> of_sexp_error (Error.to_string_hum e) sexp)
  | Sexp.List _ -> of_sexp_error "currency: expected an atom" sexp
;;

let yojson_of_t t = `String t.id

let t_of_yojson json =
  match json with
  | `String s -> of_string s
  | _ -> raise_s [%message "currency: expected a JSON string"]
;;

include Comparable.Make (struct
    include T

    let sexp_of_t = sexp_of_t
    let t_of_sexp = t_of_sexp
  end)

include Hashable.Make (struct
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

    include
      Binable.Of_binable_without_uuid [@alert "-legacy"]
        (String)
        (struct
          type nonrec t = t

          let to_binable = to_string
          let of_binable = of_string
        end)
  end
end
