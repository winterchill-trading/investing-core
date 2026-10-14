open! Core
open Async_kernel
open Investing_core

let sym = Symbol.of_string
let date = Date.of_string
let price = Price.of_string

let close ?(origin = Close.Origin.Feed) s d p =
  { Close.symbol = sym s; date = date d; close = price p; origin }
;;

let peek d =
  match Deferred.peek d with
  | Some (Ok v) -> v
  | Some (Error e) -> Error.raise e
  | None -> failwith "not determined"
;;

let%expect_test "a feed close beats seed data whatever the order" =
  let h =
    Price_history.of_list
      [ close "AAPL" "2026-10-09" "100" ~origin:Seed
      ; close "AAPL" "2026-10-09" "101"
      ; close "AAPL" "2026-10-09" "99" ~origin:Seed
      ; close "AAPL" "2026-10-08" "98" ~origin:Simulated
      ; close "AAPL" "2026-10-08" "97" ~origin:Seed
      ]
  in
  List.iter [ "2026-10-08"; "2026-10-09" ] ~f:(fun d ->
    print_s [%sexp (Price_history.on h (sym "AAPL") (date d) : Close.t option)]);
  [%expect
    {|
    (((symbol AAPL) (date 2026-10-08) (close 97) (origin Seed)))
    (((symbol AAPL) (date 2026-10-09) (close 101) (origin Feed)))
    |}]
;;

let history =
  Price_history.of_list
    [ close "VT" "2026-10-01" "120"
    ; close "VT" "2026-10-02" "118.5"
    ; close "VT" "2026-10-05" "121.25"
    ; close "VT" "2026-10-06" "122"
    ; close "VT" "2026-10-07" "119.75"
    ]
;;

let%expect_test "quotes: fresh, stale, too old, missing" =
  List.iter [ "2026-10-07"; "2026-10-12"; "2026-10-18"; "2026-09-30" ] ~f:(fun today ->
    match Price_history.quote history (sym "VT") ~today:(date today) with
    | Ok q ->
      printf
        "%s: %s on %s, %s, change %s\n"
        today
        (Price.to_string (Price_history.Quote.price q))
        (Date.to_string q.close.date)
        (Sexp.to_string [%sexp (q.verdict : Staleness.Verdict.t)])
        (Option.value_map (Price_history.Quote.change q) ~default:"-" ~f:Q.to_string)
    | Error e ->
      printf "%s: %s\n" today (Sexp.to_string [%sexp (e : Price_history.Unavailable.t)]));
  [%expect
    {|
    2026-10-07: 119.75 on 2026-10-07, Fresh, change -9/4
    2026-10-12: 119.75 on 2026-10-07, (Stale(age_days 5)), change -9/4
    2026-10-18: (Too_old(symbol VT)(date 2026-10-07)(age_days 11))
    2026-09-30: (No_price(symbol VT))
    |}];
  (* A quote as of an earlier day uses the close of that day, not a later one. *)
  let q = Price_history.quote history (sym "VT") ~today:(date "2026-10-03") in
  print_s [%sexp (Result.map q ~f:Price_history.Quote.price : (Price.t, _) Result.t)];
  [%expect {| (Ok 118.5) |}]
;;

let%expect_test "windows and the low/high range" =
  let w = Price_history.window history (sym "VT") ~until:(date "2026-10-06") ~days:5 in
  print_s
    [%sexp
      (Or_error.map w ~f:(List.map ~f:(fun c -> c.Close.date)) : Date.t list Or_error.t)];
  print_s
    [%sexp
      (Price_history.low_high history (sym "VT") ~until:(date "2026-10-07") ~days:365
       : (Price.t * Price.t) option)];
  [%expect {|
    (Ok (2026-10-02 2026-10-05 2026-10-06))
    ((118.5 122))
    |}]
;;

let simulated =
  Market_data.Simulated.create
    ~seed:7
    ~anchor_date:(date "2026-10-07")
    ~start_prices:[ sym "SIMA", price "100"; sym "SIMB", price "25.5" ]
    ()
  |> Or_error.ok_exn
;;

let%expect_test "simulated closes are deterministic weekday prices" =
  let closes =
    Market_data.Simulated.closes
      simulated
      ~symbols:[ sym "SIMA"; sym "NOPE" ]
      ~from:(date "2026-10-01")
      ~to_:(date "2026-10-13")
    |> peek
  in
  List.iter closes ~f:(fun c ->
    printf
      "%s %s %s %s\n"
      (Symbol.to_string c.symbol)
      (Date.to_string c.date)
      (Date.day_of_week c.date |> Day_of_week.to_string)
      (Price.to_string c.close));
  [%expect
    {|
    SIMA 2026-10-01 THU 100.88
    SIMA 2026-10-02 FRI 99.72
    SIMA 2026-10-05 MON 98.86
    SIMA 2026-10-06 TUE 99.58
    SIMA 2026-10-07 WED 100
    SIMA 2026-10-08 THU 100.22
    SIMA 2026-10-09 FRI 99.24
    SIMA 2026-10-12 MON 99.76
    SIMA 2026-10-13 TUE 99.23
    |}]
;;

let%expect_test "a range query agrees with single closes, either side of the anchor" =
  Quickcheck.test
    (Quickcheck.Generator.tuple2 (Int.gen_incl (-60) 60) (Int.gen_incl 0 30))
    ~trials:200
    ~f:(fun (offset, len) ->
      let from = Date.add_days (date "2026-10-07") offset in
      let to_ = Date.add_days from len in
      let ranged =
        Market_data.Simulated.closes simulated ~symbols:[ sym "SIMB" ] ~from ~to_ |> peek
      in
      let single =
        List.filter_map (Date.dates_between ~min:from ~max:to_) ~f:(fun d ->
          Market_data.Simulated.close simulated (sym "SIMB") d)
      in
      [%test_result: Close.t list] ~expect:single ranged)
;;

let%expect_test "fixed source serves its history" =
  let source = Market_data.Fixed.create history in
  let closes =
    Market_data.Fixed.closes
      source
      ~symbols:[ sym "VT" ]
      ~from:(date "2026-10-05")
      ~to_:(date "2026-10-06")
    |> peek
  in
  print_s [%sexp (closes : Close.t list)];
  [%expect
    {|
    (((symbol VT) (date 2026-10-05) (close 121.25) (origin Feed))
     ((symbol VT) (date 2026-10-06) (close 122) (origin Feed)))
    |}]
;;
