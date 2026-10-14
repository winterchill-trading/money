open! Core
open Money

let show r = print_s [%sexp (Result.map r ~f:Currency.to_string : string Or_error.t)]

let%expect_test "freeze stops new registrations but keeps identical ones" =
  show (Currency.register ~code:"EURC" ~exponent:6 ~kind:Crypto ());
  print_s [%sexp (Currency.is_frozen () : bool)];
  Currency.freeze ();
  Currency.freeze ();
  print_s [%sexp (Currency.is_frozen () : bool)];
  show (Currency.register ~code:"EURC" ~exponent:6 ~kind:Crypto ());
  show (Currency.register ~code:"PYUSD" ~exponent:6 ~kind:Crypto ());
  show (Currency.of_string_or_error "EURC");
  [%expect
    {|
    (Ok EURC)
    false
    true
    (Ok EURC)
    (Error ("currency registry is frozen" PYUSD))
    (Ok EURC)
    |}]
;;
