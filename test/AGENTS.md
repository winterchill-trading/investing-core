# AGENTS.md: investing-core/test

Inline tests for every module (ppx_expect with `-source-tree-root .`), Quickcheck properties,
`test_flows.ml` for whole flows (buy, fill, sell), and `test_stable.ml` for the pinned bin_prot
digests. `helpers.ml` holds shared fixtures.

Run from the repository root: `opam exec --switch 5.2.0+ox -- dune build --root .. @investing-core/runtest`.

Rules that matter here:

- Each property states an invariant from the README's "Tests" section. A new rule gets a property.
- Promote expect output with `dune promote` only after reading the diff. Delete any
  `[@@expect.uncaught_exn]` block a failing test left behind.
- A changed digest in `test_stable.ml` means a new `Stable.V2`, not an edited `V1`.
