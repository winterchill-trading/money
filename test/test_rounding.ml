open! Core
open Money

let%expect_test "every mode on the signed halves and thirds" =
  let cases = [ 5, 2; -5, 2; 7, 2; -7, 2; 1, 3; -1, 3; 2, 3; -2, 3; 4, 2 ] in
  List.iter Rounding.all ~f:(fun mode ->
    let results =
      List.map cases ~f:(fun (n, d) ->
        Z.to_int (Rounding.div mode (Z.of_int n) (Z.of_int d)))
    in
    print_s [%message "" (mode : Rounding.t) (results : int list)]);
  [%expect
    {|
    ((mode Down) (results (2 -3 3 -4 0 -1 0 -1 2)))
    ((mode Up) (results (3 -2 4 -3 1 0 1 0 2)))
    ((mode Toward_zero) (results (2 -2 3 -3 0 0 0 0 2)))
    ((mode Away_from_zero) (results (3 -3 4 -4 1 -1 1 -1 2)))
    ((mode Half_even) (results (2 -2 4 -4 0 0 1 -1 2)))
    ((mode Half_up) (results (3 -3 4 -4 0 0 1 -1 2)))
    |}]
;;

let%expect_test "a negative divisor is handled like a negative numerator" =
  List.iter Rounding.all ~f:(fun mode ->
    let a = Rounding.div mode (Z.of_int 7) (Z.of_int (-2)) in
    let b = Rounding.div mode (Z.of_int (-7)) (Z.of_int 2) in
    assert (Z.equal a b));
  [%expect {| |}]
;;

let%test_unit "result is within one unit, and half modes within one half" =
  Quickcheck.test
    ~sexp_of:[%sexp_of: Rounding.t * int * int]
    (Quickcheck.Generator.tuple3
       Rounding.quickcheck_generator
       Int.quickcheck_generator
       (Int.gen_incl 1 1_000_000))
    ~f:(fun (mode, n, d) ->
      let exact = Q.make (Z.of_int n) (Z.of_int d) in
      let r = Q.of_bigint (Rounding.div mode (Z.of_int n) (Z.of_int d)) in
      let err = Q.sub r exact in
      assert (Q.lt (Q.abs err) Q.one);
      match mode with
      | Down -> assert (Q.leq err Q.zero)
      | Up -> assert (Q.geq err Q.zero)
      | Toward_zero -> assert (Q.leq (Q.abs r) (Q.abs exact))
      | Away_from_zero -> assert (Q.geq (Q.abs r) (Q.abs exact))
      | Half_even | Half_up -> assert (Q.leq (Q.abs err) (Q.make Z.one (Z.of_int 2))))
;;

let%expect_test "names" =
  List.iter Rounding.all ~f:(fun t ->
    assert (Rounding.equal t (Rounding.of_string (Rounding.to_string t)));
    print_endline (Rounding.to_string t));
  print_s [%sexp (Rounding.of_string "Half_Even" : Rounding.t)];
  [%expect
    {|
    down
    up
    toward_zero
    away_from_zero
    half_even
    half_up
    Half_even
    |}]
;;
