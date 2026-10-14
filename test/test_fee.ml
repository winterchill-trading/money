open! Core
open Money

let a = Amount.of_string

let card =
  Fee.create
    Currency.eur
    ~fixed:(a "0.25 EUR")
    ~bps:150
    ~min:(a "0.30 EUR")
    ~max:(a "25.00 EUR")
  |> Or_error.ok_exn
;;

let%expect_test "fixed plus bps, clamped, rounded by side" =
  List.iter
    [ "0.00 EUR"; "10.00 EUR"; "10.01 EUR"; "-10.01 EUR"; "100.00 EUR"; "5000.00 EUR" ]
    ~f:(fun s ->
      let fee side = Amount.to_string (Or_error.ok_exn (Fee.compute card ~side (a s))) in
      printf "%-12s payable %-10s receivable %s\n" s (fee Payable) (fee Receivable));
  print_s [%sexp (Fee.compute card ~side:Payable (a "1.00 USD") : Amount.t Or_error.t)];
  [%expect
    {|
    0.00 EUR     payable 0.30 EUR   receivable 0.30 EUR
    10.00 EUR    payable 0.40 EUR   receivable 0.40 EUR
    10.01 EUR    payable 0.40 EUR   receivable 0.41 EUR
    -10.01 EUR   payable 0.40 EUR   receivable 0.41 EUR
    100.00 EUR   payable 1.75 EUR   receivable 1.75 EUR
    5000.00 EUR  payable 25.00 EUR  receivable 25.00 EUR
    (Error
     ("fee: amount in another currency" (amount "1.00 USD") (currency EUR)))
    |}]
;;

let%expect_test "validation" =
  let show r = print_s [%sexp (r : Fee.t Or_error.t)] in
  show (Fee.create Currency.eur ~fixed:(a "1.00 USD"));
  show (Fee.create Currency.eur ~fixed:(a "-1.00 EUR"));
  show (Fee.create Currency.eur ~bps:(-1));
  show (Fee.create Currency.eur ~min:(a "2.00 EUR") ~max:(a "1.00 EUR"));
  show (Fee.create Currency.btc ~bps:10);
  print_s
    [%sexp
      (Or_error.try_with (fun () ->
         Fee.t_of_sexp
           (Sexp.of_string
              "((currency EUR) (fixed \"0.00 EUR\") (bps -5) (min ()) (max ()))"))
       |> Result.is_error
       : bool)];
  [%expect
    {|
    (Error
     ("fee: amount in another currency" fixed (amount "1.00 USD") (currency EUR)))
    (Error ("fee: negative amount" fixed (amount "-1.00 EUR")))
    (Error ("fee: negative bps" (bps -1)))
    (Error ("fee: min exceeds max" (min "2.00 EUR") (max "1.00 EUR")))
    (Ok ((currency BTC) (fixed "0.00000000 BTC") (bps 10) (min ()) (max ())))
    true
    |}]
;;

let%expect_test "JSON and stable forms" =
  let json = Fee.yojson_of_t card in
  print_endline (Yojson.Safe.to_string json);
  assert (Fee.equal card (Fee.t_of_yojson json));
  assert (Fee.equal card (Fee.t_of_sexp (Fee.sexp_of_t card)));
  let bin = Bin_prot.Writer.to_string Fee.Stable.V1.bin_writer_t card in
  assert (Fee.equal card (Bin_prot.Reader.of_string Fee.Stable.V1.bin_reader_t bin));
  print_endline (Bin_prot.Shape.eval_to_digest_string Fee.Stable.V1.bin_shape_t);
  [%expect
    {|
    {"currency":"EUR","fixed":"0.25","bps":"150","min":"0.30","max":"25.00"}
    bff5f77e553e8ab3f51b80a0ea7bdc91
    |}]
;;

let%test_unit "fees are within bounds and receivable never below payable" =
  Quickcheck.test
    (Quickcheck.Generator.tuple2
       (Int.gen_incl 0 10_000)
       (Amount.quickcheck_generator_in Currency.eur))
    ~sexp_of:[%sexp_of: int * Amount.t]
    ~f:(fun (bps, amount) ->
      let fee =
        Or_error.ok_exn
          (Fee.create Currency.eur ~bps ~min:(a "0.10 EUR") ~max:(a "1000000.00 EUR"))
      in
      let p = Or_error.ok_exn (Fee.compute fee ~side:Payable amount) in
      let r = Or_error.ok_exn (Fee.compute fee ~side:Receivable amount) in
      assert (Amount.(p <= r));
      assert (Amount.(a "0.10 EUR" <= p));
      assert (Amount.(r <= a "1000000.00 EUR"));
      let exact =
        Q.mul
          (Q.of_bigint (Amount.minor_units (Amount.abs amount)))
          (Q.of_ints bps 10_000)
      in
      (* Unclamped results are the exact fee rounded down or up. *)
      let unclamped x = Amount.(a "0.10 EUR" < x && x < a "1000000.00 EUR") in
      if unclamped p then assert (Q.leq (Q.of_bigint (Amount.minor_units p)) exact);
      if unclamped r then assert (Q.geq (Q.of_bigint (Amount.minor_units r)) exact))
;;

let%expect_test "fractional basis points" =
  let fee bps = Or_error.ok_exn (Fee.create Currency.eur ~bps_q:(Q.of_string bps)) in
  List.iter [ "1/2"; "2.75"; "1/3" ] ~f:(fun bps ->
    let f = fee bps in
    let compute side =
      Amount.to_string (Or_error.ok_exn (Fee.compute f ~side (a "1000.00 EUR")))
    in
    printf
      "%-5s payable %s receivable %s sexp %s json %s\n"
      bps
      (compute Payable)
      (compute Receivable)
      (Sexp.to_string [%sexp (Q.to_string (Fee.bps_q f) : string)])
      (Yojson.Safe.to_string (Fee.yojson_of_t f)));
  print_s
    [%sexp
      (Fee.create Currency.eur ~bps:1 ~bps_q:Q.one : Fee.t Or_error.t)
      , (Fee.create Currency.eur ~bps_q:(Q.of_ints (-1) 2) : Fee.t Or_error.t)];
  [%expect
    {|
    1/2   payable 0.05 EUR receivable 0.05 EUR sexp 1/2 json {"currency":"EUR","fixed":"0.00","bps":"0.5","min":null,"max":null}
    2.75  payable 0.27 EUR receivable 0.28 EUR sexp 11/4 json {"currency":"EUR","fixed":"0.00","bps":"2.75","min":null,"max":null}
    1/3   payable 0.03 EUR receivable 0.04 EUR sexp 1/3 json {"currency":"EUR","fixed":"0.00","bps":"1/3","min":null,"max":null}
    ((Error "fee: give bps or bps_q, not both")
     (Error ("fee: negative bps" (bps -1/2))))
    |}]
;;

let%expect_test "every form round-trips fractional basis points; V1 refuses them" =
  let f =
    Fee.create Currency.eur ~fixed:(a "0.10 EUR") ~bps_q:(Q.of_ints 1 3)
    |> Or_error.ok_exn
  in
  print_s [%sexp (f : Fee.t)];
  assert (Fee.equal f (Fee.t_of_sexp (Fee.sexp_of_t f)));
  assert (Fee.equal f (Fee.t_of_yojson (Fee.yojson_of_t f)));
  let bin = Bin_prot.Writer.to_string Fee.Stable.V2.bin_writer_t f in
  assert (Fee.equal f (Bin_prot.Reader.of_string Fee.Stable.V2.bin_reader_t bin));
  print_endline (Bin_prot.Shape.eval_to_digest_string Fee.Stable.V2.bin_shape_t);
  print_s
    [%sexp
      (Result.is_error
         (Or_error.try_with (fun () ->
            Bin_prot.Writer.to_string Fee.Stable.V1.bin_writer_t f))
       : bool)];
  (* A whole-bps sexp written before fractions existed still reads. *)
  print_s
    [%sexp
      (Fee.t_of_sexp
         (Sexp.of_string
            "((currency EUR) (fixed \"0.25 EUR\") (bps 150) (min ()) (max ()))")
       : Fee.t)];
  [%expect
    {|
    ((currency EUR) (fixed "0.10 EUR") (bps 1/3) (min ()) (max ()))
    8a3bcb33f3d3cf0e0ba7fa8f3b5d7e4c
    true
    ((currency EUR) (fixed "0.25 EUR") (bps 150) (min ()) (max ()))
    |}]
;;

let%test_unit "V1 and V2 bin_prot agree on whole basis points" =
  Quickcheck.test (Int.gen_incl 0 100_000) ~sexp_of:[%sexp_of: int] ~f:(fun bps ->
    let f = Or_error.ok_exn (Fee.create Currency.eur ~bps ~min:(a "0.01 EUR")) in
    let v1 = Bin_prot.Writer.to_string Fee.Stable.V1.bin_writer_t f in
    let v2 = Bin_prot.Writer.to_string Fee.Stable.V2.bin_writer_t f in
    [%test_result: Fee.t]
      ~expect:f
      (Bin_prot.Reader.of_string Fee.Stable.V1.bin_reader_t v1);
    [%test_result: Fee.t]
      ~expect:f
      (Bin_prot.Reader.of_string Fee.Stable.V2.bin_reader_t v2))
;;
