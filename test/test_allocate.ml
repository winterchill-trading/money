open! Core
open Money

let a = Amount.of_string

let show r =
  print_s
    [%sexp (Result.map r ~f:(List.map ~f:Amount.to_string) : string list Or_error.t)]
;;

let%expect_test "split into equal parts" =
  show (Amount.split (a "100.00 EUR") ~parts:3);
  show (Amount.split (a "-100.00 EUR") ~parts:3);
  show (Amount.split (a "0.02 EUR") ~parts:3);
  show (Amount.split (a "5 JPY") ~parts:1);
  show (Amount.split (a "1.00 EUR") ~parts:0);
  [%expect
    {|
    (Ok ("33.34 EUR" "33.33 EUR" "33.33 EUR"))
    (Ok ("-33.34 EUR" "-33.33 EUR" "-33.33 EUR"))
    (Ok ("0.01 EUR" "0.01 EUR" "0.00 EUR"))
    (Ok ("5 JPY"))
    (Error ("split: parts must be positive" (parts 0)))
    |}]
;;

let%expect_test "allocate by ratios, leftovers to the largest remainders" =
  (* 0.05 EUR at 3:7 is 1.5 and 3.5 cents; both remainders are a half, so the tie goes to
     the earlier part. *)
  show (Amount.allocate (a "0.05 EUR") ~ratios:[ 3; 7 ]);
  (* 10.00 at 1:2:2 is 2.00, 4.00, 4.00 exactly. *)
  show (Amount.allocate (a "10.00 EUR") ~ratios:[ 1; 2; 2 ]);
  (* A zero ratio gets nothing. *)
  show (Amount.allocate (a "1.00 EUR") ~ratios:[ 70; 0; 20; 10 ]);
  (* 0.11 at 1:1:1:1:1:1 rounds 1.8333 cents each; the 5 leftover cents go to the first
     five parts. *)
  show (Amount.allocate (a "0.11 EUR") ~ratios:[ 1; 1; 1; 1; 1; 1 ]);
  (* 1 satoshi of 0.00000001 BTC by 1:2 is 1/3 and 2/3: the larger remainder wins. *)
  show (Amount.allocate (a "0.00000001 BTC") ~ratios:[ 1; 2 ]);
  show (Amount.allocate (a "1.00 EUR") ~ratios:[]);
  show (Amount.allocate (a "1.00 EUR") ~ratios:[ 1; -1 ]);
  show (Amount.allocate (a "1.00 EUR") ~ratios:[ 0; 0 ]);
  [%expect
    {|
    (Ok ("0.02 EUR" "0.03 EUR"))
    (Ok ("2.00 EUR" "4.00 EUR" "4.00 EUR"))
    (Ok ("0.70 EUR" "0.00 EUR" "0.20 EUR" "0.10 EUR"))
    (Ok ("0.02 EUR" "0.02 EUR" "0.02 EUR" "0.02 EUR" "0.02 EUR" "0.01 EUR"))
    (Ok ("0.00000000 BTC" "0.00000001 BTC"))
    (Error "allocate: no ratios")
    (Error ("allocate: negative ratio" (ratios (1 -1))))
    (Error ("allocate: ratios sum to zero" (ratios (0 0))))
    |}]
;;

let ratios_generator =
  let open Quickcheck.Generator.Let_syntax in
  let%bind n = Int.gen_incl 1 12 in
  let%bind ratios = List.gen_with_length n (Int.gen_incl 0 1_000) in
  (* At least one positive ratio. *)
  let%map extra = Int.gen_incl 1 1_000 in
  List.mapi ratios ~f:(fun i r -> if i = 0 then r + extra else r)
;;

let%test_unit "parts sum to the amount, stay within a unit of the exact share, and \
               leftovers go to the largest remainders"
  =
  Quickcheck.test
    (Quickcheck.Generator.tuple2 Amount.quickcheck_generator ratios_generator)
    ~sexp_of:[%sexp_of: Amount.t * int list]
    ~f:(fun (amount, ratios) ->
      let parts = Or_error.ok_exn (Amount.allocate amount ~ratios) in
      [%test_result: int] ~expect:(List.length ratios) (List.length parts);
      [%test_result: Amount.t]
        ~expect:amount
        (Or_error.ok_exn (Amount.sum (Amount.currency amount) parts));
      let total = List.sum (module Int) ratios ~f:Fn.id in
      let units = Q.of_bigint (Z.abs (Amount.minor_units amount)) in
      let fractions =
        List.map2_exn parts ratios ~f:(fun part r ->
          let exact = Q.(units * of_ints r total) in
          let got = Q.of_bigint (Z.abs (Amount.minor_units part)) in
          assert (Q.lt (Q.abs (Q.sub got exact)) Q.one);
          if r = 0 then assert (Amount.is_zero part);
          let floor = Q.of_bigint (Rounding.round Down exact) in
          let bumped = Q.gt got floor in
          bumped, Q.sub exact floor)
      in
      let bumped = List.filter_map fractions ~f:(fun (b, f) -> Option.some_if b f) in
      let kept = List.filter_map fractions ~f:(fun (b, f) -> Option.some_if (not b) f) in
      match
        List.min_elt bumped ~compare:Q.compare, List.max_elt kept ~compare:Q.compare
      with
      | Some lo, Some hi -> assert (Q.geq lo hi)
      | _ -> ())
;;

let%test_unit "the split of a negative amount is the negated split" =
  Quickcheck.test
    (Quickcheck.Generator.tuple2 Amount.quickcheck_generator (Int.gen_incl 1 50))
    ~sexp_of:[%sexp_of: Amount.t * int]
    ~f:(fun (amount, parts) ->
      [%test_result: Amount.t list]
        ~expect:(List.map ~f:Amount.neg (Or_error.ok_exn (Amount.split amount ~parts)))
        (Or_error.ok_exn (Amount.split (Amount.neg amount) ~parts)))
;;
