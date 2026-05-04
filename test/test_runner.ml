open Windtrap
module L = Sift_runner.Live_worktree
module G = Sift_git
module R = Sift_review
module F = Sift_feature
module D = Sift_diff

let expect_ok ~msg pp = function
  | Ok x -> x
  | Error e -> failf "%s: expected Ok _, got %a" msg pp e

let expect_invalid_arg ~msg f =
  let raised =
    try
      f ();
      false
    with Invalid_argument _ -> true
  in
  is_true ~msg raised

let fp s = G.Fingerprint.v s
let revision s = F.Revision.v s
let line kind text = D.Line.make kind ~text
let context text = line D.Line.Context text
let removed text = line D.Line.Removed text
let added text = line D.Line.Added text

let hunk ?(old_count = 1) ?(new_count = 1) lines =
  expect_ok ~msg:"hunk" D.Error.pp
    (D.Hunk.make ~old_start:1 ~old_count ~new_start:1 ~new_count lines)

let file path content =
  expect_ok ~msg:"file" D.Error.pp
    (D.File.make ~old_path:path ~new_path:path ~status:D.File.Modified content)

let feature ?(tip = "WORKTREE") ?(value = "2") () =
  let diff =
    D.make
      [
        file "lib/core.ml"
          (D.File.Text
             [
               hunk ~old_count:2 ~new_count:2
                 [
                   context "let stable = true";
                   removed "let value = 1";
                   added ("let value = " ^ value);
                 ];
             ]);
      ]
  in
  F.v ~base:(revision "main") ~tip:(revision tip) ~diff ()

let review ?tip ?value () = R.v ~feature:(feature ?tip ?value ()) ~cr_items:[]

let load ?tip ?value fingerprint =
  {
    L.input = { G.feature = feature ?tip ?value (); cr_items = [] };
    fingerprint;
  }

let expect_no_actions ~msg = function
  | [] -> ()
  | _ -> failf "%s: expected no actions" msg

let expect_one_load_fingerprint ~msg = function
  | [ L.Load_fingerprint request ] -> request
  | _ -> failf "%s: expected Load_fingerprint" msg

let expect_one_load_worktree ~msg fingerprint = function
  | [ L.Load_worktree (request, actual) ] ->
      is_true ~msg:(msg ^ " fingerprint")
        (G.Fingerprint.equal fingerprint actual);
      request
  | _ -> failf "%s: expected Load_worktree" msg

let expect_one_replace_review ~msg = function
  | [ L.Replace_review review ] -> review
  | _ -> failf "%s: expected Replace_review" msg

let expect_one_error ~msg expected = function
  | [ L.Report_error actual ] -> equal ~msg string expected actual
  | _ -> failf "%s: expected Report_error" msg

let expect_stale_source_result ~msg = function
  | Ok None -> ()
  | Ok (Some _) -> failf "%s: expected stale source result" msg
  | Error message -> failf "%s: unexpected source error: %s" msg message

let expect_loaded_source_review ~msg = function
  | Ok (Some review) -> review
  | Ok None -> failf "%s: expected loaded source review" msg
  | Error message -> failf "%s: unexpected source error: %s" msg message

let expect_source_load_error ~msg expected = function
  | Error actual -> equal ~msg string expected actual
  | Ok None | Ok (Some _) -> failf "%s: expected source load error" msg

let expect_source_started ~msg = function
  | Ok started -> started
  | Error message -> failf "%s: unexpected source start error: %s" msg message

let expect_source_start_error ~msg expected = function
  | Error actual -> equal ~msg string expected actual
  | Ok _ -> failf "%s: expected source start error" msg

let live_tests =
  [
    test "disabled watch does nothing" (fun () ->
        let live =
          L.make Off ~review:(review ~tip:"feature" ()) ~fingerprint:None ()
        in
        let _live, actions = L.step (Tick 0.) live in
        expect_no_actions ~msg:"tick" actions);
    test "enabled watch polls and ignores unchanged fingerprint" (fun () ->
        let a = fp "a" in
        let live =
          L.make Worktree ~review:(review ()) ~fingerprint:(Some a) ()
        in
        let live, actions = L.step (Tick 0.) live in
        let request = expect_one_load_fingerprint ~msg:"first tick" actions in
        let live, actions =
          L.step (Fingerprint_loaded (0.1, request, Ok a)) live
        in
        expect_no_actions ~msg:"unchanged fingerprint" actions;
        let _live, actions = L.step (Tick 1.) live in
        ignore
          (expect_one_load_fingerprint ~msg:"second tick" actions : L.request));
    test "changed fingerprint reloads after debounce" (fun () ->
        let a = fp "a" in
        let b = fp "b" in
        let live =
          L.make ~debounce:0.5 Worktree ~review:(review ())
            ~fingerprint:(Some a) ()
        in
        let live, actions = L.step (Tick 0.) live in
        let poll = expect_one_load_fingerprint ~msg:"poll" actions in
        let live, actions =
          L.step (Fingerprint_loaded (0.1, poll, Ok b)) live
        in
        expect_no_actions ~msg:"pending" actions;
        let live, actions = L.step (Tick 0.7) live in
        let reload = expect_one_load_worktree ~msg:"reload" b actions in
        let live, actions =
          L.step (Worktree_loaded (reload, Ok (load ~value:"3" b))) live
        in
        let refreshed = expect_one_replace_review ~msg:"replace" actions in
        is_true ~msg:"review updated" (R.equal refreshed (L.review live)));
    test
      "stale fingerprint and reload results are ignored after mutation starts"
      (fun () ->
        let a = fp "a" in
        let b = fp "b" in
        let live =
          L.make ~debounce:0. Worktree ~review:(review ()) ~fingerprint:(Some a)
            ()
        in
        let live, actions = L.step (Tick 0.) live in
        let poll = expect_one_load_fingerprint ~msg:"poll" actions in
        let live, source =
          expect_source_started ~msg:"source started"
            (L.source_mutation_started ~fingerprint:a live)
        in
        let live, actions =
          L.step (Fingerprint_loaded (0.1, poll, Ok b)) live
        in
        expect_no_actions ~msg:"stale poll ignored" actions;
        let live, active = L.source_mutation_aborted live source in
        is_true ~msg:"source abort active" active;
        let live, actions = L.step (Tick 1.) live in
        let poll = expect_one_load_fingerprint ~msg:"new poll" actions in
        let live, actions =
          L.step (Fingerprint_loaded (1.1, poll, Ok b)) live
        in
        expect_no_actions ~msg:"pending b" actions;
        let live, actions = L.step (Tick 1.2) live in
        let reload = expect_one_load_worktree ~msg:"reload b" b actions in
        let live, _source =
          expect_source_started ~msg:"source started during reload"
            (L.source_mutation_started ~fingerprint:a live)
        in
        let _live, actions =
          L.step (Worktree_loaded (reload, Ok (load ~value:"3" b))) live
        in
        expect_no_actions ~msg:"stale reload ignored" actions);
    test "reload with unexpected fingerprint is ignored" (fun () ->
        let a = fp "a" in
        let b = fp "b" in
        let c = fp "c" in
        let initial = review () in
        let live =
          L.make ~debounce:0. Worktree ~review:initial ~fingerprint:(Some a) ()
        in
        let live, actions = L.step (Tick 0.) live in
        let poll = expect_one_load_fingerprint ~msg:"poll" actions in
        let live, actions =
          L.step (Fingerprint_loaded (0.1, poll, Ok b)) live
        in
        expect_no_actions ~msg:"pending b" actions;
        let live, actions = L.step (Tick 0.2) live in
        let reload = expect_one_load_worktree ~msg:"reload b" b actions in
        let live, actions =
          L.step (Worktree_loaded (reload, Ok (load ~value:"3" c))) live
        in
        expect_no_actions ~msg:"mismatched reload ignored" actions;
        is_true ~msg:"review preserved" (R.equal initial (L.review live));
        let _live, actions = L.step (Tick 0.3) live in
        ignore
          (expect_one_load_fingerprint ~msg:"poll after mismatch" actions
            : L.request));
    test "source mutation requests ignore stale reloads and block polling"
      (fun () ->
        let a = fp "a" in
        let b = fp "b" in
        let c = fp "c" in
        let initial = review () in
        let live = L.make Worktree ~review:initial ~fingerprint:(Some a) () in
        let live, first =
          expect_source_started ~msg:"first source started"
            (L.source_mutation_started ~fingerprint:a live)
        in
        let live, actions = L.step (Tick 1.) live in
        expect_no_actions ~msg:"poll blocked by source mutation" actions;
        let live, second =
          expect_source_started ~msg:"second source started"
            (L.source_mutation_started ~fingerprint:a live)
        in
        let live, result =
          L.source_mutation_loaded live first (Ok (load ~value:"3" b))
        in
        expect_stale_source_result ~msg:"first mutation stale" result;
        is_true ~msg:"stale mutation preserved review"
          (R.equal initial (L.review live));
        let live, result =
          L.source_mutation_loaded live second (Ok (load ~value:"4" c))
        in
        let refreshed =
          expect_loaded_source_review ~msg:"second mutation loaded" result
        in
        is_true ~msg:"review updated" (R.equal refreshed (L.review live)));
    test "source mutation rejects stale worktree fingerprints" (fun () ->
        let a = fp "a" in
        let b = fp "b" in
        let live =
          L.make Worktree ~review:(review ()) ~fingerprint:(Some a) ()
        in
        expect_source_start_error ~msg:"stale source start"
          "cannot write source CRs because the worktree changed; wait for Sift \
           to refresh and try again"
          (L.source_mutation_started ~fingerprint:b live));
    test "source mutation transitions explicit review to live worktree"
      (fun () ->
        let b = fp "b" in
        let live =
          L.make Off ~review:(review ~tip:"feature" ()) ~fingerprint:None ()
        in
        let live, request =
          expect_source_started ~msg:"source started"
            (L.source_mutation_started live)
        in
        let live, result =
          L.source_mutation_loaded live request (Ok (load b))
        in
        let refreshed =
          expect_loaded_source_review ~msg:"source mutation loaded" result
        in
        is_true ~msg:"mode worktree"
          (match L.mode live with Worktree -> true | Off -> false);
        is_true ~msg:"review updated" (R.equal refreshed (L.review live)));
    test "source mutation reload errors enter recoverable worktree mode"
      (fun () ->
        let initial = review ~tip:"feature" () in
        let live = L.make Off ~review:initial ~fingerprint:None () in
        let live, request =
          expect_source_started ~msg:"source started"
            (L.source_mutation_started live)
        in
        let live, result =
          L.source_mutation_loaded live request (Error "reload failed")
        in
        expect_source_start_error ~msg:"not loaded yet"
          "cannot write source CRs before the worktree review reloads"
          (L.source_mutation_started ~fingerprint:(fp "changed") live);
        expect_source_load_error ~msg:"source reload error" "reload failed"
          result;
        is_true ~msg:"mode worktree"
          (match L.mode live with Worktree -> true | Off -> false);
        is_true ~msg:"review preserved" (R.equal initial (L.review live)));
    test "reload errors keep current review and report error" (fun () ->
        let a = fp "a" in
        let b = fp "b" in
        let initial = review () in
        let live =
          L.make ~debounce:0. Worktree ~review:initial ~fingerprint:(Some a) ()
        in
        let live, actions = L.step (Tick 0.) live in
        let poll = expect_one_load_fingerprint ~msg:"poll" actions in
        let live, actions =
          L.step (Fingerprint_loaded (0.1, poll, Ok b)) live
        in
        expect_no_actions ~msg:"pending" actions;
        let live, actions = L.step (Tick 0.2) live in
        let reload = expect_one_load_worktree ~msg:"reload" b actions in
        let live, actions =
          L.step (Worktree_loaded (reload, Error "reload failed")) live
        in
        expect_one_error ~msg:"error" "reload failed" actions;
        is_true ~msg:"review preserved" (R.equal initial (L.review live)));
    test "empty fingerprints are rejected" (fun () ->
        expect_invalid_arg ~msg:"empty fingerprint" (fun () ->
            ignore (G.Fingerprint.v "" : G.Fingerprint.t)));
  ]

let () = run "sift.runner" [ group "live worktree" live_tests ]
