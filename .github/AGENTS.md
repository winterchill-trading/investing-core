# AGENTS.md: investing-core/.github

`workflows/ci.yml`: the push and pull request workflow. It runs `ox-setup` from
`winterchill-trading/infra` (at `@main`) with a `pins:` block for `fixed-decimal`, `money` and
`ledger`, then `dune build`, `dune test`, `dune exec ./examples/quickstart.exe`, and the
`obj-magic` reusable workflow.

When the library's dependencies change, change the pin list in the same commit and keep it in
dependency order (`fixed-decimal` first). To check a run, use
`gh run list --limit 1`, and at most one `gh run watch <id> --exit-status`.
