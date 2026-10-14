# AGENTS.md

Guide for AI coding agents working in this repository. Read this first; the subdirectory
`AGENTS.md` files add detail for `lib/`, `bin/`, `examples/`, `test/` and `.github/`.
The workspace-wide guide is `../oxcaml-claude-skills/AGENTS.md`.

## Purpose

`money` is an OCaml library for currencies, exact amounts, exchange rates and fees in
payment systems. Every value is an integer count of minor units, the API has no floats,
every rounding step names its mode, and arithmetic across two currencies is an error.
The `money` command (package `money-cli`) prints conversions, fees and the registry.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | The library, wrapped as `Money`: `Currency`, `Amount`, `Rounding`, `Rate`, `Fee`, `Decimal_text` |
| `bin/` | The `money` command: `convert`, `fee`, `currencies` |
| `examples/` | `quickstart.ml`, run by `dune test` and diffed against `quickstart.expected` |
| `test/` | Expect tests, Quickcheck properties, `test/frozen` (registry freeze), `test/cli.t` (cram test of the CLI) |
| `.github/` | CI workflow |
| `dune-project` | Source of truth for package metadata; `dune build` regenerates `money.opam` and `money-cli.opam` |
| `CHANGES.md`, `README.md`, `LICENSE` | Changelog, user docs, MIT licence |

## Build, test, docs

Inside the workspace (the sibling checkouts and the shared `5.2.0+ox` switch are required):

```sh
opam exec --switch 5.2.0+ox -- dune build --root .. @money/all
opam exec --switch 5.2.0+ox -- dune build --root .. @money/runtest
opam exec --switch 5.2.0+ox -- dune build --root .. @money/doc
```

Parallel work: prefix the commands with `DUNE_BUILD_DIR=_build-money`.

Standalone, after the published packages are available:

```sh
opam repo add winterchill https://github.com/winterchill-trading/opam-repository.git
opam install --deps-only --with-test .
dune build && dune test
```

`fixed-decimal` is installed from the `winterchill` opam repository in that case.

## Conventions

- Every module has an `.mli`; public values carry odoc comments. Code is `open! Core`,
  labelled arguments, ppx_jane derivations.
- Serialization: `Stable.V1` and `Stable.V2` bin_io modules have pinned digests. A changed
  wire shape must fail a test. Add a new version instead of editing a pinned one.
- Tests: expect tests per module and Base_quickcheck properties. Expect output is promoted
  one file at a time with `dune promote <file>`.
- Formatting: `opam exec --switch 5.2.0+ox -- dune build --root .. @money/fmt --auto-promote`.
  Never run `dune fmt` at the workspace root; it reformats every sibling repository.
- Comments for humans: explain non-obvious choices where they are made.
- `CHANGES.md`: add a line under `## Unreleased` for every user-visible change.

## Dependencies and dependents

- Depends on `fixed-decimal` (pinned from GitHub in CI). External: `core`, `zarith`,
  `yojson`, `ppx_jane`, `ppx_yojson_conv`; `core_unix` for the CLI only.
- Used by `ledger` and `payments-core`, and by the other banking libraries.
- After an API change, build the dependents: `dune build --root .. @ledger/all @payments-core/all`.

## CI

`.github/workflows/ci.yml` runs the `ox-setup` action (cached opam switch, `fixed-decimal`
pinned to its GitHub URL), then `dune build`, `dune test`, `dune build @examples/runtest`,
and an odoc build in which any warning fails the job. The shared `obj-magic` workflow
runs last. To check a run: `gh run list --limit 1`, then at most one
`gh run watch <id> --exit-status`. Do not poll.

## Pitfalls

- A first-class module over `Fixed_decimal.S` needs a layout annotation (`type (a : immediate)`
  in the `.ml`, `('a : immediate)` in the `.mli`); a bare `'a` fails with "layout of the first is value".
- Zarith keeps values that fit in 63 bits immediate, so minor units cost nothing for fiat,
  BTC and USDC and widen only for 18-digit ETH.
- `include Comparable.Make (...)` shadows `<`, `>`, `min` and `max` for the rest of the file:
  put it at the end, just before `Stable`.
- An odoc `{v ... v}` block must be indented at the column of its opening brace or odoc warns,
  and CI treats warnings as errors.
- `Amount.allocate` takes integer ratios only (see Known gaps in the README).

## Where to read more

- `README.md`: quick start, modules, representation, releasing, known gaps.
- `../specs/repos/money.md`: role of the library in the banking stack.
- `../oxcaml-claude-skills/skills/banking-standards/` and `janestreet-ocaml-style/`.
- `../oxcaml-claude-skills/GOTCHAS.md`, section "Banking libraries".

## Never do

- Install or upgrade opam packages that change the compiler, `core`, `base`, `async` or
  `ppx_jane` on the shared switch. Run `opam install --switch 5.2.0+ox --dry-run <pkg>` first
  and stop if the plan touches any of them.
- Publish, tag or release, or add `pin-depends` or a forked copy of another package.
- Commit credentials. Values come from the environment only.
- Print secrets, or poll CI in a loop.
