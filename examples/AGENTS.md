# AGENTS.md: investing-core/examples

`quickstart.ml`: one buy, from prices to the portfolio (plan, hold, fill, portfolio lines). Its output
is compared with `quickstart.expected` by a rule in `dune` (`@investing-core/runtest`). CI also runs
it with `dune exec ./examples/quickstart.exe`.

The README's "Usage" section shows the same flow. When an output changes on purpose, update
`quickstart.expected` and the README block in the same commit, and say why in the message.
