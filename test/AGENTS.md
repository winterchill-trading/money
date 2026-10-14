# AGENTS.md (test/)

Expect tests (ppx_expect, `-source-tree-root .`), Base_quickcheck properties and the cram test
of the CLI.

- One test file per library module (`test_<module>.ml`). Properties cover text and sexp round
  trips, rounding bounds, conversion monotonicity, fee bounds and allocation sums.
- `frozen/` is a separate library that checks the registry after `freeze`.
- `cli.t/run.t` is a cram test. Promote its output with `dune promote` on that file only.
- The suite needs no network and no environment variables.

Run: `opam exec --switch 5.2.0+ox -- dune build --root .. @money/runtest`.
