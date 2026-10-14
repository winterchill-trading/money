# AGENTS.md (examples/)

`quickstart.ml` is the worked example from the README. `dune test` runs it and compares its
output with `quickstart.expected`.

- If the output changes on purpose, update `quickstart.expected` in the same commit as the
  change and say why in the commit message.
- Keep the example small; it is the first code a reader copies.

Run: `opam exec --switch 5.2.0+ox -- dune build --root .. @money/examples/runtest`.
