open! Core
open Investing_core
module Amount = Money.Amount

let usd s = Amount.of_string (s ^ " USD")
let q = Quantity.of_string
let sym = Symbol.of_string "ACME"

let show (p : Position.t) =
  printf
    "held %s reserved %s basis %s avg %s realised %s\n"
    (Quantity.to_string p.quantity)
    (Quantity.to_string p.reserved)
    (Amount.to_string p.cost_basis)
    (Option.value_map (Position.average_cost p) ~default:"-" ~f:Price.to_string)
    (Amount.to_string p.realised)
;;

let%expect_test "average cost through buys, a partial sale and a full sale" =
  let p = Position.empty sym Money.Currency.usd in
  let p = Position.buy p ~quantity:(q "2") ~cost:(usd "200.00") |> Or_error.ok_exn in
  show p;
  let p = Position.buy p ~quantity:(q "1") ~cost:(usd "130.00") |> Or_error.ok_exn in
  show p;
  let p = Position.reserve p (q "1") |> Or_error.ok_exn in
  show p;
  print_s [%sexp (Position.reserve p (q "2.5") : Position.t Or_error.t)];
  let p, sale =
    Position.sell p ~quantity:(q "1") ~proceeds:(usd "120.00") |> Or_error.ok_exn
  in
  print_s [%sexp (sale : Position.Sale.t)];
  show p;
  let p, sale =
    Position.sell ~from_reserved:false p ~quantity:(q "2") ~proceeds:(usd "250.00")
    |> Or_error.ok_exn
  in
  print_s [%sexp (sale : Position.Sale.t)];
  show p;
  [%expect
    {|
    held 2 reserved 0 basis 200.00 USD avg 100 realised 0.00 USD
    held 3 reserved 0 basis 330.00 USD avg 110 realised 0.00 USD
    held 3 reserved 1 basis 330.00 USD avg 110 realised 0.00 USD
    (Error
     ("not enough shares available" (symbol ACME) (requested 2.5) (available 2)))
    ((cost_removed "110.00 USD") (realised "10.00 USD"))
    held 2 reserved 0 basis 220.00 USD avg 110 realised 10.00 USD
    ((cost_removed "220.00 USD") (realised "30.00 USD"))
    held 0 reserved 0 basis 0.00 USD avg - realised 40.00 USD
    |}]
;;

let%expect_test "valuation" =
  let p =
    Position.buy
      (Position.empty sym Money.Currency.usd)
      ~quantity:(q "0.5")
      ~cost:(usd "50.01")
    |> Or_error.ok_exn
  in
  print_s [%sexp (Position.value_at p (Price.of_string "120.5") : Position.Valuation.t)];
  [%expect
    {| ((value "60.25 USD") (unrealised "10.24 USD") (unrealised_ratio (1024/5001))) |}]
;;

(* Random buys and sells; whatever the order, the books must close. *)
type step =
  | Buy of int * int (** micro-shares, cents *)
  | Sell of int * int (** per mille of the held quantity, cents *)
[@@deriving sexp_of, quickcheck]

let gen_step =
  Quickcheck.Generator.union
    [ Quickcheck.Generator.map2
        (Int.gen_incl 1 5_000_000)
        (Int.gen_incl 0 100_000)
        ~f:(fun a b -> Buy (a, b))
    ; Quickcheck.Generator.map2
        (Int.gen_incl 0 1_000)
        (Int.gen_incl 0 100_000)
        ~f:(fun a b -> Sell (a, b))
    ]
;;

let%expect_test "cost basis is conserved: what was paid is held or realised" =
  Quickcheck.test
    (List.gen_with_length 20 gen_step)
    ~sexp_of:[%sexp_of: step list]
    ~f:(fun steps ->
      let cents = Amount.of_minor_units_int Money.Currency.usd in
      let p, paid, received =
        List.fold
          steps
          ~init:(Position.empty sym Money.Currency.usd, cents 0, cents 0)
          ~f:(fun (p, paid, received) step ->
            match step with
            | Buy (micro, c) ->
              let quantity = Quantity.of_micro micro |> Or_error.ok_exn in
              ( Position.buy p ~quantity ~cost:(cents c) |> Or_error.ok_exn
              , Amount.add_exn paid (cents c)
              , received )
            | Sell (per_mille, c) ->
              let quantity =
                Quantity.of_micro (Quantity.to_micro p.quantity * per_mille / 1_000)
                |> Or_error.ok_exn
              in
              let p, _ =
                Position.sell ~from_reserved:false p ~quantity ~proceeds:(cents c)
                |> Or_error.ok_exn
              in
              p, paid, Amount.add_exn received (cents c))
      in
      assert (not (Amount.is_negative p.cost_basis));
      (* paid = held basis + removed basis, and realised = received - removed *)
      [%test_result: Amount.t]
        ~expect:(Amount.sub_exn received paid)
        (Amount.sub_exn p.realised p.cost_basis);
      (* selling the rest leaves nothing behind *)
      let flat, _ =
        Position.sell ~from_reserved:false p ~quantity:p.quantity ~proceeds:(cents 0)
        |> Or_error.ok_exn
      in
      assert (Amount.is_zero flat.cost_basis);
      assert (Position.is_flat flat))
;;

let%expect_test "a partial sale keeps the average cost within rounding" =
  Quickcheck.test
    (Quickcheck.Generator.tuple3
       (Int.gen_incl 2 10_000_000)
       (Int.gen_incl 1 10_000_000)
       (Int.gen_incl 1 999))
    ~f:(fun (micro, cents, per_mille) ->
      let p =
        Position.buy
          (Position.empty sym Money.Currency.usd)
          ~quantity:(Quantity.of_micro micro |> Or_error.ok_exn)
          ~cost:(Amount.of_minor_units_int Money.Currency.usd cents)
        |> Or_error.ok_exn
      in
      let sold = Int.max 1 (micro * per_mille / 1_000) in
      let after, sale =
        Position.sell
          ~from_reserved:false
          p
          ~quantity:(Quantity.of_micro sold |> Or_error.ok_exn)
          ~proceeds:(Amount.zero Money.Currency.usd)
        |> Or_error.ok_exn
      in
      (* removed is the exact share of the basis, within half a cent *)
      let exact = Q.mul (Q.of_int cents) (Q.of_ints sold micro) in
      let removed = Amount.minor_units sale.cost_removed |> Q.of_bigint in
      assert (Q.leq (Q.abs (Q.sub removed exact)) (Q.of_ints 1 2));
      assert (not (Amount.is_negative after.cost_basis)))
;;

let%expect_test "average cost at eight or four decimals" =
  (* 3 shares for 100.00: 33.333333333... per share. *)
  let p = Position.empty sym Money.Currency.usd in
  let p = Position.buy p ~quantity:(q "3") ~cost:(usd "100.00") |> Or_error.ok_exn in
  let avg ?precision ?rounding () =
    Option.value_map
      (Position.average_cost ?precision ?rounding p)
      ~default:"-"
      ~f:Price.to_string
  in
  printf "default %s\n" (avg ());
  printf "eight %s\n" (avg ~precision:Position.Cost_precision.eight ());
  printf "four %s\n" (avg ~precision:Position.Cost_precision.four ());
  printf "four up %s\n" (avg ~precision:Position.Cost_precision.four ~rounding:Up ());
  (* 0.00 cost, and 0.01 over a million shares: zero at four decimals. *)
  let free =
    Position.buy
      (Position.empty sym Money.Currency.usd)
      ~quantity:(q "1")
      ~cost:(usd "0.00")
    |> Or_error.ok_exn
  in
  let tiny =
    Position.buy
      (Position.empty sym Money.Currency.usd)
      ~quantity:(q "1000000")
      ~cost:(usd "0.01")
    |> Or_error.ok_exn
  in
  List.iter [ free; tiny ] ~f:(fun p ->
    List.iter
      [ Position.Cost_precision.eight; Position.Cost_precision.four ]
      ~f:(fun precision ->
        printf
          "%s "
          (Option.value_map
             (Position.average_cost ~precision p)
             ~default:"-"
             ~f:Price.to_string));
    print_endline "");
  print_s
    [%sexp
      (List.map [ -1; 0; 4; 8; 9 ] ~f:Position.Cost_precision.of_decimals
       : Position.Cost_precision.t Or_error.t list)];
  [%expect
    {|
    default 33.33333333
    eight 33.33333333
    four 33.3333
    four up 33.3334
    - -
    0.00000001 -
    ((Error ("cost precision must be 0 to 8 decimals" (n -1))) (Ok 0) (Ok 4)
     (Ok 8) (Error ("cost precision must be 0 to 8 decimals" (n 9))))
    |}]
;;

let position_gen =
  let open Quickcheck.Generator.Let_syntax in
  (* 1 to a million shares (in millionths) and up to 10m: the average always fits a price,
     and goes down to 10^-8, below a four-decimal tick. *)
  let%map shares = Int.gen_incl 1_000_000 1_000_000_000_000
  and cents = Int.gen_incl 1 1_000_000_000 in
  Position.buy
    (Position.empty sym Money.Currency.usd)
    ~quantity:(Quantity.of_micro shares |> Or_error.ok_exn)
    ~cost:(Amount.of_minor_units_int Money.Currency.usd cents)
  |> Or_error.ok_exn
;;

let exact (p : Position.t) = Q.div (Amount.to_q p.cost_basis) (Quantity.to_q p.quantity)

let%test_unit "the default is half-even at eight decimals, as before" =
  Quickcheck.test position_gen ~f:(fun p ->
    [%test_result: Price.t option]
      (Position.average_cost p)
      ~expect:(Price.of_q ~rounding:Half_even (exact p) |> Result.ok))
;;

let%test_unit "four decimals: a multiple of 10^-4 within the rounding's bound" =
  let tick = Q.of_ints 1 10_000 in
  Quickcheck.test position_gen ~f:(fun p ->
    let x = exact p in
    List.iter Money.Rounding.all ~f:(fun rounding ->
      match Position.average_cost ~precision:Position.Cost_precision.four ~rounding p with
      | None -> assert (Q.( < ) x tick)
      | Some avg ->
        assert (Price.to_units avg mod 10_000 = 0);
        let a = Price.to_q avg in
        assert (Q.( < ) (Q.abs (Q.sub a x)) tick);
        (match rounding with
         | Down | Toward_zero -> assert (Q.( <= ) a x)
         | Up | Away_from_zero -> assert (Q.( >= ) a x)
         | Half_even | Half_up ->
           assert (Q.( <= ) (Q.abs (Q.sub a x)) (Q.div tick (Q.of_int 2))))))
;;
