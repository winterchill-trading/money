# AGENTS.md (bin/)

The `money` command-line tool (opam package `money-cli`), with subcommands `convert`,
`fee` and `currencies`. `main.ml` only parses arguments and calls the library in `../lib`;
keep arithmetic there.

- Output is plain text and must stay stable: `test/cli.t/run.t` is a cram test of it.
- After a change, `dune promote` only the cram file you meant to change.

Build: `opam exec --switch 5.2.0+ox -- dune build --root .. @money/all`.
