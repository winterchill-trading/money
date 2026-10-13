open! Core
open Money

let%expect_test "built-in crypto currencies" =
  List.iter (Currency.all ()) ~f:(fun c ->
    match Currency.kind c with
    | Fiat -> ()
    | Crypto ->
      print_s
        [%message
          ""
            ~_:(c : Currency.t)
            ~code:(Currency.code c : string)
            ~network:(Currency.network c : string option)
            ~exponent:(Currency.exponent c : int)]);
  [%expect
    {|
    (BTC (code BTC) (network ()) (exponent 8))
    (BTC@lightning (code BTC) (network (lightning)) (exponent 11))
    (ETH (code ETH) (network ()) (exponent 18))
    (USDC (code USDC) (network ()) (exponent 6))
    (USDC@ethereum (code USDC) (network (ethereum)) (exponent 6))
    (USDC@polygon (code USDC) (network (polygon)) (exponent 6))
    (USDC@solana (code USDC) (network (solana)) (exponent 6))
    (USDT (code USDT) (network ()) (exponent 6))
    (USDT@ethereum (code USDT) (network (ethereum)) (exponent 6))
    (USDT@tron (code USDT) (network (tron)) (exponent 6))
    |}]
;;

let%expect_test "fiat exponents that are not 2" =
  List.iter (Currency.all ()) ~f:(fun c ->
    match Currency.kind c with
    | Crypto -> ()
    | Fiat ->
      if Currency.exponent c <> 2
      then printf "%s %d\n" (Currency.to_string c) (Currency.exponent c));
  [%expect
    {|
    BHD 3
    CLP 0
    ISK 0
    JOD 3
    JPY 0
    KRW 0
    KWD 3
    OMR 3
    TND 3
    VND 0
    |}]
;;

let%expect_test "register validates and is idempotent" =
  let show r = print_s [%sexp (Result.map r ~f:Currency.to_string : string Or_error.t)] in
  show (Currency.register ~code:"PYUSD" ~network:"solana" ~exponent:6 ~kind:Crypto ());
  show (Currency.register ~code:"PYUSD" ~network:"solana" ~exponent:6 ~kind:Crypto ());
  show (Currency.register ~code:"PYUSD" ~network:"solana" ~exponent:8 ~kind:Crypto ());
  show (Currency.register ~code:"eur" ~exponent:2 ~kind:Fiat ());
  show (Currency.register ~code:"EURO" ~exponent:2 ~kind:Fiat ());
  show (Currency.register ~code:"EUR" ~network:"sepa" ~exponent:2 ~kind:Fiat ());
  show (Currency.register ~code:"XYZ" ~network:"Bad Net" ~exponent:2 ~kind:Crypto ());
  show (Currency.register ~code:"XYZ" ~exponent:37 ~kind:Crypto ());
  print_s [%sexp (Currency.of_string "PYUSD@solana" |> Currency.exponent : int)];
  [%expect
    {|
    (Ok PYUSD@solana)
    (Ok PYUSD@solana)
    (Error
     ("currency already registered differently" PYUSD@solana
      (registered_exponent 6) (registered_kind Crypto)))
    (Error ("currency code must be 2-12 of A-Z0-9" eur))
    (Error ("fiat code must be three letters" EURO))
    (Error ("fiat currency with a network" EUR))
    (Error ("network must be 1-32 of a-z0-9-" "Bad Net"))
    (Error ("exponent must be in [0, 36]" XYZ (exponent 37)))
    6
    |}]
;;

let%expect_test "text, sexp, JSON and bin_prot forms" =
  let c = Currency.usdc_polygon in
  print_s [%sexp (c : Currency.t)];
  print_endline (Yojson.Safe.to_string (Currency.yojson_of_t c));
  let buf = Bin_prot.Writer.to_string Currency.Stable.V1.bin_writer_t c in
  print_s [%sexp (buf : string)];
  assert (Currency.equal c (Bin_prot.Reader.of_string Currency.Stable.V1.bin_reader_t buf));
  assert (Currency.equal c (Currency.t_of_sexp (Currency.sexp_of_t c)));
  print_s [%sexp (Currency.of_string_or_error "DOGE@moon" : Currency.t Or_error.t)];
  print_s [%sexp (Currency.equal Currency.usdc Currency.usdc_ethereum : bool)];
  [%expect
    {|
    USDC@polygon
    "USDC@polygon"
    "\012USDC@polygon"
    (Error ("unknown currency" DOGE@moon))
    false
    |}]
;;

let%expect_test "stable shape digest" =
  print_endline (Bin_prot.Shape.eval_to_digest_string Currency.Stable.V1.bin_shape_t);
  [%expect {| d9a8da25d5656b016fb4dbdc2e4197fb |}]
;;
