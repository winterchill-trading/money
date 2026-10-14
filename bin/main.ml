open! Core
open Money

let amount_arg = Command.Arg_type.create Amount.of_string
let currency_arg = Command.Arg_type.create Currency.of_string
let rounding_arg = Command.Arg_type.create Rounding.of_string

let side_arg =
  Command.Arg_type.of_alist_exn
    (List.map Fee.Side.all ~f:(fun s ->
       String.lowercase (Sexp.to_string (Fee.Side.sexp_of_t s)), s))
;;

let ok_or_exit = function
  | Ok x -> x
  | Error e ->
    Core.eprintf "%s\n" (Error.to_string_hum e);
    Stdlib.exit 1
;;

let convert =
  Command.basic
    ~summary:"convert an amount at a given price"
    ~readme:(fun () ->
      "money convert \"100.00 EUR\" -to USD -price 1.0845\n\n\
       The price is quote currency per one unit of the amount's currency, as a decimal \
       or a fraction (2000/2169).")
    (let%map_open.Command amount = anon ("AMOUNT" %: amount_arg)
     and quote = flag "to" (required currency_arg) ~doc:"CURRENCY target currency"
     and price = flag "price" (required string) ~doc:"PRICE quote per one base unit"
     and rounding =
       flag
         "rounding"
         (optional_with_default Rounding.default rounding_arg)
         ~doc:"MODE down, up, toward_zero, away_from_zero, half_even (default), half_up"
     in
     fun () ->
       let rate =
         ok_or_exit
           (let%bind.Or_error price = Rate.price_of_string price in
            Rate.create
              ~base:(Amount.currency amount)
              ~quote
              ~price
              ~at:(Time_ns.now ())
              ~source:"cli")
       in
       print_endline (Amount.to_string (ok_or_exit (Rate.convert ~rounding rate amount))))
;;

let fee =
  Command.basic
    ~summary:"compute a fee: fixed + bps of the amount, clamped to min/max"
    ~readme:(fun () ->
      "money fee \"100.00 EUR\" -fixed 0.25 -bps 150 -min 0.30 -max 25 -side receivable")
    (let%map_open.Command amount = anon ("AMOUNT" %: amount_arg)
     and fixed = flag "fixed" (optional string) ~doc:"DECIMAL fixed part"
     and bps =
       flag
         "bps"
         (optional_with_default "0" string)
         ~doc:"BPS basis points, whole, decimal (0.5) or fraction (1/3); default 0"
     and min = flag "min" (optional string) ~doc:"DECIMAL minimum fee"
     and max = flag "max" (optional string) ~doc:"DECIMAL maximum fee"
     and side =
       flag
         "side"
         (optional_with_default Fee.Side.Receivable side_arg)
         ~doc:"SIDE payable (round down) or receivable (round up, default)"
     in
     fun () ->
       let currency = Amount.currency amount in
       let dec s = ok_or_exit (Amount.of_decimal_string currency s) in
       let bps_q = ok_or_exit (Rate.price_of_string bps) in
       let schedule =
         ok_or_exit
           (Fee.create
              currency
              ?fixed:(Option.map fixed ~f:dec)
              ~bps_q
              ?min:(Option.map min ~f:dec)
              ?max:(Option.map max ~f:dec))
       in
       print_endline (Amount.to_string (ok_or_exit (Fee.compute schedule ~side amount))))
;;

let currencies =
  Command.basic
    ~summary:"list the built-in currencies and their exponents"
    (let%map_open.Command () = return () in
     fun () ->
       List.iter (Currency.all ()) ~f:(fun c ->
         printf
           "%-16s %-6s %d\n"
           (Currency.to_string c)
           (String.lowercase (Sexp.to_string (Currency.Kind.sexp_of_t (Currency.kind c))))
           (Currency.exponent c)))
;;

let () =
  Command_unix.run
    (Command.group
       ~summary:"exact money arithmetic: conversions and fees"
       [ "convert", convert; "fee", fee; "currencies", currencies ])
;;
