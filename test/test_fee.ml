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
