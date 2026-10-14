(* Converting, charging a fee and splitting a bill, exactly. *)

open! Core
open Money

let ok = Or_error.ok_exn

let () =
  (* A currency the built-in registry lacks, registered once at startup. *)
  let eurc = Currency.register ~code:"EURC" ~exponent:6 ~kind:Crypto () |> ok in
  Currency.freeze ();
  let eur_usd =
    Rate.create
      ~base:Currency.eur
      ~quote:Currency.usd
      ~price:(Rate.price_of_string "1.0845" |> ok)
      ~at:Time_ns.epoch
      ~source:"example"
    |> ok
  in
  let bill = Amount.of_string "100.00 EUR" in
  printf "converted   %s\n" (Amount.to_string (Rate.convert eur_usd bill |> ok));
  (* 0.25 EUR plus 1.5 basis points, charged to a customer: rounds up. *)
  let card =
    Fee.create
      Currency.eur
      ~fixed:(Amount.of_string "0.25 EUR")
      ~bps_q:(Q.of_string "3/2")
    |> ok
  in
  printf
    "fee         %s\n"
    (Amount.to_string (Fee.compute card ~side:Receivable bill |> ok));
  printf
    "split       %s\n"
    (Amount.split bill ~parts:3
     |> ok
     |> List.map ~f:Amount.to_string
     |> String.concat ~sep:", ");
  printf
    "allocate    %s\n"
    (Amount.allocate bill ~ratios:[ 1; 2; 4 ]
     |> ok
     |> List.map ~f:Amount.to_string
     |> String.concat ~sep:", ");
  printf "registered  %s\n" (Amount.to_string (Amount.of_minor_units_int eurc 1_500_000))
;;
