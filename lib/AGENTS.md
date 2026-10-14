# AGENTS.md (lib/)

The `money` library, wrapped as `Money`. One `.ml` and one `.mli` per module.

- Values are integer minor units (Zarith). No floats in the API; `Rate` keeps an exact
  rational price.
- Every rounding step takes a `Rounding.t` argument. Default is `Half_even`.
- Operations across two currencies return an error, never a silent conversion.
- `Currency` holds a process-wide registry. `register` is idempotent; `freeze` stops new
  registrations. Tests that touch the registry belong in `test/frozen`.
- Modules with a `Stable` submodule (`fee.mli`, `amount.mli`, `currency.mli`, `rate.mli`,
  `rounding.mli`) are wire contracts. Do not change a pinned version; add the next one.

Build: `opam exec --switch 5.2.0+ox -- dune build --root .. @money/all`.
Tests for these modules are in `../test`.
