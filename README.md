# money

Currencies, exact amounts, exchange rates and fees for OCaml, with no floats anywhere.

An amount is a currency plus an arbitrary-precision integer of its minor units (cents,
satoshis, wei). Arithmetic between two currencies is an error rather than a silent mix,
every operation that can lose a digit names its rounding mode, and splitting an amount
never creates or loses a minor unit. The library targets the
[OxCaml](https://oxcaml.org) compiler and the Jane Street `core` stack.

## Install

The library is not on opam yet. With an OxCaml switch (`5.2.0+ox`) that has the ox opam
repository, pin it and its one non-opam dependency:

```sh
opam pin add fixed-decimal https://github.com/winterchill-trading/fixed-decimal.git
opam pin add money https://github.com/winterchill-trading/money.git
opam pin add money-cli https://github.com/winterchill-trading/money.git   # optional CLI
```

Then add `money` to the `libraries` of a dune stanza.

## Quick start

```ocaml
open! Core
open Money

let () =
  let eur_usd =
    Rate.create
      ~base:Currency.eur
      ~quote:Currency.usd
      ~price:(Rate.price_of_string "1.0845" |> Or_error.ok_exn)
      ~at:(Time_ns.now ())
      ~source:"ecb"
    |> Or_error.ok_exn
  in
  let bill = Amount.of_string "100.00 EUR" in
  (* 108.45 USD *)
  print_endline (Amount.to_string (Rate.convert eur_usd bill |> Or_error.ok_exn));
  (* 0.25 EUR plus 1.5 basis points, charged: rounds up to 0.27 EUR *)
  let card =
    Fee.create Currency.eur ~fixed:(Amount.of_string "0.25 EUR") ~bps_q:(Q.of_string "3/2")
    |> Or_error.ok_exn
  in
  print_endline
    (Amount.to_string (Fee.compute card ~side:Receivable bill |> Or_error.ok_exn));
  (* 33.34 EUR, 33.33 EUR, 33.33 EUR *)
  Amount.split bill ~parts:3
  |> Or_error.ok_exn
  |> List.iter ~f:(fun part -> print_endline (Amount.to_string part))
;;
```

The complete program, with its expected output checked by `dune test`, is
[examples/quickstart.ml](examples/quickstart.ml).

The `money-cli` package installs a `money` command:

```text
$ money convert "100.00 EUR" -to USD -price 1.0845
108.45 USD
$ money fee "10.01 EUR" -fixed 0.25 -bps 150 -side payable
0.40 EUR
$ money fee "1000.00 EUR" -bps 0.5
0.05 EUR
$ money currencies
```

Build: `dune build`, test: `dune test`. No environment variables, no network.

## Modules

| Module | What it is |
| --- | --- |
| `Currency` | Code, optional network tag (`USDC@polygon`), minor-unit exponent, fiat or crypto kind. A process-wide registry holds 40 ISO 4217 currencies and common crypto assets; `register` adds more, `freeze` fixes the set. |
| `Amount` | Currency plus an integer of minor units. Checked `add`/`sub`/`sum`, exact `scale`, `mul_ratio`, `mul_bps` and `mul_bps_q` (fractional basis points) with a rounding mode, `split` and `allocate`, exact text form `"12.34 EUR"`. |
| `Rounding` | `Down`, `Up`, `Toward_zero`, `Away_from_zero`, `Half_even` (default), `Half_up`. |
| `Rate` | Base, quote, exact rational price, timestamp, source. `convert` rounds once; `inverse` is exact. |
| `Fee` | Fixed part plus whole or fractional basis points, clamped to a minimum and maximum. `Payable` rounds down, `Receivable` rounds up. |
| `Decimal_text` | The decimal layout shared by the modules above. |

## Representation

Amounts hold a Zarith integer of minor units. Zarith keeps integers that fit in 63 bits as
immediate OCaml ints and boxes only larger ones, so EUR (2 digits), BTC (8) and USDC (6)
amounts stay machine ints while ETH (18 digits; 4.6 ETH is already 4.6e18 wei) widens
instead of overflowing or truncating. `Amount.minor_units_int` returns the `int` when it
fits.

Currencies with an exponent of 8 or less convert exactly to and from `Fixed_decimal`
values (`Amount.to_fixed_decimal`, `Amount.of_fixed_decimal`); a conversion that would
lose digits returns an error.

Built-in crypto currencies: `BTC` (8), `BTC@lightning` (11, millisatoshis), `ETH` (18),
`USDC` and `USDT` (6) without a network tag for off-chain balances, and `USDC@ethereum`,
`USDC@polygon`, `USDC@solana`, `USDT@ethereum`, `USDT@tron`. Equality is by the full text
form, so USDC on two networks never adds up by accident.

## Allocation

`Amount.allocate t ~ratios` divides an amount in proportion to integer ratios with the
largest remainder method: every part first gets its exact share rounded toward zero, then
the leftover minor units go one at a time to the parts with the largest discarded
remainder, earlier parts first on ties. The parts always sum to `t` and each one is
within a minor unit of its exact share. `Amount.split t ~parts` is the equal-ratio case:

```text
split "100.00 EUR" ~parts:3        -> 33.34, 33.33, 33.33
allocate "100.00 EUR" ~ratios:[1; 2; 4] -> 14.29, 28.57, 57.14
allocate "0.05 EUR" ~ratios:[3; 7]      -> 0.02, 0.03  (tie: earlier part)
```

## The currency registry

Parsing looks a currency up in a process-wide registry, so an amount can never be read
back with a different exponent than it was written with. The registry is an immutable map
behind an atomic reference: lookups never lock, and `Currency.register` publishes a new
map with compare-and-set, so it is safe from several domains or threads. The recommended
discipline is to register every extra currency at startup and then call
`Currency.freeze ()`. After that, registering a new currency returns an error, while
re-registering an identical one still succeeds, so modules that register during
initialisation keep working.

## Serialization

| Form | Currency | Amount | Rate, Fee |
| --- | --- | --- | --- |
| Text / sexp | `USDC@polygon` | `"12.34 EUR"` | record with price `1.0845` or `2000/2169`, bps `150`, `0.5` or `1/3`, time in UTC |
| JSON | `"EUR"` | `{"amount":"12.34","currency":"EUR"}` | every number a string, time ISO 8601 UTC |
| Bin_prot (`Stable`) | text form | currency + minor units as a decimal string | wire record, price and fractional bps as text |

Reading a currency that is not registered fails. `Fee.Stable.V1` is the original wire
shape with whole basis points and refuses to write a fractional schedule;
`Fee.Stable.V2` carries basis points as text. The Bin_prot shape digest of every
`Stable` type is pinned in the tests, so a change to any of them fails the build.

## Portability

The library needs OxCaml. The OxCaml-only pieces are:

- the layout annotation `('a : immediate)` on `Amount.to_fixed_decimal` and
  `Amount.of_fixed_decimal`, and the `fixed-decimal` dependency itself (which uses
  `[@zero_alloc]` and other OxCaml features);
- Jane Street packages at `v0.18~preview` (`core`, `ppx_jane`, `ppx_yojson_conv`), which
  exist only in the ox opam repository.

Everything else is plain OCaml 5: `Stdlib.Atomic`, Zarith, Yojson. A build on upstream
OCaml 5.x would need the two `Fixed_decimal` conversions moved to a separate sub-library
and Core v0.17; nothing in the arithmetic depends on OxCaml.

## Verified

Expect tests on every module; Quickcheck properties for add/sub round trips, print/parse
identity (text, sexp, JSON, Bin_prot), rounding bounds for every mode, conversion
monotonicity and there-and-back conversion, fee bounds and side ordering, fractional basis
points against whole ones, allocation sums, per-part bounds and the largest-remainder
rule; a separate test library for the registry freeze; a cram test for the CLI; and the
quickstart example run against its expected output.

## Known gaps

- `Amount.allocate` takes integer ratios. Ratios such as one third are expressed by
  scaling (`[1; 1; 1]`); a rational-ratio variant waits for a caller that needs it.
- There is no rate table or cross-rate derivation (EUR to JPY through USD); `Rate` is a
  single quote. Choosing a source and a staleness rule is an application decision.
- Plain OCaml (non-OxCaml) builds are not supported yet; see Portability.

## Releasing

Nothing is published yet. The plan for a release, once the dependencies are on opam:

1. Move the `## Unreleased` entries in [CHANGES.md](CHANGES.md) under a version heading.
2. `dune-release tag <version>` to tag the commit (the version comes from the tag; there
   is no version string in the sources).
3. `dune-release distrib`, `dune-release publish` and `dune-release opam pkg` /
   `dune-release opam submit` for both `money` and `money-cli`.

`fixed-decimal` must be published first.

API docs are built with `dune build @doc` (odoc). CI fails on any odoc warning, so run it before tagging.

## Used by

`ledger`, `payments-core`, `card-core`, `risk-rules` and `banking-provider` in the
winterchill-trading organisation.

## License

MIT, see [LICENSE](LICENSE).
