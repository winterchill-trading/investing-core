# AGENTS.md: investing-core

## Purpose

investing-core is the customer side of a retail brokerage as pure OCaml values: instruments,
end-of-day prices, fractional market orders, positions with average cost basis, and the ledger
entries for the cash side of each order. It has no storage and no network code; a service keeps
the values in its own store and reaches a broker or data vendor through the module types here.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | The `investing-core` library (module `Investing_core`): instruments, prices, orders, positions, `Booking`, the `Broker.S` and `Market_data.S` ports, and the simulated broker and market data |
| `test/` | Inline expect tests per module, Quickcheck properties, `test_flows.ml` (whole flows), `test_stable.ml` (pinned bin_prot digests), `helpers.ml` |
| `examples/` | `quickstart.ml`: one buy from prices to portfolio, its output checked against `quickstart.expected` |
| `doc/` | `index.mld`, the odoc landing page |
| `.github/` | `workflows/ci.yml` |

`README.md` holds the model table, the rules (rounding, sizing, prices, order life, cost basis),
the ledger entries and the portability notes. `CHANGES.md` keeps the notes per version.

## Build, test, docs

Run from the repository root, inside the workspace (`..` is the workspace root):

```sh
opam exec --switch 5.2.0+ox -- dune build --root .. @investing-core/all
opam exec --switch 5.2.0+ox -- dune build --root .. @investing-core/runtest
opam exec --switch 5.2.0+ox -- dune build --root .. @investing-core/doc
```

For parallel work, use `DUNE_BUILD_DIR=_build-investing-core-<task>`.

Standalone (outside the workspace), pin the organization libraries in dependency order, then this
one, as the README's quick start shows: `fixed-decimal`, `money`, `ledger`, `investing-core`.
The library needs the OxCaml compiler.

## Conventions

- Format only this repository: `dune build --root .. @investing-core/fmt --auto-promote`, after the
  tests pass. Never run `dune fmt` at the workspace root.
- Every module has an `.mli`. Use `open! Core`, labelled arguments and `ppx_jane`.
- Money rules live in the README's "Rules" section. Change the rule, its test and the README
  sentence in the same commit.
- `Price` and `Quantity` are `immediate` (an OxCaml layout annotation, the one OxCaml-specific
  syntax in the library); keep them so.
- Stable types have pinned digests in `test/test_stable.ml`. A changed digest means a new
  `Stable.V2`, and `V1` stays readable.
- Quickcheck properties check the money invariants (cost basis conservation, rounding direction,
  whole fills). A new rule gets a property, not only an example.
- odoc on every public value. User-visible changes get a line under the next version in `CHANGES.md`.

## Dependencies and dependents

- Sibling repositories: `fixed-decimal`, `money` and `ledger`. CI pins them from GitHub in that
  order (see CI). Other dependencies: core, async_kernel and ppx_jane (`v0.18~preview`), zarith,
  and expect_test_helpers_core for tests.
- Dependents in the organization: none yet.

## CI

`.github/workflows/ci.yml` runs on every push and pull request. It runs the `ox-setup` composite
action from `winterchill-trading/infra` with a `pins:` block for `fixed-decimal`, `money` and
`ledger`, then `dune build`, `dune test` and `dune exec ./examples/quickstart.exe`, then the
`obj-magic` reusable workflow from the same repository. The pin list must match the dependencies
in `investing-core.opam` and `lib/dune`. To check a run, use `gh run list --limit 1`, and at most
one `gh run watch <id> --exit-status`. Do not poll in a loop.

## Pitfalls

- Changes after 0.1.0 are additive (optional arguments on functions with a positional
  argument, new functions, new modules). Rounding to fewer decimals goes straight from
  the exact rational: rounding an already-rounded eight-decimal value again can differ
  from rounding once (double rounding), so `Position.average_cost ~precision` never does.

- `Identifiable.Make` needs `bin_io` in the type. For a validated string id, put `Binable` with
  the validator inside `T` itself, then `module Stable = struct module V1 = T end`. After the
  include, comparison operators are the id's, so string functions on it stop type-checking.
- `Fixed_decimal.S` types derive no `bin_io`. Store the units as an `int` and re-check the range
  on decode.
- A deterministic random walk with rounding at each step differs by direction. The range query
  must step the same way as the single-day function, and a property pins range = single days.
- Simulator settings read at decision time change orders already waiting. Snapshot them into each
  order when it is placed.
- `Date.of_time` takes `Time_float.t`; for `Time_ns.t` use `Time_ns.to_date ~zone`.
- `dune promote` after a raising test writes an `[@@expect.uncaught_exn]` block. Delete it after the fix.

## Where to read more

- `README.md` (model, rules, ledger entries, simulated market data, tests, portability, known gaps).
- `doc/index.mld` (the odoc landing page).
- `../oxcaml-claude-skills/AGENTS.md` (workspace guide), the skill
  `../oxcaml-claude-skills/skills/banking-standards/` for the banking rules that apply to money handling,
  and the section "investing-core" of `../oxcaml-claude-skills/GOTCHAS.md`.

## Never do

- Install an opam package that changes the compiler, `core`, `base`, `async` or `ppx_jane` on the
  shared `5.2.0+ox` switch. Dry-run first: `opam install --switch 5.2.0+ox --dry-run <pkg>`.
- Add network or storage code to the library, or a real broker or data-vendor adapter; those live
  outside it and implement `Broker.S` and `Market_data.S`.
- Publish, tag or release. The README's "Releasing" section gives the order: `fixed-decimal`,
  `money`, `ledger`, then this library.
- Commit credentials or account data.
