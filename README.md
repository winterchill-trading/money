# money

Currencies, exact amounts, exchange rates and fees for payment systems, in OxCaml.

Every value is an integer count of minor units. There are no floats in the API, every
rounding step names its mode, and arithmetic between two currencies is an error rather than
a silent mix.

## Why separate

Ledgers, payment flows, card processing and risk rules all handle amounts, and each one
that grows its own decimal type ends up rounding differently. This library is the single
place that decides how many digits a currency has, how a string becomes an amount, and
which way a fee is rounded. It has no sibling dependencies except `fixed-decimal` (for
handing amounts to the trading stack), so everything else can depend on it.

## Quick start

```ocaml
open Money

let price = Rate.price_of_string "1.0845" |> Or_error.ok_exn

let eur_usd =
  Rate.create ~base:Currency.eur ~quote:Currency.usd ~price ~at:(Time_ns.now ()) ~source:"ecb"
  |> Or_error.ok_exn

let () =
  let amount = Amount.of_string "100.00 EUR" in
  let usd = Rate.convert eur_usd amount |> Or_error.ok_exn in
  print_endline (Amount.to_string usd);                       (* 108.45 USD *)
  let card = Fee.create Currency.eur ~fixed:(Amount.of_string "0.25 EUR") ~bps:150 |> Or_error.ok_exn in
  print_endline (Amount.to_string (Fee.compute card ~side:Receivable amount |> Or_error.ok_exn))
  (* 1.75 EUR *)
```

```
$ money convert "100.00 EUR" -to USD -price 1.0845
108.45 USD
$ money fee "10.01 EUR" -fixed 0.25 -bps 150 -side payable
0.40 EUR
$ money currencies
```

Build: `dune build`, test: `dune test`. No environment variables, no network.

## Modules

| Module | What it is |
|---|---|
| `Currency` | Code, optional network tag (`USDC@polygon`), minor-unit exponent, fiat/crypto kind. A process-wide registry holds ISO 4217 fiat and the common crypto assets; `register` adds more. |
| `Amount` | Currency plus an integer of minor units. Checked `add`/`sub`/`sum`, exact `scale`, `mul_ratio` and `mul_bps` with a rounding mode, exact text form `"12.34 EUR"`. |
| `Rounding` | `Down`, `Up`, `Toward_zero`, `Away_from_zero`, `Half_even` (default), `Half_up`. |
| `Rate` | Base, quote, exact rational price, timestamp, source. `convert` rounds once; `inverse` is exact. |
| `Fee` | Fixed part plus basis points, clamped to min/max. `Payable` rounds down, `Receivable` rounds up. |

## Representation

Amounts hold a Zarith integer of minor units. Zarith keeps integers that fit in 63 bits as
immediate OCaml ints and boxes only larger ones, so EUR (2), BTC (8) and USDC (6) amounts
stay plain machine ints while ETH (18 digits; 4.6 ETH is already 4.6e18 wei) widens instead
of overflowing or truncating. `Amount.minor_units_int` returns the `int` when it fits.

Currencies with an exponent of 8 or less convert exactly to and from `Fixed_decimal`
(`Amount.to_fixed_decimal`, `Amount.of_fixed_decimal`); a conversion that would lose
digits returns an error.

Built-in crypto currencies: `BTC` (8), `BTC@lightning` (11, millisatoshis), `ETH` (18),
`USDC` and `USDT` (6) without a network tag for off-chain balances, and `USDC@ethereum`,
`USDC@polygon`, `USDC@solana`, `USDT@ethereum`, `USDT@tron`. Equality is by the full text
form, so USDC on two networks never adds up by accident.

## Serialization

| Form | Currency | Amount | Rate, Fee |
|---|---|---|---|
| Text / sexp | `USDC@polygon` | `"12.34 EUR"` | record with price `1.0845` or `2000/2169`, time in UTC |
| JSON | `"EUR"` | `{"amount":"12.34","currency":"EUR"}` | every number a string, time ISO 8601 UTC |
| Bin_prot (`Stable.V1`) | text form | currency + minor units as a decimal string | wire record, price as text |

Reading a currency that is not registered fails, so an amount can never be read back with
a different exponent than it was written with. Applications that register their own
currencies must do so before reading data. The Bin_prot shape digest of every `Stable.V1`
type is pinned in the tests; a change to any of them fails the build.

## Verified

Expect tests on every module, Quickcheck properties for add/sub round trips, print/parse
identity (text, sexp, JSON, Bin_prot), rounding bounds for every mode, conversion
monotonicity and there-and-back conversion, fee bounds and side ordering, and a cram test
for the CLI. There is no external API, so nothing is verified live.

## Known gaps

- Basis points are whole numbers; a fee of 0.5 bps needs `Amount.mul_ratio`.
- No allocation of one amount into parts (splitting a bill); add when a caller needs it.
- The registry is global and not synchronised; register currencies at startup.
