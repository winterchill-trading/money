open! Core
open Money

let show r = print_s [%sexp (r : Amount.t Or_error.t)]

let%expect_test "printing uses exactly the currency's digits" =
  List.iter
    [ Currency.eur, 1234
    ; Currency.eur, -5
    ; Currency.eur, 0
    ; Currency.jpy, -5
    ; Currency.btc, 12345
    ; Currency.btc_lightning, 1_000
    ; Currency.usdc_polygon, 1_500_000
    ; Currency.of_string "KWD", 1
    ]
    ~f:(fun (c, n) -> print_endline (Amount.to_string (Amount.of_minor_units_int c n)));
  print_endline
    (Amount.to_string
       (Amount.of_minor_units Currency.eth (Z.of_string "123456789012345678901234567")));
  [%expect
    {|
    12.34 EUR
    -0.05 EUR
    0.00 EUR
    -5 JPY
    0.00012345 BTC
    0.00000001000 BTC@lightning
    1.500000 USDC@polygon
    0.001 KWD
    123456789.012345678901234567 ETH
    |}]
;;

let%expect_test "parsing" =
  List.iter
    [ "12.34 EUR"
    ; "12.3 EUR"
    ; "12 EUR"
    ; "12.340000 EUR"
    ; "-0.00 EUR"
    ; "0.00012345 BTC"
    ; "1.5 ETH"
    ; "12.345 EUR"
    ; ".5 EUR"
    ; "5. EUR"
    ; "+5 EUR"
    ; "1,000.00 EUR"
    ; "1e3 EUR"
    ; "12.34EUR"
    ; "12.34  EUR"
    ; "12.34 eur"
    ; "12.34 XXX"
    ]
    ~f:(fun s ->
      printf "%-16s " s;
      show (Amount.of_string_or_error s));
  [%expect
    {|
    12.34 EUR        (Ok "12.34 EUR")
    12.3 EUR         (Ok "12.30 EUR")
    12 EUR           (Ok "12.00 EUR")
    12.340000 EUR    (Ok "12.34 EUR")
    -0.00 EUR        (Ok "0.00 EUR")
    0.00012345 BTC   (Ok "0.00012345 BTC")
    1.5 ETH          (Ok "1.500000000000000000 ETH")
    12.345 EUR       (Error
     ("amount: more fractional digits than the currency has" (input 12.345)))
    .5 EUR           (Error ("amount: expected digits before the decimal point" (input .5)))
    5. EUR           (Error ("amount: expected digits after the decimal point" (input 5.)))
    +5 EUR           (Error ("amount: expected digits before the decimal point" (input +5)))
    1,000.00 EUR     (Error ("amount: expected digits before the decimal point" (input 1,000.00)))
    1e3 EUR          (Error ("amount: expected digits before the decimal point" (input 1e3)))
    12.34EUR         (Error ("amount: expected \"<decimal> <currency>\"" 12.34EUR))
    12.34  EUR       (Error ("unknown currency" " EUR"))
    12.34 eur        (Error ("unknown currency" eur))
    12.34 XXX        (Error ("unknown currency" XXX))
    |}]
;;

let eur = Amount.of_string
let usd = Amount.of_string

let%expect_test "arithmetic requires one currency" =
  show (Amount.add (eur "1.10 EUR") (eur "2.20 EUR"));
  show (Amount.sub (eur "1.10 EUR") (eur "2.20 EUR"));
  show (Amount.add (eur "1.10 EUR") (usd "2.20 USD"));
  show
    (Amount.add Amount.(of_string "1 USDC@ethereum") (Amount.of_string "1 USDC@polygon"));
  show (Amount.sum Currency.eur [ eur "1.00 EUR"; eur "2.50 EUR"; eur "-0.25 EUR" ]);
  show (Amount.sum Currency.eur []);
  show (Amount.sum Currency.eur [ eur "1.00 EUR"; usd "1.00 USD" ]);
  print_s
    [%sexp (Amount.compare_value (eur "1.00 EUR") (usd "1.00 USD") : int Or_error.t)];
  [%expect
    {|
    (Ok "3.30 EUR")
    (Ok "-1.10 EUR")
    (Error ("currency mismatch" add "1.10 EUR" "2.20 USD"))
    (Error
     ("currency mismatch" add "1.000000 USDC@ethereum" "1.000000 USDC@polygon"))
    (Ok "3.25 EUR")
    (Ok "0.00 EUR")
    (Error ("currency mismatch" add "1.00 EUR" "1.00 USD"))
    (Error ("currency mismatch" compare "1.00 EUR" "1.00 USD"))
    |}]
;;

let%expect_test "ratios and basis points round as asked" =
  let a = eur "10.05 EUR" in
  let half = Q.of_ints 1 2 in
  List.iter Rounding.all ~f:(fun rounding ->
    printf
      "%-15s %s %s %s\n"
      (Rounding.to_string rounding)
      (Amount.to_string (Amount.mul_ratio ~rounding a half))
      (Amount.to_string (Amount.mul_ratio ~rounding (Amount.neg a) half))
      (Amount.to_string (Amount.mul_bps ~rounding (eur "0.99 EUR") ~bps:150)));
  print_endline (Amount.to_string (Amount.mul_ratio a half));
  print_endline (Amount.to_string (Amount.scale a 3));
  [%expect
    {|
    down            5.02 EUR -5.03 EUR 0.01 EUR
    up              5.03 EUR -5.02 EUR 0.02 EUR
    toward_zero     5.02 EUR -5.02 EUR 0.01 EUR
    away_from_zero  5.03 EUR -5.03 EUR 0.02 EUR
    half_even       5.02 EUR -5.02 EUR 0.01 EUR
    half_up         5.03 EUR -5.03 EUR 0.01 EUR
    5.02 EUR
    30.15 EUR
    |}]
;;

let%expect_test "fixed-decimal interop" =
  let module F = Fixed_decimal.Make () in
  let f = (module F : Fixed_decimal.S with type t = F.t) in
  let to_fd s =
    print_s
      [%sexp
        (Amount.to_fixed_decimal f (Amount.of_string s) |> Or_error.map ~f:F.to_string
         : string Or_error.t)]
  in
  to_fd "12.34 EUR";
  to_fd "0.00012345 BTC";
  to_fd "0.00000001000 BTC@lightning";
  to_fd "0.00000000001 BTC@lightning";
  to_fd "1.5 ETH";
  to_fd "1.000000000000000001 ETH";
  to_fd "100000000000 EUR";
  let of_fd c s = show (Amount.of_fixed_decimal f c (F.of_string s)) in
  of_fd Currency.eur "12.34";
  of_fd Currency.eur "12.345";
  of_fd Currency.eth "0.12345678";
  of_fd Currency.jpy "-100";
  [%expect
    {|
    (Ok 12.34)
    (Ok 0.00012345)
    (Ok 0.00000001)
    (Error
     ("amount has more than 8 fractional digits" "0.00000000001 BTC@lightning"))
    (Ok 1.5)
    (Error
     ("amount has more than 8 fractional digits" "1.000000000000000001 ETH"))
    (Error ("amount out of fixed-decimal range" "100000000000.00 EUR"))
    (Ok "12.34 EUR")
    (Error
     ("value has more fractional digits than the currency" (value 12.345)
      (currency EUR)))
    (Ok "0.123456780000000000 ETH")
    (Ok "-100 JPY")
    |}]
;;

let%expect_test "JSON keeps numbers in strings" =
  let a = Amount.of_string "-1234.5 USDC@solana" in
  let json = Amount.yojson_of_t a in
  print_endline (Yojson.Safe.to_string json);
  assert (Amount.equal a (Amount.t_of_yojson json));
  print_s
    [%sexp
      (Or_error.try_with (fun () ->
         Amount.t_of_yojson
           (Yojson.Safe.from_string {|{"amount":12.34,"currency":"EUR"}|}))
       : Amount.t Or_error.t)];
  [%expect
    {|
    {"amount":"-1234.500000","currency":"USDC@solana"}
    (Error "amount: expected string fields amount and currency")
    |}]
;;

let%expect_test "stable forms" =
  let a = Amount.of_minor_units Currency.eth (Z.of_string "-98765432109876543210") in
  print_s [%sexp (a : Amount.Stable.V1.t)];
  let bin = Bin_prot.Writer.to_string Amount.Stable.V1.bin_writer_t a in
  print_s [%sexp (bin : string)];
  assert (Amount.equal a (Bin_prot.Reader.of_string Amount.Stable.V1.bin_reader_t bin));
  print_endline (Bin_prot.Shape.eval_to_digest_string Amount.Stable.V1.bin_shape_t);
  [%expect
    {|
    "-98.765432109876543210 ETH"
    "\003ETH\021-98765432109876543210"
    75b4abde0f7b6de64dd7bb0f751e25d4
    |}]
;;

(* Properties. *)

let gen_pair =
  let open Quickcheck.Generator.Let_syntax in
  let%bind a = Amount.quickcheck_generator in
  let%map b = Amount.quickcheck_generator_in (Amount.currency a) in
  a, b
;;

let%test_unit "add then sub round trips" =
  Quickcheck.test gen_pair ~sexp_of:[%sexp_of: Amount.t * Amount.t] ~f:(fun (a, b) ->
    [%test_result: Amount.t] ~expect:a (Amount.sub_exn (Amount.add_exn a b) b);
    [%test_result: Amount.t] ~expect:a (Amount.add_exn (Amount.sub_exn a b) b);
    [%test_result: Amount.t]
      ~expect:(Amount.zero (Amount.currency a))
      (Amount.add_exn a (Amount.neg a)))
;;

let%test_unit "printing then parsing is the identity" =
  Quickcheck.test Amount.quickcheck_generator ~sexp_of:[%sexp_of: Amount.t] ~f:(fun a ->
    [%test_result: Amount.t] ~expect:a (Amount.of_string (Amount.to_string a));
    [%test_result: Amount.t] ~expect:a (Amount.t_of_sexp (Amount.sexp_of_t a));
    [%test_result: Amount.t] ~expect:a (Amount.t_of_yojson (Amount.yojson_of_t a));
    [%test_result: Amount.t]
      ~expect:a
      (Bin_prot.Writer.to_string Amount.Stable.V1.bin_writer_t a
       |> Bin_prot.Reader.of_string Amount.Stable.V1.bin_reader_t))
;;

let%test_unit "the canonical text is unique" =
  Quickcheck.test Amount.quickcheck_generator ~sexp_of:[%sexp_of: Amount.t] ~f:(fun a ->
    let s = Amount.to_string a in
    [%test_result: string] ~expect:s (Amount.to_string (Amount.of_string s)))
;;

let%test_unit "basis points stay within one minor unit of the exact product" =
  Quickcheck.test
    (Quickcheck.Generator.tuple3
       Amount.quickcheck_generator
       (Int.gen_incl (-20_000) 20_000)
       Rounding.quickcheck_generator)
    ~sexp_of:[%sexp_of: Amount.t * int * Rounding.t]
    ~f:(fun (a, bps, rounding) ->
      let exact = Q.mul (Q.of_bigint (Amount.minor_units a)) (Q.of_ints bps 10_000) in
      let got = Q.of_bigint (Amount.minor_units (Amount.mul_bps ~rounding a ~bps)) in
      assert (Q.lt (Q.abs (Q.sub got exact)) Q.one))
;;
