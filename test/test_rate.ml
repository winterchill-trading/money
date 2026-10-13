open! Core
open Money

let at = Time_ns.of_string_with_utc_offset "2026-10-13T12:00:00Z"

let rate ?(base = Currency.eur) ?(quote = Currency.usd) price =
  Rate.create
    ~base
    ~quote
    ~price:(Or_error.ok_exn (Rate.price_of_string price))
    ~at
    ~source:"test"
  |> Or_error.ok_exn
;;

let%expect_test "prices print exactly" =
  List.iter
    [ "1.0845"; "150"; "0.000001"; "1.50"; "2000/2169"; "4/8"; "1e3"; "-1"; "1/0"; ".5" ]
    ~f:(fun s ->
      print_s
        [%message
          s
            ~_:
              (Rate.price_of_string s |> Or_error.map ~f:Rate.price_to_string
               : string Or_error.t)]);
  [%expect
    {|
    (1.0845 (Ok 1.0845))
    (150 (Ok 150))
    (0.000001 (Ok 0.000001))
    (1.50 (Ok 1.5))
    (2000/2169 (Ok 2000/2169))
    (4/8 (Ok 0.5))
    (1e3 (Error ("rate: malformed price" 1e3)))
    (-1 (Error ("rate: malformed price" -1)))
    (1/0 (Error ("rate: malformed price" 1/0)))
    (.5 (Error ("rate: malformed price" .5)))
    |}]
;;

let%expect_test "convert, inverse and validation" =
  let r = rate "1.0845" in
  print_s [%sexp (r : Rate.t)];
  let conv ?rounding r s =
    print_s
      [%sexp
        (Rate.convert ?rounding r (Amount.of_string s) |> Or_error.map ~f:Amount.to_string
         : string Or_error.t)]
  in
  conv r "100.00 EUR";
  conv r "0.05 EUR";
  conv ~rounding:Up r "0.05 EUR";
  conv r "100.00 USD";
  let inv = Rate.inverse r in
  print_s [%sexp (inv : Rate.t)];
  conv inv "108.45 USD";
  conv (rate ~base:Currency.btc ~quote:Currency.eur "61234.56") "0.00012345 BTC";
  conv (rate ~base:Currency.eth ~quote:Currency.usdc "2500.5") "1.000000000000000001 ETH";
  conv (rate ~base:Currency.usd ~quote:Currency.jpy "149.876") "10.00 USD";
  print_s
    [%sexp
      (Rate.create ~base:Currency.eur ~quote:Currency.eur ~price:Q.one ~at ~source:"x"
       : Rate.t Or_error.t)];
  print_s
    [%sexp
      (Rate.create ~base:Currency.eur ~quote:Currency.usd ~price:Q.zero ~at ~source:"x"
       : Rate.t Or_error.t)];
  [%expect
    {|
    ((base EUR) (quote USD) (price 1.0845) (at "2026-10-13 12:00:00Z")
     (source test))
    (Ok "108.45 USD")
    (Ok "0.05 USD")
    (Ok "0.06 USD")
    (Error
     ("rate: amount is not in the base currency" (amount "100.00 USD")
      (base EUR)))
    ((base USD) (quote EUR) (price 2000/2169) (at "2026-10-13 12:00:00Z")
     (source test))
    (Ok "100.00 EUR")
    (Ok "7.56 EUR")
    (Ok "2500.500000 USDC")
    (Ok "1499 JPY")
    (Error ("rate: base and quote are the same" (base EUR)))
    (Error ("rate: price must be positive" (price 0)))
    |}]
;;

let%expect_test "JSON and stable forms" =
  let r = Rate.inverse (rate "1.0845") in
  let json = Rate.yojson_of_t r in
  print_endline (Yojson.Safe.to_string json);
  assert (Rate.equal r (Rate.t_of_yojson json));
  assert (Rate.equal r (Rate.t_of_sexp (Rate.sexp_of_t r)));
  let bin = Bin_prot.Writer.to_string Rate.Stable.V1.bin_writer_t r in
  assert (Rate.equal r (Bin_prot.Reader.of_string Rate.Stable.V1.bin_reader_t bin));
  print_endline (Bin_prot.Shape.eval_to_digest_string Rate.Stable.V1.bin_shape_t);
  [%expect
    {|
    {"base":"USD","quote":"EUR","price":"2000/2169","at":"2026-10-13T12:00:00.000000000Z","source":"test"}
    c92b6b710d34c8fe69bea1d3a3976980
    |}]
;;

let gen_price =
  let open Quickcheck.Generator.Let_syntax in
  let%map n = Int.gen_incl 1 1_000_000_000
  and d = Int.gen_incl 1 1_000_000 in
  Q.of_ints n d
;;

let%test_unit "conversion is monotone in the amount" =
  Quickcheck.test
    (Quickcheck.Generator.tuple4
       gen_price
       Rounding.quickcheck_generator
       (Amount.quickcheck_generator_in Currency.eur)
       (Amount.quickcheck_generator_in Currency.eur))
    ~sexp_of:(fun (p, r, a, b) ->
      [%sexp (Q.to_string p : string), (r : Rounding.t), (a : Amount.t), (b : Amount.t)])
    ~f:(fun (price, rounding, a, b) ->
      let r =
        Or_error.ok_exn
          (Rate.create ~base:Currency.eur ~quote:Currency.btc ~price ~at ~source:"q")
      in
      let a, b = if Amount.(a <= b) then a, b else b, a in
      let ca = Or_error.ok_exn (Rate.convert ~rounding r a) in
      let cb = Or_error.ok_exn (Rate.convert ~rounding r b) in
      assert (Amount.(ca <= cb)))
;;

let%test_unit "converting there and back stays within the rounding of both legs" =
  Quickcheck.test
    (Quickcheck.Generator.tuple2 gen_price (Amount.quickcheck_generator_in Currency.usdc))
    ~sexp_of:(fun (p, a) -> [%sexp (Q.to_string p : string), (a : Amount.t)])
    ~f:(fun (price, a) ->
      let r =
        Or_error.ok_exn
          (Rate.create ~base:Currency.usdc ~quote:Currency.eth ~price ~at ~source:"q")
      in
      (* USDC (6) to ETH (18) at a price of at least 1e-6 loses nothing on the way out
         that the way back cannot recover to within half a minor unit. *)
      let there = Or_error.ok_exn (Rate.convert r a) in
      let back = Or_error.ok_exn (Rate.convert (Rate.inverse r) there) in
      let diff = Z.abs (Z.sub (Amount.minor_units back) (Amount.minor_units a)) in
      assert (Z.leq diff Z.one))
;;
