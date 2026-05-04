open Windtrap
module S = Sift_store
module C = Sift_crs
module D = Sift_diff
module F = Sift_feature
module R = Sift_review

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

let string_has_prefix ~prefix s =
  let prefix_len = String.length prefix in
  String.length s >= prefix_len && String.sub s 0 prefix_len = prefix

let rec equal_value a b =
  match (a, b) with
  | S.Codec.Null, S.Codec.Null -> true
  | S.Codec.Bool a, S.Codec.Bool b -> Bool.equal a b
  | S.Codec.Int a, S.Codec.Int b -> Int.equal a b
  | S.Codec.String a, S.Codec.String b -> String.equal a b
  | S.Codec.List a, S.Codec.List b ->
      List.length a = List.length b && List.for_all2 equal_value a b
  | S.Codec.Fields a, S.Codec.Fields b ->
      List.length a = List.length b
      && List.for_all2
           (fun (ak, av) (bk, bv) -> String.equal ak bk && equal_value av bv)
           a b
  | ( ( S.Codec.Null | S.Codec.Bool _ | S.Codec.Int _ | S.Codec.String _
      | S.Codec.List _ | S.Codec.Fields _ ),
      _ ) ->
      false

let line kind text = D.Line.make kind ~text
let added text = line D.Line.Added text

let hunk ?(old_start = 0) ?(old_count = 0) ?(new_start = 1) ?(new_count = 1)
    lines =
  expect_ok ~msg:"hunk" D.Error.pp
    (D.Hunk.make ~old_start ~old_count ~new_start ~new_count lines)

let file ?old_path ?new_path ~status content =
  expect_ok ~msg:"file" D.Error.pp
    (D.File.make ?old_path ?new_path ~status content)

let revision s = F.Revision.v s

let sample_feature ?title () =
  let diff =
    D.make
      [
        file ~new_path:"lib/new.ml" ~status:D.File.Added
          (D.File.Text [ hunk [ added "let value = 1" ] ]);
      ]
  in
  F.v ?title ~base:(revision "main") ~tip:(revision "feature/store") ~diff ()

let review_feature ?(path = "lib/new.ml") ?(lines = [ added "let value = 1" ])
    () =
  let diff =
    D.make
      [
        file ~new_path:path ~status:D.File.Added
          (D.File.Text [ hunk ~new_count:(List.length lines) lines ]);
      ]
  in
  F.v ~base:(revision "main") ~tip:(revision "WORKTREE") ~diff ()

let make_review ?path ?lines () =
  R.v ~feature:(review_feature ?path ?lines ()) ~cr_items:[]

let base = revision "main"
let tip = revision "feature/store"
let key ?namespace () = S.Key.v ?namespace ~base ~tip ()
let digest s = C.Digest.create s

let scope_tests =
  [
    test "constructs durable scopes and exposes their views" (fun () ->
        let feature = S.Record.feature in
        (match S.Record.scope_view feature with
        | S.Record.Feature -> ()
        | S.Record.File _ | S.Record.Hunk _ | S.Record.Line _ ->
            fail "expected feature scope");
        expect_none ~msg:"feature path" (S.Record.scope_path feature);
        let file_scope = S.Record.file ~path:"lib/core.ml" in
        equal ~msg:"file path" (option string) (Some "lib/core.ml")
          (S.Record.scope_path file_scope);
        (match S.Record.scope_view file_scope with
        | S.Record.File path ->
            equal ~msg:"file view path" string "lib/core.ml" path
        | S.Record.Feature | S.Record.Hunk _ | S.Record.Line _ ->
            fail "expected file scope");
        let hunk_scope =
          S.Record.hunk ~path:"lib/core.ml" ~old_start:1 ~old_count:2
            ~new_start:1 ~new_count:3
        in
        (match S.Record.scope_view hunk_scope with
        | S.Record.Hunk h ->
            let open S.Record in
            equal ~msg:"hunk path" string "lib/core.ml" h.path;
            equal ~msg:"hunk old_start" int 1 h.old_start;
            equal ~msg:"hunk old_count" int 2 h.old_count;
            equal ~msg:"hunk new_start" int 1 h.new_start;
            equal ~msg:"hunk new_count" int 3 h.new_count
        | S.Record.Feature | S.Record.File _ | S.Record.Line _ ->
            fail "expected hunk scope");
        let old_line = S.Record.old_line ~path:"lib/core.ml" ~line:2 in
        let new_line = S.Record.new_line ~path:"lib/core.ml" ~line:3 in
        (match S.Record.scope_view old_line with
        | S.Record.Line (S.Record.Old, path, line) ->
            equal ~msg:"old line path" string "lib/core.ml" path;
            equal ~msg:"old line number" int 2 line
        | S.Record.Feature | S.Record.File _ | S.Record.Hunk _ | S.Record.Line _
          ->
            fail "expected old line scope");
        is_true ~msg:"different line scopes"
          (S.Record.compare_scope old_line new_line <> 0);
        is_true ~msg:"scope equal"
          (S.Record.equal_scope file_scope (S.Record.file ~path:"lib/core.ml"));
        is_true ~msg:"side equal"
          (S.Record.equal_side S.Record.New S.Record.New);
        equal ~msg:"side compare equal" int 0
          (S.Record.compare_side S.Record.Old S.Record.Old);
        expect_invalid_arg ~msg:"empty file path" (fun () ->
            ignore (S.Record.file ~path:"" : S.Record.scope));
        expect_invalid_arg ~msg:"absolute file path" (fun () ->
            ignore (S.Record.file ~path:"/tmp/file.ml" : S.Record.scope));
        expect_invalid_arg ~msg:"invalid line" (fun () ->
            ignore
              (S.Record.old_line ~path:"lib/core.ml" ~line:0 : S.Record.scope));
        is_true ~msg:"scope pp smoke"
          (String.length (pp_to_string S.Record.pp_scope hunk_scope) > 0));
  ]

let key_tests =
  [
    test "constructs keys and compares them" (fun () ->
        let k = key ~namespace:"repo" () in
        equal ~msg:"namespace" (option string) (Some "repo") (S.Key.namespace k);
        is_true ~msg:"base" (F.Revision.equal base (S.Key.base k));
        is_true ~msg:"tip" (F.Revision.equal tip (S.Key.tip k));
        let from_feature =
          S.Key.of_feature ~namespace:"repo" (sample_feature ~title:"Store" ())
        in
        is_true ~msg:"key ignores title" (S.Key.equal k from_feature);
        equal ~msg:"key compare equal" int 0 (S.Key.compare k from_feature);
        is_true ~msg:"key string smoke" (String.length (S.Key.to_string k) > 0);
        is_true ~msg:"key pp smoke" (String.length (pp_to_string S.Key.pp k) > 0);
        expect_invalid_arg ~msg:"empty namespace" (fun () ->
            ignore (key ~namespace:"" () : S.Key.t)));
  ]

let record_tests =
  [
    test "constructs CR records and cursors" (fun () ->
        let line_scope = S.Record.new_line ~path:"lib/core.ml" ~line:3 in
        let mark = S.Record.mark ~scope:line_scope ~state:S.Record.Reviewed in
        is_true ~msg:"mark scope"
          (S.Record.equal_scope line_scope (S.Record.mark_scope mark));
        is_true ~msg:"mark state"
          (S.Record.equal_mark_state S.Record.Reviewed
             (S.Record.mark_state mark));
        let unreviewed =
          S.Record.mark ~scope:line_scope ~state:S.Record.Unreviewed
        in
        is_true ~msg:"mark compare distinguishes state"
          (S.Record.compare_mark mark unreviewed <> 0);
        equal ~msg:"mark identity ignores state" int 0
          (S.Record.compare_mark_identity mark unreviewed);
        is_true ~msg:"mark pp smoke"
          (String.length (pp_to_string S.Record.pp_mark mark) > 0);
        let cr =
          S.Record.cr_record ~scope:line_scope ~digest:(digest "CR alice: fix")
            ~state:S.Record.Open ()
        in
        is_true ~msg:"CR digest"
          (C.Digest.equal (digest "CR alice: fix") (S.Record.cr_digest cr));
        is_true ~msg:"CR scope"
          (S.Record.equal_scope line_scope
             (expect_some ~msg:"CR scope" (S.Record.cr_scope cr)));
        is_true ~msg:"CR state"
          (S.Record.equal_cr_state S.Record.Open (S.Record.cr_state cr));
        let addressed =
          S.Record.cr_record ~scope:line_scope ~digest:(digest "CR alice: fix")
            ~state:S.Record.Addressed ()
        in
        is_true ~msg:"CR compare distinguishes state"
          (S.Record.compare_cr_record cr addressed <> 0);
        equal ~msg:"CR state compare equal" int 0
          (S.Record.compare_cr_state S.Record.Accepted S.Record.Accepted);
        let scope_cursor = S.Record.cursor (S.Record.Scope line_scope) in
        is_true ~msg:"cursor scope"
          (S.Record.equal_scope line_scope
             (expect_some ~msg:"cursor scope"
                (S.Record.cursor_scope scope_cursor)));
        expect_none ~msg:"scope cursor CR" (S.Record.cursor_cr scope_cursor);
        let cr_cursor = S.Record.cursor (S.Record.Cr 2) in
        equal ~msg:"cursor CR" (option int) (Some 2)
          (S.Record.cursor_cr cr_cursor);
        expect_none ~msg:"CR cursor scope" (S.Record.cursor_scope cr_cursor);
        is_true ~msg:"cursor equal"
          (S.Record.equal_cursor cr_cursor (S.Record.cursor (S.Record.Cr 2)));
        equal ~msg:"cursor compare equal" int 0
          (S.Record.compare_cursor cr_cursor cr_cursor);
        equal ~msg:"cursor target compare equal" int 0
          (S.Record.compare_cursor_target (S.Record.Cr 2) (S.Record.Cr 2));
        expect_invalid_arg ~msg:"negative CR cursor" (fun () ->
            ignore (S.Record.cursor (S.Record.Cr (-1)) : S.Record.cursor));
        is_true ~msg:"CR pp smoke"
          (String.length (pp_to_string S.Record.pp_cr_record cr) > 0);
        is_true ~msg:"cursor pp smoke"
          (String.length (pp_to_string S.Record.pp_cursor cr_cursor) > 0));
    test "compares approval values" (fun () ->
        is_true ~msg:"approval equal"
          (S.Record.equal_approval S.Record.Approved S.Record.Approved);
        is_false ~msg:"approval differs"
          (S.Record.equal_approval S.Record.Pending S.Record.Seconded);
        equal ~msg:"approval compare equal" int 0
          (S.Record.compare_approval S.Record.Seconded S.Record.Seconded));
  ]

let snapshot_tests =
  [
    test "constructs and edits snapshots" (fun () ->
        let k = key ~namespace:"repo" () in
        let store = S.empty ~title:"Store feature" k in
        is_true ~msg:"current version"
          (S.Version.equal S.Version.current (S.version store));
        is_true ~msg:"key" (S.Key.equal k (S.key store));
        equal ~msg:"title" (option string) (Some "Store feature")
          (S.title store);
        is_true ~msg:"pending approval"
          (S.Record.equal_approval S.Record.Pending (S.approval store));
        equal ~msg:"marks" int 0 (List.length (S.marks store));
        equal ~msg:"CR records" int 0 (List.length (S.cr_records store));
        expect_none ~msg:"cursor" (S.cursor store);
        let version = S.Version.v 2 in
        let line_scope = S.Record.new_line ~path:"lib/core.ml" ~line:3 in
        let cr =
          S.Record.cr_record ~scope:line_scope ~digest:(digest "CR alice: fix")
            ~state:S.Record.Open ()
        in
        let mark = S.Record.mark ~scope:line_scope ~state:S.Record.Unreviewed in
        let cursor = S.Record.cursor (S.Record.Scope line_scope) in
        let edited =
          store |> fun t ->
          S.with_version t version |> fun t ->
          S.with_title t (Some "Renamed") |> fun t ->
          S.with_approval t S.Record.Approved |> fun t ->
          S.put_mark t mark |> fun t ->
          S.put_cr_record t cr |> fun t -> S.with_cursor t (Some cursor)
        in
        is_true ~msg:"edited version"
          (S.Version.equal version (S.version edited));
        equal ~msg:"edited title" (option string) (Some "Renamed")
          (S.title edited);
        is_true ~msg:"edited approval"
          (S.Record.equal_approval S.Record.Approved (S.approval edited));
        equal ~msg:"edited marks" int 1 (List.length (S.marks edited));
        is_true ~msg:"edited mark state"
          (S.Record.equal_mark_state S.Record.Unreviewed
             (S.Record.mark_state (List.hd (S.marks edited))));
        equal ~msg:"edited CRs" int 1 (List.length (S.cr_records edited));
        is_true ~msg:"edited cursor"
          (S.Record.equal_cursor cursor
             (expect_some ~msg:"edited cursor" (S.cursor edited)));
        let reviewed_mark =
          S.Record.mark ~scope:line_scope ~state:S.Record.Reviewed
        in
        let replaced_mark = S.put_mark edited reviewed_mark in
        equal ~msg:"mark replaced" int 1 (List.length (S.marks replaced_mark));
        is_true ~msg:"mark replacement state"
          (S.Record.equal_mark_state S.Record.Reviewed
             (S.Record.mark_state (List.hd (S.marks replaced_mark))));
        let removed_mark = S.remove_mark replaced_mark line_scope in
        equal ~msg:"mark removed" int 0 (List.length (S.marks removed_mark));
        let addressed =
          S.Record.cr_record ~scope:line_scope ~digest:(digest "CR alice: fix")
            ~state:S.Record.Addressed ()
        in
        let replaced = S.put_cr_record edited addressed in
        equal ~msg:"CR replaced" int 1 (List.length (S.cr_records replaced));
        is_true ~msg:"CR replacement state"
          (S.Record.equal_cr_state S.Record.Addressed
             (S.Record.cr_state (List.hd (S.cr_records replaced))));
        let without_cr =
          S.remove_cr_record replaced ~digest:(digest "CR alice: fix")
            ~scope:(Some line_scope)
        in
        equal ~msg:"CR removed" int 0 (List.length (S.cr_records without_cr));
        expect_invalid_arg ~msg:"empty title" (fun () ->
            ignore (S.empty ~title:"" k : S.t));
        expect_invalid_arg ~msg:"duplicate marks" (fun () ->
            ignore (S.with_marks store [ mark; reviewed_mark ] : S.t));
        expect_invalid_arg ~msg:"duplicate CR records" (fun () ->
            ignore (S.with_cr_records store [ cr; addressed ] : S.t)));
    test "constructs snapshots from features" (fun () ->
        let feature = sample_feature ~title:"Feature title" () in
        let store = S.of_feature ~namespace:"repo" feature in
        is_true ~msg:"feature key"
          (S.Key.equal
             (S.Key.of_feature ~namespace:"repo" feature)
             (S.key store));
        equal ~msg:"feature title" (option string) (Some "Feature title")
          (S.title store);
        expect_invalid_arg ~msg:"empty namespace" (fun () ->
            ignore (S.of_feature ~namespace:"" feature : S.t)));
  ]

let codec_tests =
  [
    test "round-trips snapshots through backend-neutral values" (fun () ->
        let line_scope = S.Record.new_line ~path:"lib/core.ml" ~line:3 in
        let cr =
          S.Record.cr_record ~scope:line_scope ~digest:(digest "CR alice: fix")
            ~state:S.Record.Accepted ()
        in
        let snapshot =
          S.empty ~version:(S.Version.v 1) ~title:"Codec feature"
            (key ~namespace:"repo" ())
          |> fun t ->
          S.with_approval t S.Record.Seconded |> fun t ->
          S.with_marks t
            [ S.Record.mark ~scope:line_scope ~state:S.Record.Reviewed ]
          |> fun t ->
          S.with_cr_records t [ cr ] |> fun t ->
          S.with_cursor t (Some (S.Record.cursor (S.Record.Cr 0)))
        in
        let encoded = S.Codec.encode S.codec snapshot in
        is_true ~msg:"deterministic encode"
          (equal_value encoded (S.Codec.encode S.codec snapshot));
        let decoded =
          expect_ok ~msg:"decode snapshot" S.Error.pp
            (S.Codec.decode S.codec encoded)
        in
        is_true ~msg:"round-trip snapshot" (S.equal snapshot decoded);
        equal ~msg:"snapshot compare equal" int 0 (S.compare snapshot decoded);
        is_true ~msg:"snapshot pp smoke"
          (String.length (pp_to_string S.pp snapshot) > 0));
    test "reports recoverable decode errors" (fun () ->
        let error =
          expect_error ~msg:"decode null" (S.Codec.decode S.codec S.Codec.Null)
        in
        is_true ~msg:"decode error message"
          (String.length (S.Error.message error) > 0);
        is_true ~msg:"decode error pp smoke"
          (String.length (pp_to_string S.Error.pp error) > 0);
        let version_error =
          expect_error ~msg:"invalid version" (S.Version.of_int 0)
        in
        match version_error with
        | S.Error.Invalid_version 0 -> ()
        | Invalid_version _ | Invalid_key _ | Invalid_path _ | Invalid_range _
        | Duplicate_mark | Duplicate_cr | Decode _ | Io _ ->
            fail "expected Invalid_version 0");
  ]

let review_tests =
  [
    test "constructs snapshots from reviews and restores matching content"
      (fun () ->
        let file_scope = R.Scope.file "lib/new.ml" in
        let line_scope = R.Scope.new_line ~path:"lib/new.ml" ~line:1 in
        let review =
          make_review () |> fun review ->
          expect_ok ~msg:"mark file" R.Error.pp
            (R.mark_reviewed review file_scope)
          |> fun review ->
          expect_ok ~msg:"mark line" R.Error.pp
            (R.mark_unreviewed review line_scope)
          |> fun review ->
          R.set_approval review R.Approval.Seconded |> fun review ->
          expect_ok ~msg:"cursor" R.Error.pp
            (R.set_cursor review (R.Cursor.scope line_scope))
        in
        let store = S.of_review ~namespace:"repo" review in
        equal ~msg:"stored mark count" int 2 (List.length (S.marks store));
        is_true ~msg:"stored approval"
          (S.Record.equal_approval S.Record.Seconded (S.approval store));
        let applied = S.apply_to_review store (make_review ()) in
        is_true ~msg:"file reviewed" (R.is_reviewed applied file_scope);
        is_false ~msg:"line unreviewed" (R.is_reviewed applied line_scope);
        is_true ~msg:"approval restored"
          (R.Approval.equal R.Approval.Seconded (R.approval applied));
        is_true ~msg:"cursor restored"
          (R.Cursor.equal (R.Cursor.scope line_scope) (R.cursor applied)));
    test "restores only same-content reviewed units after content changes"
      (fun () ->
        let file_scope = R.Scope.file "lib/new.ml" in
        let first_line = R.Scope.new_line ~path:"lib/new.ml" ~line:1 in
        let second_line = R.Scope.new_line ~path:"lib/new.ml" ~line:2 in
        let review =
          make_review () |> fun review ->
          expect_ok ~msg:"mark file" R.Error.pp
            (R.mark_reviewed review file_scope)
          |> fun review ->
          R.set_approval review R.Approval.Seconded |> fun review ->
          expect_ok ~msg:"cursor" R.Error.pp
            (R.set_cursor review (R.Cursor.scope first_line))
        in
        let store = S.of_review ~namespace:"repo" review in
        let fresh =
          make_review ~lines:[ added "let value = 1"; added "let extra = 2" ] ()
        in
        let applied = S.apply_to_review store fresh in
        is_true ~msg:"old line reviewed" (R.is_reviewed applied first_line);
        is_false ~msg:"new line unreviewed" (R.is_reviewed applied second_line);
        is_false ~msg:"broad file mark not restored"
          (Option.is_some (R.mark applied file_scope));
        is_true ~msg:"approval reset"
          (R.Approval.equal R.Approval.Pending (R.approval applied));
        is_true ~msg:"valid cursor restored"
          (R.Cursor.equal (R.Cursor.scope first_line) (R.cursor applied)));
    test "does not restore a reviewed line when line content changed" (fun () ->
        let file_scope = R.Scope.file "lib/new.ml" in
        let first_line = R.Scope.new_line ~path:"lib/new.ml" ~line:1 in
        let review =
          make_review () |> fun review ->
          expect_ok ~msg:"mark file" R.Error.pp
            (R.mark_reviewed review file_scope)
        in
        let store = S.of_review ~namespace:"repo" review in
        let fresh =
          make_review
            ~lines:[ added "let inserted = 0"; added "let value = 1" ]
            ()
        in
        let applied = S.apply_to_review store fresh in
        is_false ~msg:"changed line not reviewed"
          (R.is_reviewed applied first_line));
    test "ignores stale marks and stale cursor" (fun () ->
        let stale_scope = S.Record.file ~path:"lib/missing.ml" in
        let stale_mark =
          S.Record.mark ~scope:stale_scope ~state:S.Record.Reviewed
        in
        let stale_cursor = S.Record.cursor (S.Record.Scope stale_scope) in
        let store =
          S.of_feature ~namespace:"repo" (review_feature ()) |> fun store ->
          S.with_marks store [ stale_mark ] |> fun store ->
          S.with_cursor store (Some stale_cursor)
        in
        let fresh = make_review () in
        let applied = S.apply_to_review store fresh in
        equal ~msg:"stale marks ignored" int 0 (List.length (R.marks applied));
        is_true ~msg:"stale cursor ignored"
          (R.Cursor.equal (R.cursor fresh) (R.cursor applied)));
  ]

let fs_tests =
  [
    test "derives deterministic store paths and bridges byte codecs" (fun () ->
        let k = key ~namespace:"repo" () in
        let dir = "/tmp/sift-store" in
        let path = S.Fs.file ~dir k in
        equal ~msg:"deterministic file path" string path (S.Fs.file ~dir k);
        is_true ~msg:"path stays under dir"
          (string_has_prefix ~prefix:(dir ^ Filename.dir_sep) path);
        let writes = ref [] in
        let io : S.Fs.io =
          {
            read = (fun path -> Ok ("41:" ^ path));
            write =
              (fun path bytes ->
                writes := (path, bytes) :: !writes;
                Ok ());
            mkdir_p =
              (fun path ->
                if String.length path < 0 then Error (S.Error.Io path)
                else Ok ());
          }
        in
        let codec : int S.Fs.codec =
          {
            encode = string_of_int;
            decode =
              (fun bytes ->
                match String.split_on_char ':' bytes with
                | value :: _ -> (
                    match int_of_string_opt value with
                    | Some n -> Ok n
                    | None -> Error (S.Error.Decode "invalid int"))
                | [] -> Error (S.Error.Decode "empty payload"));
          }
        in
        equal ~msg:"load" int 41
          (expect_ok ~msg:"load" S.Error.pp (S.Fs.load io codec path));
        ignore
          (expect_ok ~msg:"save" S.Error.pp (S.Fs.save io codec path 42) : unit);
        equal ~msg:"write count" int 1 (List.length !writes);
        match !writes with
        | [ (written_path, written_bytes) ] ->
            equal ~msg:"write path" string path written_path;
            equal ~msg:"write payload" string "42" written_bytes
        | writes -> failf "expected one write, got %d" (List.length writes));
  ]

let () =
  run "sift.store"
    [
      group "keys" key_tests;
      group "records" record_tests;
      group "scopes" scope_tests;
      group "snapshots" snapshot_tests;
      group "codec" codec_tests;
      group "reviews" review_tests;
      group "fs" fs_tests;
    ]
