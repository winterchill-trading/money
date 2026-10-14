# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## Unreleased

## 0.1.0

First version prepared for opam; not yet published.

### Added

- `Currency`: registry of ISO 4217 fiat currencies and common crypto assets with network
  tags; `register`, `all`; lock-free, domain-safe registry with `freeze` and `is_frozen`.
- `Amount`: exact minor units over Zarith; checked arithmetic; `scale`, `mul_ratio`,
  `mul_bps`, `mul_bps_q` (fractional basis points); `split` and `allocate` with the
  largest remainder method; text, sexp, JSON and `Stable.V1` bin_prot forms;
  `Fixed_decimal` conversions.
- `Rounding`: six modes over Zarith integers and rationals.
- `Rate`: exact rational prices, single-rounding `convert`, exact `inverse`.
- `Fee`: fixed part plus whole or fractional basis points, clamped, rounded by side;
  `Stable.V1` (whole basis points) and `Stable.V2` (fractional) wire shapes.
- `money-cli` package with the `money` command (`convert`, `fee`, `currencies`).
- Quickstart example built and run by the test suite.

### Deprecated

- `Fee.bps`: use `Fee.bps_q`, which also handles fractional basis points.
