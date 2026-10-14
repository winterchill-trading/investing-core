(lang dune 3.17)

(name investing-core)

(generate_opam_files true)

(license MIT)

(authors "WinterChill AI")

(maintainers "hello@winterchill.xyz")

(source
 (github winterchill-trading/investing-core))

(homepage "https://github.com/winterchill-trading/investing-core")

(bug_reports "https://github.com/winterchill-trading/investing-core/issues")

(documentation "https://github.com/winterchill-trading/investing-core#readme")

(package
 (name investing-core)
 (synopsis "Retail brokerage domain: instruments, end-of-day prices, fractional market orders, positions and their ledger bookings")
 (description
  "investing-core models a retail investing account without any storage or network code: instruments and their listings, end-of-day price history with staleness rules and a market-data source module type (with a deterministic simulated source), market orders by cash amount, by quantity or for a whole position with six-place fractional shares and directional rounding, an order state machine, positions with average cost basis and realised and unrealised profit and loss, a recurring-buy hook, a brokerage module type with a simulated broker that fills at the reference price with a configurable spread and delay, and the ledger entries for the cash legs (holds, settlement, release, proceeds). Requires the OxCaml compiler (through its money and fixed-decimal dependencies).")
 (tags
  (investing brokerage orders portfolio cost-basis ledger banking oxcaml))
 (depends
  oxcaml
  (ocaml
   (and
    (>= 5.2.0)
    (< 5.3~)))
  dune
  (core
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (async_kernel
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (ppx_jane
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (zarith
   (>= 1.12))
  fixed-decimal
  money
  ledger
  (expect_test_helpers_core
   (and
    :with-test
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (odoc :with-doc)))
