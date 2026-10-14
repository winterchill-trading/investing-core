# AGENTS.md: investing-core/lib

The `investing-core` library (module `Investing_core`, re-exported from `investing_core.ml`). Each
module has an `.mli` with odoc on every public value.

Build from the repository root: `opam exec --switch 5.2.0+ox -- dune build --root .. @investing-core/all`.

Rules that matter here:

- No I/O. Storage and brokers come in through `Broker.S` and `Market_data.S`; `Sim_broker` and
  `Market_data.Simulated` are the in-memory versions used by tests and the example.
- `Booking` builds ledger entries with the idempotency keys in the README's table. Keep the keys
  stable: a retry must produce the same key.
- An order records its settings (limits, staleness rules) when it is placed, never reads them
  later.
- A new module needs: the `.ml` and `.mli`, expect tests in `test/`, a re-export in
  `investing_core.ml`, and a row in the README's model table.
