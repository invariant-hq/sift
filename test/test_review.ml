open Windtrap
module R = Sift_review
module C = Sift_crs
module D = Sift_diff
module F = Sift_feature

let pp_to_string pp x = Format.asprintf "%a" pp x

let expect_ok ~msg pp = function
  | Ok x -> x
  | Error e -> failf "%s: expected Ok _, got %a" msg pp e

let expect_error ~msg = function
  | Error e -> e
  | Ok _ -> failf "%s: expected Error _" msg

let expect_some ~msg = function
  | Some x -> x
  | None -> failf "%s: expected Some _" msg

let expect_none ~msg = function
  | None -> ()
  | Some _ -> failf "%s: expected None" msg

let expect_invalid_arg ~msg f =
  let raised =
    try
      f ();
      false
    with Invalid_argument _ -> true
  in
  is_true ~msg raised

let equal_float ~msg expected actual =
  is_true ~msg (abs_float (expected -. actual) < 0.000001)

let handle s = expect_ok ~msg:("handle " ^ s) C.Error.pp (C.Handle.of_string s)

let comment ?(reporter = "alice") body =
  let header = C.Header.make ~reporter:(handle reporter) () in
  C.Comment.make ~header ~body

let span ?(line = 1) ?(col = 0) () =
  C.Span.v ~start_offset:0 ~stop_offset:1 ~start_line:line ~start_col:col
    ~stop_line:line ~stop_col:(col + 1) ()

let cr_item ?(path = "lib/core.ml") ?(line = 1) ?(body = "check this") raw =
  C.Item.make ~path ~syntax:C.Syntax.Ocaml_block ~span:(span ~line ()) ~raw
    (Ok (comment body))

let invalid_cr_item raw =
  let error =
    expect_error ~msg:"invalid CR item" (C.Parser.comment "CR two words: bad")
  in
  C.Item.make ~path:"lib/core.ml" ~syntax:C.Syntax.Ocaml_block
    ~span:(span ~line:20 ()) ~raw (Error error)

let line kind text = D.Line.make kind ~text
let context text = line D.Line.Context text
let added text = line D.Line.Added text
let removed text = line D.Line.Removed text

let hunk ?(old_start = 1) ?(old_count = 1) ?(new_start = 1) ?(new_count = 1)
    lines =
  expect_ok ~msg:"hunk" D.Error.pp
    (D.Hunk.make ~old_start ~old_count ~new_start ~new_count lines)

let file ?old_path ?new_path ~status content =
  expect_ok ~msg:"file" D.Error.pp
    (D.File.make ?old_path ?new_path ~status content)

let revision s = F.Revision.v s

let first_hunk () =
  hunk ~old_start:1 ~old_count:2 ~new_start:1 ~new_count:3
    [
      context "let stable = true";
      removed "let value = 1";
      added "let value = 2";
      added "let extra = 3";
    ]

let second_hunk () =
  hunk ~old_start:10 ~old_count:1 ~new_start:10 ~new_count:1
    [ removed "old branch"; added "new branch" ]

let sample_diff () =
  D.make
    [
      file ~old_path:"lib/core.ml" ~new_path:"lib/core.ml"
        ~status:D.File.Modified
        (D.File.Text [ first_hunk (); second_hunk () ]);
      file ~old_path:"assets/logo.bin" ~new_path:"assets/logo.bin"
        ~status:D.File.Modified D.File.Binary;
    ]

let sample_feature () =
  F.v ~title:"Review feature" ~base:(revision "main")
    ~tip:(revision "feature/review")
    ~diff:(sample_diff ()) ()

let refreshed_feature () =
  let changed_hunk =
    hunk ~old_start:1 ~old_count:2 ~new_start:1 ~new_count:4
      [
        context "let stable = true";
        removed "let value = 1";
        added "let value = 2";
        added "let extra = 3";
        added "let fresh = 4";
      ]
  in
  let diff =
    D.make
      [
        file ~old_path:"lib/core.ml" ~new_path:"lib/core.ml"
          ~status:D.File.Modified (D.File.Text [ changed_hunk ]);
      ]
  in
  F.v ~title:"Review feature" ~base:(revision "main")
    ~tip:(revision "feature/review-2")
    ~diff ()

let retitled_feature () =
  F.v ~title:"Retitled review" ~base:(revision "main")
    ~tip:(revision "feature/review")
    ~diff:(sample_diff ()) ()

let same_scope_changed_content_feature () =
  let changed_hunk =
    hunk ~old_start:1 ~old_count:2 ~new_start:1 ~new_count:3
      [
        context "let stable = true";
        removed "let value = 10";
        added "let value = 2";
        added "let extra = 3";
      ]
  in
  let diff =
    D.make
      [
        file ~old_path:"lib/core.ml" ~new_path:"lib/core.ml"
          ~status:D.File.Modified
          (D.File.Text [ changed_hunk; second_hunk () ]);
        file ~old_path:"assets/logo.bin" ~new_path:"assets/logo.bin"
          ~status:D.File.Modified D.File.Binary;
      ]
  in
  F.v ~title:"Review feature" ~base:(revision "main")
    ~tip:(revision "feature/review-2")
    ~diff ()

let sample_cr_items () =
  [
    cr_item ~line:3 ~body:"verify the edge case" "(* CR alice: verify *)";
    cr_item ~line:11 ~body:"rename this" "(* CR bob: rename *)";
    invalid_cr_item "(* CR two words: bad *)";
  ]

let sample_review () =
  R.v ~feature:(sample_feature ()) ~cr_items:(sample_cr_items ())

let assert_scope_equal ~msg expected actual =
  is_true ~msg (R.Scope.equal expected actual)

let assert_cursor_scope ~msg expected cursor =
  match R.Cursor.selected_scope cursor with
  | Some actual -> assert_scope_equal ~msg expected actual
  | None -> failf "%s: expected scope cursor" msg

let assert_cursor_cr ~msg expected cursor =
  equal ~msg (option int) (Some expected) (R.Cursor.selected_cr cursor)

let expect_mark_state ~msg expected_state mark =
  is_true ~msg (R.Mark.equal_state expected_state (R.Mark.state mark))

let expect_invalid_scope ~msg = function
  | R.Error.Invalid_scope _ -> ()
  | R.Error.Invalid_cursor _ -> failf "%s: expected Invalid_scope" msg

let expect_invalid_cursor ~msg = function
  | R.Error.Invalid_cursor _ -> ()
  | R.Error.Invalid_scope _ -> failf "%s: expected Invalid_cursor" msg

let construction_tests =
  [
    test "constructs reviews and exposes accessors" (fun () ->
        let review = sample_review () in
        let feature = R.feature review in
        is_true ~msg:"feature" (F.equal (sample_feature ()) feature);
        equal ~msg:"cr_count" int 3 (R.cr_count review);
        equal ~msg:"cr_items length" int 3 (List.length (R.cr_items review));
        let first = expect_some ~msg:"first CR" (R.cr_item review 0) in
        is_true ~msg:"first CR equal"
          (C.Item.equal first (List.hd (sample_cr_items ())));
        expect_none ~msg:"missing CR" (R.cr_item review 99);
        let digest = C.Item.digest first in
        equal ~msg:"find by digest" int 1
          (List.length (R.find_cr_items review ~digest));
        equal ~msg:"initial marks" int 0 (List.length (R.marks review));
        expect_none ~msg:"feature mark" (R.mark review R.Scope.feature);
        expect_none ~msg:"effective feature mark"
          (R.effective_mark review R.Scope.feature);
        is_true ~msg:"pending approval"
          (R.Approval.equal R.Approval.Pending (R.approval review));
        assert_cursor_scope ~msg:"initial cursor" R.Scope.feature
          (R.cursor review);
        let summary = R.summary review in
        equal ~msg:"summary total" int 6 (R.Summary.total summary);
        equal ~msg:"summary reviewed" int 0 (R.Summary.reviewed summary);
        equal ~msg:"summary remaining" int 6 (R.Summary.remaining summary);
        equal_float ~msg:"summary progress" 0.0 (R.Summary.progress summary);
        equal_float ~msg:"review progress" 0.0 (R.progress review);
        equal ~msg:"summary CR items" int 3 (R.Summary.cr_items summary);
        equal ~msg:"summary valid CR items" int 2
          (R.Summary.valid_cr_items summary);
        equal ~msg:"summary invalid CR items" int 1
          (R.Summary.invalid_cr_items summary);
        is_false ~msg:"not complete" (R.is_complete review));
  ]

let mark_tests =
  [
    test "marks scopes reviewed and unreviewed" (fun () ->
        let review = sample_review () in
        let core = R.Scope.file "lib/core.ml" in
        let old_line = R.Scope.old_line ~path:"lib/core.ml" ~line:2 in
        let reviewed =
          expect_ok ~msg:"mark feature reviewed" R.Error.pp
            (R.mark_reviewed review R.Scope.feature)
        in
        is_true ~msg:"line inherits reviewed" (R.is_reviewed reviewed old_line);
        let feature_mark =
          expect_some ~msg:"feature mark" (R.mark reviewed R.Scope.feature)
        in
        expect_mark_state ~msg:"feature mark state" R.Mark.Reviewed feature_mark;
        let narrowed =
          expect_ok ~msg:"mark line unreviewed" R.Error.pp
            (R.mark_unreviewed reviewed old_line)
        in
        is_false ~msg:"line no longer reviewed"
          (R.is_reviewed narrowed old_line);
        is_true ~msg:"file remains reviewed" (R.is_reviewed narrowed core);
        let line_mark =
          expect_some ~msg:"line mark" (R.effective_mark narrowed old_line)
        in
        expect_mark_state ~msg:"line mark state" R.Mark.Unreviewed line_mark;
        let cleared_line = R.clear_mark narrowed old_line in
        is_true ~msg:"clear restores inherited review"
          (R.is_reviewed cleared_line old_line);
        let cleared_feature = R.clear_mark cleared_line R.Scope.feature in
        is_false ~msg:"clear feature removes review"
          (R.is_reviewed cleared_feature old_line);
        let explicit_mark = R.Mark.reviewed core in
        let marked =
          expect_ok ~msg:"set explicit mark" R.Error.pp
            (R.set_mark review explicit_mark)
        in
        is_true ~msg:"explicit mark stored"
          (R.Mark.equal explicit_mark
             (expect_some ~msg:"core mark" (R.mark marked core))));
    test "rejects marks for scopes outside the feature" (fun () ->
        let review = sample_review () in
        let missing = R.Scope.file "lib/missing.ml" in
        let error =
          expect_error ~msg:"invalid mark" (R.mark_reviewed review missing)
        in
        expect_invalid_scope ~msg:"invalid mark" error);
  ]

let approval_tests =
  [
    test "moves through pending, approved, and seconded states" (fun () ->
        let review = sample_review () in
        is_false ~msg:"pending is not approved"
          (R.Approval.is_approved R.Approval.Pending);
        let approved = R.set_approval review R.Approval.Approved in
        is_true ~msg:"approved approval"
          (R.Approval.equal R.Approval.Approved (R.approval approved));
        is_true ~msg:"approved predicate"
          (R.Approval.is_approved (R.approval approved));
        is_false ~msg:"approved is not seconded"
          (R.Approval.is_seconded (R.approval approved));
        let seconded = R.set_approval approved R.Approval.Seconded in
        is_true ~msg:"seconded predicate"
          (R.Approval.is_seconded (R.approval seconded));
        is_true ~msg:"summary carries approval"
          (R.Approval.equal R.Approval.Seconded
             (R.Summary.approval (R.summary seconded)));
        let pending = R.set_approval seconded R.Approval.Pending in
        is_true ~msg:"back to pending"
          (R.Approval.equal R.Approval.Pending (R.approval pending));
        equal ~msg:"approval compare equal" int 0
          (R.Approval.compare R.Approval.Seconded R.Approval.Seconded);
        is_true ~msg:"approval pp smoke"
          (String.length (pp_to_string R.Approval.pp R.Approval.Approved) > 0));
  ]

let refresh_tests =
  [
    test "preserves review state when the feature is unchanged" (fun () ->
        let review = sample_review () in
        let core = R.Scope.file "lib/core.ml" in
        let reviewed =
          expect_ok ~msg:"review core" R.Error.pp (R.mark_reviewed review core)
        in
        let approved = R.set_approval reviewed R.Approval.Approved in
        let cr_items = [ cr_item ~line:7 "(* CR carol: new note *)" ] in
        let refreshed =
          R.refresh approved ~feature:(R.feature approved) ~cr_items
        in
        is_true ~msg:"feature unchanged"
          (F.equal (R.feature approved) (R.feature refreshed));
        equal ~msg:"CR list refreshed" int 1 (R.cr_count refreshed);
        is_true ~msg:"mark preserved" (R.is_reviewed refreshed core);
        is_true ~msg:"approval preserved"
          (R.Approval.equal R.Approval.Approved (R.approval refreshed)));
    test "preserves review state when only feature metadata changed" (fun () ->
        let review = sample_review () in
        let core = R.Scope.file "lib/core.ml" in
        let reviewed =
          expect_ok ~msg:"review core" R.Error.pp (R.mark_reviewed review core)
        in
        let approved = R.set_approval reviewed R.Approval.Approved in
        let refreshed =
          R.refresh approved ~feature:(retitled_feature ())
            ~cr_items:(R.cr_items approved)
        in
        is_true ~msg:"mark preserved" (R.is_reviewed refreshed core);
        is_true ~msg:"approval preserved"
          (R.Approval.equal R.Approval.Approved (R.approval refreshed)));
    test "refreshes changed features conservatively" (fun () ->
        let review = sample_review () in
        let core = R.Scope.file "lib/core.ml" in
        let old_line = R.Scope.old_line ~path:"lib/core.ml" ~line:2 in
        let old_new_line = R.Scope.new_line ~path:"lib/core.ml" ~line:2 in
        let fresh_line = R.Scope.new_line ~path:"lib/core.ml" ~line:4 in
        let reviewed =
          expect_ok ~msg:"review core" R.Error.pp (R.mark_reviewed review core)
        in
        let seconded = R.set_approval reviewed R.Approval.Seconded in
        let moved =
          expect_ok ~msg:"cursor to CR" R.Error.pp
            (R.set_cursor seconded (R.Cursor.cr 2))
        in
        let refreshed =
          R.refresh moved ~feature:(refreshed_feature ()) ~cr_items:[]
        in
        is_true ~msg:"old removed line still reviewed"
          (R.is_reviewed refreshed old_line);
        is_true ~msg:"old added line still reviewed"
          (R.is_reviewed refreshed old_new_line);
        is_false ~msg:"new line is not covered by old file mark"
          (R.is_reviewed refreshed fresh_line);
        expect_none ~msg:"broad file mark dropped" (R.mark refreshed core);
        is_true ~msg:"approval reset"
          (R.Approval.equal R.Approval.Pending (R.approval refreshed));
        assert_cursor_scope ~msg:"stale CR cursor reset" R.Scope.feature
          (R.cursor refreshed));
    test "does not preserve a reviewed line when same-position content changed"
      (fun () ->
        let review = sample_review () in
        let core = R.Scope.file "lib/core.ml" in
        let changed_old_line = R.Scope.old_line ~path:"lib/core.ml" ~line:2 in
        let unchanged_new_line = R.Scope.new_line ~path:"lib/core.ml" ~line:2 in
        let reviewed =
          expect_ok ~msg:"review core" R.Error.pp (R.mark_reviewed review core)
        in
        let refreshed =
          R.refresh reviewed
            ~feature:(same_scope_changed_content_feature ())
            ~cr_items:(R.cr_items reviewed)
        in
        is_false ~msg:"changed old line not restored"
          (R.is_reviewed refreshed changed_old_line);
        is_true ~msg:"unchanged new line restored"
          (R.is_reviewed refreshed unchanged_new_line));
  ]

let cursor_tests =
  [
    test "constructs cursors and validates setters" (fun () ->
        let review = sample_review () in
        let core = R.Scope.file "lib/core.ml" in
        let hunk_scope = R.Scope.of_hunk ~path:"lib/core.ml" (first_hunk ()) in
        let scope_cursor = R.Cursor.scope hunk_scope in
        assert_scope_equal ~msg:"selected scope" hunk_scope
          (expect_some ~msg:"selected scope"
             (R.Cursor.selected_scope scope_cursor));
        expect_none ~msg:"scope cursor has no CR"
          (R.Cursor.selected_cr scope_cursor);
        let cr_cursor = R.Cursor.cr 1 in
        equal ~msg:"selected CR" (option int) (Some 1)
          (R.Cursor.selected_cr cr_cursor);
        expect_none ~msg:"CR cursor has no scope"
          (R.Cursor.selected_scope cr_cursor);
        expect_invalid_arg ~msg:"negative CR cursor" (fun () ->
            ignore (R.Cursor.cr (-1) : R.Cursor.t));
        let moved =
          expect_ok ~msg:"set cursor" R.Error.pp
            (R.set_cursor review scope_cursor)
        in
        assert_cursor_scope ~msg:"set cursor result" hunk_scope (R.cursor moved);
        let missing_cursor = R.Cursor.scope (R.Scope.file "missing.ml") in
        let error =
          expect_error ~msg:"invalid cursor"
            (R.set_cursor review missing_cursor)
        in
        expect_invalid_cursor ~msg:"invalid cursor" error;
        let cr_error =
          expect_error ~msg:"invalid CR cursor"
            (R.set_cursor review (R.Cursor.cr 42))
        in
        expect_invalid_cursor ~msg:"invalid CR cursor" cr_error;
        let next = R.next review in
        assert_cursor_scope ~msg:"next selects first file" core (R.cursor next));
    test "moves through the review navigation order" (fun () ->
        let review = sample_review () in
        let first = R.move_cursor review R.Cursor.First in
        assert_cursor_scope ~msg:"first" R.Scope.feature (R.cursor first);
        let previous = R.previous review in
        assert_cursor_scope ~msg:"previous without wrap stays put"
          R.Scope.feature (R.cursor previous);
        let wrapped = R.previous ~wrap:true review in
        assert_cursor_cr ~msg:"previous with wrap selects last CR" 2
          (R.cursor wrapped);
        let last = R.move_cursor review R.Cursor.Last in
        assert_cursor_cr ~msg:"last" 2 (R.cursor last);
        let after_last = R.next last in
        assert_cursor_cr ~msg:"next after last stays put" 2
          (R.cursor after_last);
        let wrapped_first = R.next ~wrap:true last in
        assert_cursor_scope ~msg:"next after last wraps" R.Scope.feature
          (R.cursor wrapped_first));
  ]

let summary_tests =
  [
    test "counts reviewed and remaining units" (fun () ->
        let review = sample_review () in
        let core = R.Scope.file "lib/core.ml" in
        let logo = R.Scope.file "assets/logo.bin" in
        let core_reviewed =
          expect_ok ~msg:"review core" R.Error.pp (R.mark_reviewed review core)
        in
        let summary = R.summary core_reviewed in
        equal ~msg:"core reviewed count" int 5 (R.Summary.reviewed summary);
        equal ~msg:"core remaining count" int 1 (R.Summary.remaining summary);
        equal_float ~msg:"core progress" (5.0 /. 6.0)
          (R.Summary.progress summary);
        let complete =
          expect_ok ~msg:"review logo" R.Error.pp
            (R.mark_reviewed core_reviewed logo)
        in
        let complete_summary = R.summary complete in
        equal ~msg:"complete reviewed count" int 6
          (R.Summary.reviewed complete_summary);
        equal ~msg:"complete remaining count" int 0
          (R.Summary.remaining complete_summary);
        equal_float ~msg:"complete progress" 1.0
          (R.Summary.progress complete_summary);
        is_true ~msg:"summary complete" (R.Summary.is_complete complete_summary);
        is_true ~msg:"review complete" (R.is_complete complete));
  ]

let comparison_and_formatting_tests =
  [
    test "compares values and formats them for humans" (fun () ->
        let review = sample_review () in
        let same = sample_review () in
        let approved = R.set_approval review R.Approval.Approved in
        is_true ~msg:"review equal" (R.equal review same);
        equal ~msg:"review compare equal" int 0 (R.compare review same);
        is_false ~msg:"review not equal" (R.equal review approved);
        is_true ~msg:"review compare distinguishes"
          (R.compare review approved <> 0);
        let scope = R.Scope.old_line ~path:"lib/core.ml" ~line:2 in
        is_true ~msg:"feature contains line"
          (R.Scope.contains R.Scope.feature scope);
        is_true ~msg:"side equal" (R.Scope.equal_side R.Scope.Old R.Scope.Old);
        equal ~msg:"side compare equal" int 0
          (R.Scope.compare_side R.Scope.New R.Scope.New);
        let mark = R.Mark.unreviewed scope in
        is_true ~msg:"mark unreviewed" (R.Mark.is_unreviewed mark);
        equal ~msg:"mark compare equal" int 0 (R.Mark.compare mark mark);
        equal ~msg:"cursor compare equal" int 0
          (R.Cursor.compare R.Cursor.feature R.Cursor.feature);
        equal ~msg:"summary compare equal" int 0
          (R.Summary.compare (R.summary review) (R.summary same));
        is_true ~msg:"review pp smoke"
          (String.length (pp_to_string R.pp review) > 0);
        is_true ~msg:"scope pp smoke"
          (String.length (pp_to_string R.Scope.pp scope) > 0);
        is_true ~msg:"mark pp smoke"
          (String.length (pp_to_string R.Mark.pp mark) > 0);
        is_true ~msg:"cursor pp smoke"
          (String.length (pp_to_string R.Cursor.pp R.Cursor.feature) > 0);
        is_true ~msg:"summary pp smoke"
          (String.length (pp_to_string R.Summary.pp (R.summary review)) > 0);
        is_true ~msg:"error pp smoke"
          (String.length
             (pp_to_string R.Error.pp
                (R.Error.Invalid_scope (R.Scope.file "missing.ml")))
          > 0));
  ]

let () =
  run "sift.review"
    [
      group "construction" construction_tests;
      group "marks" mark_tests;
      group "approval" approval_tests;
      group "refresh" refresh_tests;
      group "cursor" cursor_tests;
      group "summary" summary_tests;
      group "comparison and formatting" comparison_and_formatting_tests;
    ]
