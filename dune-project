(lang dune 3.17)

(name money)

(generate_opam_files true)

(license MIT)

(authors "WinterChill AI")

(maintainers "hello@winterchill.xyz")

(source
 (github winterchill-trading/money))

(homepage "https://github.com/winterchill-trading/money")

(bug_reports "https://github.com/winterchill-trading/money/issues")

(documentation "https://github.com/winterchill-trading/money#readme")

(package
 (name money)
 (synopsis "Currencies, exact amounts, exchange rates and fees with no floats")
 (description
  "Money represents an amount as an arbitrary-precision integer of a currency's minor units, so EUR cents, BTC satoshis and ETH wei are all exact. Arithmetic across currencies is an error, every rounding step names its mode, exchange rates are exact rationals that round once, fee schedules take fractional basis points and round in the operator's favour, and allocation splits an amount into parts without losing a minor unit. A registry of ISO 4217 and common crypto currencies (with chain tags such as USDC@polygon) can be extended and then frozen. Sexp, JSON (numbers as strings) and versioned bin_prot forms are provided. Requires the OxCaml compiler.")
 (tags
  (money currency decimal finance payments oxcaml))
 (depends
  (ocaml-variants
   (and
    (>= 5.2.0+ox)
    (< 5.2.1~)))
  dune
  (core
   (>= v0.18~preview))
  (ppx_jane
   (>= v0.18~preview))
  (ppx_yojson_conv
   (>= v0.18~preview))
  (ppx_yojson_conv_lib
   (>= v0.18~preview))
  (yojson
   (>= 2.0.0))
  (zarith
   (>= 1.12))
  fixed-decimal
  (core_unix
   (>= v0.18~preview))
  (odoc :with-doc)))
