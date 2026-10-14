(** Currencies, exact amounts, exchange rates and fees, with no floats.

    An {!Amount.t} is a {!Currency.t} and an arbitrary-precision integer of that
    currency's minor units (cents, satoshis, wei). Arithmetic between two currencies is an
    error, every operation that can lose a digit takes a {!Rounding.t}, an exchange
    {!Rate.t} is an exact rational that rounds once, and a {!Fee.t} schedule rounds in the
    operator's favour.

    {[
      open! Core
      open Money

      let () =
        let eur_usd =
          Rate.create
            ~base:Currency.eur
            ~quote:Currency.usd
            ~price:(Rate.price_of_string "1.0845" |> Or_error.ok_exn)
            ~at:Time_ns.epoch
            ~source:"example"
          |> Or_error.ok_exn
        in
        let bill = Amount.of_string "100.00 EUR" in
        (* 108.45 USD *)
        print_endline (Amount.to_string (Rate.convert eur_usd bill |> Or_error.ok_exn));
        (* 33.34 EUR, 33.33 EUR, 33.33 EUR *)
        Amount.split bill ~parts:3
        |> Or_error.ok_exn
        |> List.iter ~f:(fun part -> print_endline (Amount.to_string part))
      ;;
    ]}

    The complete program is [examples/quickstart.ml] in the source tree.

    {2 Currencies at startup}

    The currency registry is process-wide. Register any currency the built-ins lack before
    reading data, then call {!Currency.freeze}. *)

module Amount = Amount
module Currency = Currency

(** How integers and exact rationals are written as decimal text. Used by the other
    modules; exposed for callers that need the same layout. *)
module Decimal_text = Decimal_text

module Fee = Fee
module Rate = Rate
module Rounding = Rounding
