open Windtrap
module S = Sift_feature
module D = Sift_diff

let pp_to_string pp x = Format.asprintf "%a" pp x

let expect_diff_ok ~msg = function
  | Ok x -> x
  | Error e -> failf "%s: expected Ok _, got %a" msg D.Error.pp e

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

let line kind text = D.Line.make kind ~text
let context text = line D.Line.Context text
let added text = line D.Line.Added text
let removed text = line D.Line.Removed text

let hunk ?(old_start = 1) ?(old_count = 1) ?(new_start = 1) ?(new_count = 1)
    lines =
  expect_diff_ok ~msg:"hunk"
    (D.Hunk.make ~old_start ~old_count ~new_start ~new_count lines)

let file ?old_path ?new_path ~status content =
  expect_diff_ok ~msg:"file" (D.File.make ?old_path ?new_path ~status content)

let revision = S.Revision.v

let sample_diff () =
  let changed_hunk =
    hunk ~old_start:1 ~old_count:2 ~new_start:1 ~new_count:3
      [
        context "let stable = true";
        removed "let value = 1";
        added "let value = 2";
        added "let extra = 3";
      ]
  in
  let followup_hunk =
    hunk ~old_start:10 ~old_count:1 ~new_start:11 ~new_count:2
      [ removed "old branch"; added "new branch"; added "new guard" ]
  in
  let created_hunk =
    hunk ~old_start:0 ~old_count:0 ~new_start:1 ~new_count:1 [ added "created" ]
  in
  D.make
    [
      file ~old_path:"lib/core.ml" ~new_path:"lib/core.ml"
        ~status:D.File.Modified
        (D.File.Text [ changed_hunk; followup_hunk ]);
      file ~new_path:"lib/new.ml" ~status:D.File.Added
        (D.File.Text [ created_hunk ]);
      file ~old_path:"assets/logo.bin" ~new_path:"assets/logo.bin"
        ~status:D.File.Modified D.File.Binary;
    ]

let sample_feature ?title () =
  S.v ?title ~base:(revision "main") ~tip:(revision "feature/ui")
    ~diff:(sample_diff ()) ()

let revision_tests =
  [
    test "accepts non-empty opaque revision identifiers" (fun () ->
        let r = S.Revision.v "feature branch@{1}" in
        equal ~msg:"to_string" string "feature branch@{1}"
          (S.Revision.to_string r);
        equal ~msg:"pp" string "feature branch@{1}"
          (pp_to_string S.Revision.pp r);
        is_true ~msg:"equal"
          (S.Revision.equal r (S.Revision.v "feature branch@{1}"));
        is_false ~msg:"not equal" (S.Revision.equal r (S.Revision.v "HEAD"));
        equal ~msg:"compare equal" int 0 (S.Revision.compare r r);
        is_true ~msg:"compare lexicographic"
          (S.Revision.compare (S.Revision.v "a") (S.Revision.v "b") < 0));
    test "rejects empty revision identifiers" (fun () ->
        expect_invalid_arg ~msg:"Revision.v rejects empty input" (fun () ->
            ignore (S.Revision.v "" : S.Revision.t)));
  ]

let feature_tests =
  [
    test "constructs features with optional titles" (fun () ->
        let base = revision "main" in
        let tip = revision "topic" in
        let diff = sample_diff () in
        let without_title = S.v ~base ~tip ~diff () in
        expect_none ~msg:"title absent" (S.title without_title);
        is_true ~msg:"base" (S.Revision.equal base (S.base without_title));
        is_true ~msg:"tip" (S.Revision.equal tip (S.tip without_title));
        is_true ~msg:"diff" (D.equal diff (S.diff without_title));
        let with_title = S.v ~title:"Refresh UI" ~base ~tip ~diff () in
        equal ~msg:"title present" (option string) (Some "Refresh UI")
          (S.title with_title);
        let via_v = S.v ~title:"Refresh UI" ~base ~tip ~diff () in
        is_true ~msg:"v equals make" (S.equal with_title via_v));
    test "rejects empty titles" (fun () ->
        let base = revision "main" in
        let tip = revision "topic" in
        let diff = D.empty in
        expect_invalid_arg ~msg:"Feature.v rejects empty title" (fun () ->
            ignore (S.v ~title:"" ~base ~tip ~diff () : S.t)));
    test "exposes files and finds files by display path" (fun () ->
        let feature = sample_feature () in
        equal ~msg:"file count" int 3 (List.length (S.files feature));
        let core =
          expect_some ~msg:"find modified file"
            (S.find_file feature ~path:"lib/core.ml")
        in
        equal ~msg:"modified path" string "lib/core.ml" (D.File.path core);
        let added_file =
          expect_some ~msg:"find added file"
            (S.find_file feature ~path:"lib/new.ml")
        in
        equal ~msg:"added path" string "lib/new.ml" (D.File.path added_file);
        let binary =
          expect_some ~msg:"find binary file"
            (S.find_file feature ~path:"assets/logo.bin")
        in
        is_true ~msg:"binary file" (D.File.is_binary binary);
        expect_none ~msg:"missing file"
          (S.find_file feature ~path:"lib/missing.ml"));
  ]

let summary_tests =
  [
    test "counts files, file kinds, hunks, and changed lines" (fun () ->
        let summary = S.summary (sample_feature ()) in
        equal ~msg:"files" int 3 (S.Summary.files summary);
        equal ~msg:"text files" int 2 (S.Summary.text_files summary);
        equal ~msg:"binary files" int 1 (S.Summary.binary_files summary);
        equal ~msg:"hunks" int 3 (S.Summary.hunks summary);
        equal ~msg:"added lines" int 5 (S.Summary.added_lines summary);
        equal ~msg:"removed lines" int 2 (S.Summary.removed_lines summary);
        is_true ~msg:"summary equal" (S.Summary.equal summary summary);
        equal ~msg:"summary compare equal" int 0
          (S.Summary.compare summary summary);
        ignore (pp_to_string S.Summary.pp summary : string));
  ]

let comparison_and_formatting_tests =
  [
    test "compares features and formats them for humans" (fun () ->
        let feature = sample_feature ~title:"Refresh UI" () in
        let same = sample_feature ~title:"Refresh UI" () in
        let different = sample_feature ~title:"Other title" () in
        is_true ~msg:"feature equal" (S.equal feature same);
        equal ~msg:"feature compare equal" int 0 (S.compare feature same);
        is_false ~msg:"feature not equal" (S.equal feature different);
        is_true ~msg:"feature compare distinguishes values"
          (S.compare feature different <> 0);
        is_true ~msg:"pp smoke" (String.length (pp_to_string S.pp feature) > 0));
  ]

let () =
  run "sift.feature"
    [
      group "revisions" revision_tests;
      group "features" feature_tests;
      group "summaries" summary_tests;
      group "comparison and formatting" comparison_and_formatting_tests;
    ]
