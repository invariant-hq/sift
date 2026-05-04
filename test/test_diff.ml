open Windtrap
module D = Sift_diff

let pp_to_string pp x = Format.asprintf "%a" pp x

let expect_ok ~msg = function
  | Ok x -> x
  | Error e -> failf "%s: expected Ok _, got %a" msg D.Error.pp e

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

let expect_one ~msg = function
  | [ x ] -> x
  | xs -> failf "%s: expected one item, got %d" msg (List.length xs)

let line kind text = D.Line.make kind ~text
let context text = line D.Line.Context text
let added text = line D.Line.Added text
let removed text = line D.Line.Removed text

let hunk ?(old_start = 1) ?(old_count = 1) ?(new_start = 1) ?(new_count = 1)
    lines =
  expect_ok ~msg:"hunk"
    (D.Hunk.make ~old_start ~old_count ~new_start ~new_count lines)

let file ?old_path ?new_path ~status content =
  expect_ok ~msg:"file" (D.File.make ?old_path ?new_path ~status content)

let expect_path ~msg expected actual =
  match (expected, actual) with
  | None, None -> ()
  | Some expected, Some actual -> equal ~msg string expected actual
  | None, Some actual -> failf "%s: expected None, got %S" msg actual
  | Some expected, None -> failf "%s: expected Some %S, got None" msg expected

let expect_file ~msg ?old_path ?new_path ~status f =
  expect_path ~msg:(msg ^ " old_path") old_path (D.File.old_path f);
  expect_path ~msg:(msg ^ " new_path") new_path (D.File.new_path f);
  is_true ~msg:(msg ^ " status") (D.File.equal_status status (D.File.status f))

let expect_binary ~msg f =
  match D.File.content f with
  | D.File.Binary -> ()
  | D.File.Text _ -> failf "%s: expected binary content" msg

let expect_hunk_error ~msg = function
  | D.Error.Invalid_hunk _ -> ()
  | D.Error.Invalid_file _ | D.Error.Invalid_unified_diff _
  | D.Error.Invalid_context _ ->
      failf "%s: expected Invalid_hunk, got different error kind" msg

let expect_file_error ~msg = function
  | D.Error.Invalid_file _ -> ()
  | D.Error.Invalid_hunk _ | D.Error.Invalid_unified_diff _
  | D.Error.Invalid_context _ ->
      failf "%s: expected Invalid_file, got different error kind" msg

let expect_parse_error_line ~msg line e =
  equal ~msg:(msg ^ " line") (option int) (Some line) (D.Error.line e);
  match D.Error.kind e with
  | D.Error.Invalid_unified_diff _ | D.Error.Invalid_hunk _
  | D.Error.Invalid_file _ ->
      ()
  | D.Error.Invalid_context _ ->
      failf "%s: expected unified diff, hunk, or file parse error" msg

let line_tests =
  [
    test "exposes line kind prefixes, accessors, and comparisons" (fun () ->
        let same = context "same" in
        let add = added "new" in
        let del = removed "old" in
        equal ~msg:"context prefix" char ' ' (D.Line.prefix D.Line.Context);
        equal ~msg:"added prefix" char '+' (D.Line.prefix D.Line.Added);
        equal ~msg:"removed prefix" char '-' (D.Line.prefix D.Line.Removed);
        is_true ~msg:"context kind"
          (D.Line.equal_kind D.Line.Context (D.Line.kind same));
        equal ~msg:"added text" string "new" (D.Line.text add);
        is_false ~msg:"context is not change" (D.Line.is_change same);
        is_true ~msg:"added is change" (D.Line.is_change add);
        is_true ~msg:"removed is change" (D.Line.is_change del);
        is_true ~msg:"equal lines" (D.Line.equal (added "new") (added "new"));
        is_false ~msg:"different line kinds"
          (D.Line.equal (added "x") (removed "x"));
        equal ~msg:"compare equal" int 0
          (D.Line.compare (context "x") (context "x"));
        equal ~msg:"compare_kind equal" int 0
          (D.Line.compare_kind D.Line.Added D.Line.Added);
        is_true ~msg:"compare distinguishes lines"
          (D.Line.compare (context "a") (context "b") < 0);
        equal ~msg:"pp context" string " same" (pp_to_string D.Line.pp same);
        equal ~msg:"pp added" string "+new" (pp_to_string D.Line.pp add);
        equal ~msg:"pp removed" string "-old" (pp_to_string D.Line.pp del));
  ]

let hunk_tests =
  [
    test "validates hunk ranges and line counts" (fun () ->
        let h =
          hunk ~old_start:10 ~old_count:3 ~new_start:20 ~new_count:3
            [ context "same"; removed "old"; added "new"; context "tail" ]
        in
        equal ~msg:"old_start" int 10 (D.Hunk.old_start h);
        equal ~msg:"old_count" int 3 (D.Hunk.old_count h);
        equal ~msg:"new_start" int 20 (D.Hunk.new_start h);
        equal ~msg:"new_count" int 3 (D.Hunk.new_count h);
        equal ~msg:"line count" int 4 (List.length (D.Hunk.lines h));
        let same =
          hunk ~old_start:10 ~old_count:3 ~new_start:20 ~new_count:3
            [ context "same"; removed "old"; added "new"; context "tail" ]
        in
        is_true ~msg:"hunk equal" (D.Hunk.equal h same);
        equal ~msg:"hunk compare equal" int 0 (D.Hunk.compare h same);
        ignore (pp_to_string D.Hunk.pp h : string));
    test "annotates rows with old and new line numbers" (fun () ->
        let h =
          hunk ~old_start:10 ~old_count:3 ~new_start:20 ~new_count:3
            [ context "same"; removed "old"; added "new"; context "tail" ]
        in
        match D.Hunk.rows h with
        | [ r1; r2; r3; r4 ] ->
            equal ~msg:"row1 old" (option int) (Some 10) r1.D.Hunk.old_line;
            equal ~msg:"row1 new" (option int) (Some 20) r1.D.Hunk.new_line;
            equal ~msg:"row2 old" (option int) (Some 11) r2.D.Hunk.old_line;
            equal ~msg:"row2 new" (option int) None r2.D.Hunk.new_line;
            equal ~msg:"row3 old" (option int) None r3.D.Hunk.old_line;
            equal ~msg:"row3 new" (option int) (Some 21) r3.D.Hunk.new_line;
            equal ~msg:"row4 old" (option int) (Some 12) r4.D.Hunk.old_line;
            equal ~msg:"row4 new" (option int) (Some 22) r4.D.Hunk.new_line;
            is_true ~msg:"row3 line" (D.Line.equal (added "new") r3.D.Hunk.line)
        | rows -> failf "expected four rows, got %d" (List.length rows));
    test "rejects invalid hunks" (fun () ->
        let cases =
          [
            ( "empty lines",
              D.Hunk.make ~old_start:1 ~old_count:0 ~new_start:1 ~new_count:0 []
            );
            ( "negative old count",
              D.Hunk.make ~old_start:1 ~old_count:(-1) ~new_start:1 ~new_count:0
                [ removed "x" ] );
            ( "non-empty range starts at zero",
              D.Hunk.make ~old_start:0 ~old_count:1 ~new_start:1 ~new_count:1
                [ context "x" ] );
            ( "old count mismatch",
              D.Hunk.make ~old_start:1 ~old_count:2 ~new_start:1 ~new_count:1
                [ removed "x"; added "y" ] );
            ( "new count mismatch",
              D.Hunk.make ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:2
                [ removed "x"; added "y" ] );
          ]
        in
        List.iter
          (fun (msg, result) ->
            let e = expect_error ~msg result in
            expect_hunk_error ~msg (D.Error.kind e))
          cases;
        ignore
          (hunk ~old_start:0 ~old_count:0 ~new_start:1 ~new_count:1
             [ added "x" ]
            : D.Hunk.t);
        expect_invalid_arg ~msg:"Hunk.v rejects invalid hunk" (fun () ->
            ignore
              (D.Hunk.v ~old_start:1 ~old_count:2 ~new_start:1 ~new_count:1
                 [ removed "x"; added "y" ]
                : D.Hunk.t)));
  ]

let file_tests =
  [
    test "validates file status, paths, text content, and binary content"
      (fun () ->
        let add_hunk =
          hunk ~old_start:0 ~old_count:0 ~new_start:1 ~new_count:1
            [ added "new" ]
        in
        let del_hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:0 ~new_count:0
            [ removed "old" ]
        in
        let mod_hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "old"; added "new" ]
        in
        let added_file =
          file ~new_path:"new.ml" ~status:D.File.Added
            (D.File.Text [ add_hunk ])
        in
        let deleted_file =
          file ~old_path:"old.ml" ~status:D.File.Deleted
            (D.File.Text [ del_hunk ])
        in
        let modified_file =
          file ~old_path:"same.ml" ~new_path:"same.ml" ~status:D.File.Modified
            (D.File.Text [ mod_hunk ])
        in
        let renamed_file =
          file ~old_path:"old.ml" ~new_path:"new.ml" ~status:D.File.Renamed
            (D.File.Text [])
        in
        let binary_file =
          file ~old_path:"image.bin" ~new_path:"image.bin"
            ~status:D.File.Modified D.File.Binary
        in
        expect_file ~msg:"added" ~new_path:"new.ml" ~status:D.File.Added
          added_file;
        expect_file ~msg:"deleted" ~old_path:"old.ml" ~status:D.File.Deleted
          deleted_file;
        expect_file ~msg:"modified" ~old_path:"same.ml" ~new_path:"same.ml"
          ~status:D.File.Modified modified_file;
        expect_file ~msg:"renamed" ~old_path:"old.ml" ~new_path:"new.ml"
          ~status:D.File.Renamed renamed_file;
        equal ~msg:"added display path" string "new.ml" (D.File.path added_file);
        equal ~msg:"deleted display path" string "old.ml"
          (D.File.path deleted_file);
        is_true ~msg:"added is text" (D.File.is_text added_file);
        is_false ~msg:"added is not binary" (D.File.is_binary added_file);
        is_false ~msg:"modified is not empty" (D.File.is_empty modified_file);
        is_true ~msg:"renamed with no hunks is empty"
          (D.File.is_empty renamed_file);
        is_true ~msg:"binary is binary" (D.File.is_binary binary_file);
        is_false ~msg:"binary is not text" (D.File.is_text binary_file);
        equal ~msg:"binary hunks" int 0 (List.length (D.File.hunks binary_file));
        expect_binary ~msg:"binary content" binary_file;
        is_true ~msg:"file equal"
          (D.File.equal modified_file
             (file ~old_path:"same.ml" ~new_path:"same.ml"
                ~status:D.File.Modified (D.File.Text [ mod_hunk ])));
        equal ~msg:"file compare equal" int 0
          (D.File.compare modified_file
             (file ~old_path:"same.ml" ~new_path:"same.ml"
                ~status:D.File.Modified (D.File.Text [ mod_hunk ])));
        equal ~msg:"status compare equal" int 0
          (D.File.compare_status D.File.Modified D.File.Modified);
        ignore (pp_to_string D.File.pp modified_file : string));
    test "rejects invalid files and overlapping hunks" (fun () ->
        let mod_hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "old"; added "new" ]
        in
        let overlapping =
          hunk ~old_start:1 ~old_count:1 ~new_start:2 ~new_count:1
            [ removed "other"; added "next" ]
        in
        let cases =
          [
            ( "missing paths",
              D.File.make ~status:D.File.Modified (D.File.Text [ mod_hunk ]) );
            ( "added with old path",
              D.File.make ~old_path:"old.ml" ~new_path:"new.ml"
                ~status:D.File.Added (D.File.Text [ mod_hunk ]) );
            ( "deleted with new path",
              D.File.make ~old_path:"old.ml" ~new_path:"new.ml"
                ~status:D.File.Deleted (D.File.Text [ mod_hunk ]) );
            ( "modified missing old path",
              D.File.make ~new_path:"new.ml" ~status:D.File.Modified
                (D.File.Text [ mod_hunk ]) );
            ( "renamed missing new path",
              D.File.make ~old_path:"old.ml" ~status:D.File.Renamed
                (D.File.Text [ mod_hunk ]) );
            ( "overlapping hunks",
              D.File.make ~old_path:"same.ml" ~new_path:"same.ml"
                ~status:D.File.Modified
                (D.File.Text [ mod_hunk; overlapping ]) );
          ]
        in
        List.iter
          (fun (msg, result) ->
            let e = expect_error ~msg result in
            expect_file_error ~msg (D.Error.kind e))
          cases;
        expect_invalid_arg ~msg:"File.v rejects invalid file" (fun () ->
            ignore
              (D.File.v ~status:D.File.Modified (D.File.Text []) : D.File.t)));
  ]

let diff_tests =
  [
    test "exposes root helpers and root t alias" (fun () ->
        is_true ~msg:"empty is empty" (D.is_empty D.empty);
        equal ~msg:"empty file count" int 0 (D.file_count D.empty);
        equal ~msg:"empty files" int 0 (List.length (D.files D.empty));
        let h =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "old"; added "new" ]
        in
        let f =
          file ~old_path:"a.ml" ~new_path:"a.ml" ~status:D.File.Modified
            (D.File.Text [ h ])
        in
        let root : D.t = D.make [ f ] in
        let nested : D.t = root in
        equal ~msg:"root file count" int 1 (D.file_count root);
        equal ~msg:"nested file count" int 1 (D.file_count nested);
        is_true ~msg:"root equal nested" (D.equal root nested);
        equal ~msg:"root compare equal" int 0 (D.compare root nested);
        is_true ~msg:"nested equal" (D.equal nested (D.make [ f ]));
        ignore (pp_to_string D.pp root : string);
        ignore (pp_to_string D.pp nested : string));
  ]

let compute_tests =
  [
    test "returns no hunks and no file for equal text" (fun () ->
        let hunks = D.Compute.hunks ~old_text:"same\n" ~new_text:"same\n" () in
        equal ~msg:"equal hunks" int 0 (List.length hunks);
        expect_none ~msg:"equal file"
          (D.Compute.file ~old_path:"same.ml" ~new_path:"same.ml"
             ~old_text:"same\n" ~new_text:"same\n" ());
        let invalid_context () =
          ignore (D.Compute.hunks ~context:(-1) ~old_text:"" ~new_text:"" ())
        in
        expect_invalid_arg ~msg:"negative context" invalid_context);
    test "derives added, deleted, modified, and renamed file statuses"
      (fun () ->
        let added_file =
          expect_some ~msg:"compute added"
            (D.Compute.file ~new_path:"new.ml" ~old_text:""
               ~new_text:"created\n" ())
        in
        let deleted_file =
          expect_some ~msg:"compute deleted"
            (D.Compute.file ~old_path:"old.ml" ~old_text:"removed\n"
               ~new_text:"" ())
        in
        let modified_file =
          expect_some ~msg:"compute modified"
            (D.Compute.file ~old_path:"same.ml" ~new_path:"same.ml"
               ~old_text:"old\n" ~new_text:"new\n" ())
        in
        let renamed_file =
          expect_some ~msg:"compute renamed"
            (D.Compute.file ~old_path:"old.ml" ~new_path:"new.ml"
               ~old_text:"same\n" ~new_text:"same\n" ())
        in
        expect_file ~msg:"compute added" ~new_path:"new.ml" ~status:D.File.Added
          added_file;
        expect_file ~msg:"compute deleted" ~old_path:"old.ml"
          ~status:D.File.Deleted deleted_file;
        expect_file ~msg:"compute modified" ~old_path:"same.ml"
          ~new_path:"same.ml" ~status:D.File.Modified modified_file;
        expect_file ~msg:"compute renamed" ~old_path:"old.ml" ~new_path:"new.ml"
          ~status:D.File.Renamed renamed_file;
        is_false ~msg:"added has hunks"
          (List.length (D.File.hunks added_file) = 0);
        is_true ~msg:"renamed without text changes has no hunks"
          (D.File.is_empty renamed_file));
  ]

let parser_tests =
  [
    test "parses a plain unified single-file diff" (fun () ->
        let input =
          String.concat "\n"
            [
              "--- src/app.ml";
              "+++ src/app.ml";
              "@@ -1,2 +1,2 @@";
              " let unchanged = 0";
              "-let value = 1";
              "+let value = 2";
              "";
            ]
        in
        let f = expect_ok ~msg:"plain file" (D.Parser.file_unified input) in
        expect_file ~msg:"plain file" ~old_path:"src/app.ml"
          ~new_path:"src/app.ml" ~status:D.File.Modified f;
        let h = expect_one ~msg:"plain hunks" (D.File.hunks f) in
        equal ~msg:"plain old count" int 2 (D.Hunk.old_count h);
        equal ~msg:"plain new count" int 2 (D.Hunk.new_count h);
        match D.Hunk.lines h with
        | [ c; r; a ] ->
            is_true ~msg:"context line"
              (D.Line.equal (context "let unchanged = 0") c);
            is_true ~msg:"removed line"
              (D.Line.equal (removed "let value = 1") r);
            is_true ~msg:"added line" (D.Line.equal (added "let value = 2") a)
        | lines -> failf "expected three hunk lines, got %d" (List.length lines));
    test "parses a multi-file Git diff" (fun () ->
        let input =
          String.concat "\n"
            [
              "diff --git a/src/a.ml b/src/a.ml";
              "index 1111111..2222222 100644";
              "--- a/src/a.ml";
              "+++ b/src/a.ml";
              "@@ -1 +1 @@";
              "-old";
              "+new";
              "diff --git a/src/b.ml b/src/b.ml";
              "new file mode 100644";
              "index 0000000..3333333";
              "--- /dev/null";
              "+++ b/src/b.ml";
              "@@ -0,0 +1 @@";
              "+created";
              "";
            ]
        in
        let d = expect_ok ~msg:"git diff" (D.Parser.unified input) in
        equal ~msg:"git file count" int 2 (D.file_count d);
        match D.files d with
        | [ modified_file; added_file ] ->
            expect_file ~msg:"git modified" ~old_path:"src/a.ml"
              ~new_path:"src/a.ml" ~status:D.File.Modified modified_file;
            expect_file ~msg:"git added" ~new_path:"src/b.ml"
              ~status:D.File.Added added_file;
            equal ~msg:"git modified hunk count" int 1
              (List.length (D.File.hunks modified_file));
            equal ~msg:"git added hunk count" int 1
              (List.length (D.File.hunks added_file))
        | files -> failf "expected two files, got %d" (List.length files));
    test "normalizes a/, b/, and /dev/null paths" (fun () ->
        let added_input =
          String.concat "\n"
            [
              "diff --git a/src/new.ml b/src/new.ml";
              "new file mode 100644";
              "--- /dev/null";
              "+++ b/src/new.ml";
              "@@ -0,0 +1 @@";
              "+new";
              "";
            ]
        in
        let deleted_input =
          String.concat "\n"
            [
              "diff --git a/src/old.ml b/src/old.ml";
              "deleted file mode 100644";
              "--- a/src/old.ml";
              "+++ /dev/null";
              "@@ -1 +0,0 @@";
              "-old";
              "";
            ]
        in
        let added_file =
          expect_ok ~msg:"normalize added" (D.Parser.file_unified added_input)
        in
        let deleted_file =
          expect_ok ~msg:"normalize deleted"
            (D.Parser.file_unified deleted_input)
        in
        expect_file ~msg:"normalize added" ~new_path:"src/new.ml"
          ~status:D.File.Added added_file;
        expect_file ~msg:"normalize deleted" ~old_path:"src/old.ml"
          ~status:D.File.Deleted deleted_file);
    test "parses rename and copy metadata" (fun () ->
        let input =
          String.concat "\n"
            [
              "diff --git a/lib/old.ml b/lib/new.ml";
              "similarity index 100%";
              "rename from lib/old.ml";
              "rename to lib/new.ml";
              "diff --git a/lib/template.ml b/lib/copy.ml";
              "similarity index 100%";
              "copy from lib/template.ml";
              "copy to lib/copy.ml";
              "";
            ]
        in
        let d = expect_ok ~msg:"rename copy" (D.Parser.unified input) in
        match D.files d with
        | [ renamed_file; copied_file ] ->
            expect_file ~msg:"renamed metadata" ~old_path:"lib/old.ml"
              ~new_path:"lib/new.ml" ~status:D.File.Renamed renamed_file;
            expect_file ~msg:"copied metadata" ~old_path:"lib/template.ml"
              ~new_path:"lib/copy.ml" ~status:D.File.Copied copied_file;
            is_true ~msg:"renamed metadata is empty"
              (D.File.is_empty renamed_file);
            is_true ~msg:"copied metadata is empty"
              (D.File.is_empty copied_file)
        | files -> failf "expected two files, got %d" (List.length files));
    test "parses binary file markers" (fun () ->
        let input =
          String.concat "\n"
            [
              "diff --git a/assets/image.bin b/assets/image.bin";
              "index 1111111..2222222 100644";
              "Binary files a/assets/image.bin and b/assets/image.bin differ";
              "";
            ]
        in
        let f = expect_ok ~msg:"binary marker" (D.Parser.file_unified input) in
        expect_file ~msg:"binary marker" ~old_path:"assets/image.bin"
          ~new_path:"assets/image.bin" ~status:D.File.Modified f;
        expect_binary ~msg:"binary marker content" f);
    test "rejects unexpected lines in Git text diffs" (fun () ->
        let input =
          String.concat "\n"
            [
              "diff --git a/src/bad.ml b/src/bad.ml";
              "--- a/src/bad.ml";
              "+++ b/src/bad.ml";
              "!not a diff line";
              "";
            ]
        in
        let e =
          expect_error ~msg:"unexpected git text line"
            (D.Parser.file_unified input)
        in
        expect_parse_error_line ~msg:"unexpected git text line" 4 e);
    test "ignores no-newline markers inside hunks" (fun () ->
        let input =
          String.concat "\n"
            [
              "--- a/src/eof.ml";
              "+++ b/src/eof.ml";
              "@@ -1 +1 @@";
              "-old";
              "\\ No newline at end of file";
              "+new";
              "\\ No newline at end of file";
              "";
            ]
        in
        let f = expect_ok ~msg:"no newline" (D.Parser.file_unified input) in
        let h = expect_one ~msg:"no newline hunks" (D.File.hunks f) in
        match D.Hunk.lines h with
        | [ old_line; new_line ] ->
            is_true ~msg:"old line" (D.Line.equal (removed "old") old_line);
            is_true ~msg:"new line" (D.Line.equal (added "new") new_line)
        | lines -> failf "expected two hunk lines, got %d" (List.length lines));
    test "reports parse errors with line numbers where applicable" (fun () ->
        let malformed_header =
          String.concat "\n" [ "--- a/x.ml"; "+++ b/x.ml"; "@@ broken"; "" ]
        in
        let e =
          expect_error ~msg:"malformed hunk header"
            (D.Parser.file_unified malformed_header)
        in
        expect_parse_error_line ~msg:"malformed hunk header" 3 e;
        let malformed_line =
          String.concat "\n"
            [
              "--- a/x.ml"; "+++ b/x.ml"; "@@ -1 +1 @@"; "!not a diff line"; "";
            ]
        in
        let e =
          expect_error ~msg:"malformed hunk line"
            (D.Parser.file_unified malformed_line)
        in
        expect_parse_error_line ~msg:"malformed hunk line" 4 e);
  ]

let () =
  run "sift.diff"
    [
      group "lines" line_tests;
      group "hunks" hunk_tests;
      group "files" file_tests;
      group "diffs" diff_tests;
      group "compute" compute_tests;
      group "parser" parser_tests;
    ]
