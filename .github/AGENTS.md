# AGENTS.md (.github/)

`workflows/ci.yml` is the only workflow. It builds with the `ox-setup` action, pins
`fixed-decimal` from GitHub, runs the tests and examples, builds odoc (warnings fail) and
calls the shared `obj-magic` workflow.

- A new sibling dependency needs a line in the `pins:` block, in dependency order.
- Check a run with `gh run list --limit 1`; at most one `gh run watch <id> --exit-status`.
