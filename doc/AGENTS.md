# AGENTS.md: investing-core/doc

`index.mld`, the odoc landing page of the `investing-core` package (`{0 investing-core}`). `dune`
declares the documentation package.

Build from the repository root: `opam exec --switch 5.2.0+ox -- dune build --root .. @investing-core/doc`.

Keep the summary in step with the README's first paragraph. Module-level detail belongs in the
odoc comments in `lib/`, not here.
