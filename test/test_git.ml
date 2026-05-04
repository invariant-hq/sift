open Windtrap
module G = Sift_git
module F = Sift_feature
module D = Sift_diff
module C = Sift_crs

let pp_to_string pp x = Format.asprintf "%a" pp x

let expect_git_ok ~msg = function
  | Ok x -> x
  | Error e -> failf "%s: expected Ok _, got %a" msg G.Error.pp e

let expect_git_error ~msg = function
  | Error e -> e
  | Ok _ -> failf "%s: expected Error _" msg

let expect_invalid_arg ~msg f =
  let raised =
    try
      f ();
      false
    with Invalid_argument _ -> true
  in
  is_true ~msg raised

let expect_some ~msg = function
  | Some x -> x
  | None -> failf "%s: expected Some _" msg

let expect_no_git () =
  match Sys.command "git --version > /dev/null 2>&1" with
  | 0 -> ()
  | code -> skip ~reason:(Printf.sprintf "git unavailable: exit %d" code) ()

let quote = Filename.quote

let command_to_string { G.Error.cwd; argv } =
  cwd ^ ": " ^ String.concat " " argv

let status_to_string = function
  | G.Error.Exited code -> Printf.sprintf "exited %d" code
  | G.Error.Signaled signal -> Printf.sprintf "signaled %d" signal
  | G.Error.Stopped signal -> Printf.sprintf "stopped %d" signal

let git_error_kind_name = function
  | G.Error.Invalid_repository _ -> "Invalid_repository"
  | G.Error.No_worktree _ -> "No_worktree"
  | G.Error.Git_not_found _ -> "Git_not_found"
  | G.Error.Git_failed (command, status, stderr) ->
      Printf.sprintf "Git_failed(%s, %s, %S)"
        (command_to_string command)
        (status_to_string status) stderr
  | G.Error.Io message -> "Io(" ^ message ^ ")"
  | G.Error.Diff e -> "Diff(" ^ Format.asprintf "%a" D.Error.pp e ^ ")"

let expect_error_kind ~msg predicate e =
  if not (predicate e) then failf "%s: got %s" msg (git_error_kind_name e)

let run_shell ~msg command =
  match Sys.command command with
  | 0 -> ()
  | code -> failf "%s: command exited %d: %s" msg code command

let read_all ic =
  let b = Buffer.create 256 in
  let chunk = Bytes.create 4096 in
  let rec loop () =
    match input ic chunk 0 (Bytes.length chunk) with
    | 0 -> Buffer.contents b
    | n ->
        Buffer.add_subbytes b chunk 0 n;
        loop ()
  in
  loop ()

let command_output ~msg command =
  let ic = Unix.open_process_in command in
  let output = read_all ic in
  match Unix.close_process_in ic with
  | Unix.WEXITED 0 -> String.trim output
  | Unix.WEXITED code ->
      failf "%s: command exited %d: %s\n%s" msg code command output
  | Unix.WSIGNALED signal ->
      failf "%s: command signaled %d: %s\n%s" msg signal command output
  | Unix.WSTOPPED signal ->
      failf "%s: command stopped %d: %s\n%s" msg signal command output

let remove_tree path =
  let rec loop path =
    if Sys.file_exists path then
      match (Unix.lstat path).st_kind with
      | S_DIR ->
          Array.iter
            (fun name -> loop (Filename.concat path name))
            (Sys.readdir path);
          Unix.rmdir path
      | S_REG | S_LNK | S_CHR | S_BLK | S_FIFO | S_SOCK -> Unix.unlink path
  in
  loop path

let with_temp_dir name f =
  let path = Filename.temp_file ("sift-" ^ name ^ "-") "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  Fun.protect ~finally:(fun () -> remove_tree path) (fun () -> f path)

let make_temp_dir name =
  let path = Filename.temp_file ("sift-" ^ name ^ "-") "" in
  Sys.remove path;
  Unix.mkdir path 0o700;
  path

let mkdir_p path =
  let rec loop path =
    if String.equal path Filename.current_dir_name || String.equal path "/" then
      ()
    else if Sys.file_exists path then ()
    else (
      loop (Filename.dirname path);
      Unix.mkdir path 0o755)
  in
  loop path

let write_file root path content =
  let full = Filename.concat root path in
  mkdir_p (Filename.dirname full);
  let oc = open_out_bin full in
  Fun.protect
    ~finally:(fun () -> close_out_noerr oc)
    (fun () -> output_string oc content)

let remove_file root path = Sys.remove (Filename.concat root path)
let git root args = "git -C " ^ quote root ^ " " ^ args ^ " > /dev/null 2>&1"

let git_output root args =
  command_output ~msg:("git " ^ args)
    ("git -C " ^ quote root ^ " " ^ args ^ " 2>/dev/null")

let git_quiet root args = run_shell ~msg:("git " ^ args) (git root args)

let init_repo root =
  expect_no_git ();
  run_shell ~msg:"git init"
    ("git init -b main " ^ quote root ^ " > /dev/null 2>&1");
  git_quiet root "config user.name Sift";
  git_quiet root "config user.email sift@example.invalid";
  git_quiet root "config core.autocrlf false";
  git_quiet root "config core.safecrlf false"

let commit root ~message =
  git_quiet root "add -A";
  run_shell ~msg:("git commit " ^ message)
    (String.concat " "
       [
         "GIT_AUTHOR_DATE='2001-01-01T00:00:00Z'";
         "GIT_COMMITTER_DATE='2001-01-01T00:00:00Z'";
         "git";
         "-C";
         quote root;
         "commit";
         "-m";
         quote message;
         "> /dev/null 2>&1";
       ]);
  F.Revision.v (git_output root "rev-parse HEAD")

let setup_review_repo root =
  init_repo root;
  write_file root "src/main.ml"
    "let value = 1\n(* CR base: base item should not be scanned *)\n";
  write_file root "src/delete.ml" "(* CR deleted: skip deleted path *)\n";
  write_file root "assets/blob.bin" "\000\001base\000";
  let base = commit root ~message:"base" in
  git_quiet root "update-ref refs/remotes/origin/main HEAD";
  git_quiet root
    "symbolic-ref refs/remotes/origin/HEAD refs/remotes/origin/main";
  write_file root "src/main.ml"
    (String.concat "\n"
       [
         "let value = 2";
         "(* CR tip: first tip item *)";
         "let extra = true";
         "(* XCR-soon reviewer for owner: second tip item *)";
         "";
       ]);
  write_file root "src/added.ml"
    (String.concat "\n"
       [
         "let added = true";
         "(* CR alice: added file item *)";
         "(* CR bad handle!: malformed item is still returned *)";
         "";
       ]);
  remove_file root "src/delete.ml";
  write_file root "assets/blob.bin" "\000\002tip\000";
  let tip = commit root ~message:"tip" in
  (base, tip)

type review_fixture = { root : string; base : F.Revision.t; tip : F.Revision.t }

let review_fixture =
  lazy
    (let root = make_temp_dir "review" in
     at_exit (fun () -> if Sys.file_exists root then remove_tree root);
     let base, tip = setup_review_repo root in
     { root; base; tip })

let with_review_fixture f =
  let fixture = Lazy.force review_fixture in
  f fixture

let repo root = G.v ~root ()
let revision_text = F.Revision.to_string

let expect_revision ~msg expected actual =
  equal ~msg string (revision_text expected) (revision_text actual)

let find_file ~path diff =
  List.find_opt
    (fun file -> String.equal path (D.File.path file))
    (D.files diff)

let expect_file ~msg ~path diff = expect_some ~msg (find_file ~path diff)

let item_body item =
  match C.Item.comment item with
  | Ok comment -> C.Comment.body comment
  | Error e -> Format.asprintf "%a" C.Error.pp e

let expect_item ~msg ~path ~body item =
  equal ~msg:(msg ^ " path") string path (C.Item.path item);
  equal ~msg:(msg ^ " body") string body (item_body item)

let construction_tests =
  [
    test "constructs handles and compares them" (fun () ->
        let a = G.v ~git:"git" ~root:"/tmp/repo" () in
        let same = G.v ~git:"git" ~root:"/tmp/repo" () in
        let different_git = G.v ~git:"custom-git" ~root:"/tmp/repo" () in
        equal ~msg:"root" string "/tmp/repo" (G.root a);
        equal ~msg:"git" string "git" (G.git a);
        is_true ~msg:"equal" (G.equal a same);
        equal ~msg:"compare equal" int 0 (G.compare a same);
        is_false ~msg:"different git" (G.equal a different_git);
        is_true ~msg:"compare distinguishes" (G.compare a different_git <> 0);
        is_true ~msg:"pp smoke" (String.length (pp_to_string G.pp a) > 0));
    test "rejects empty handle arguments" (fun () ->
        expect_invalid_arg ~msg:"empty git" (fun () ->
            ignore (G.v ~git:"" ~root:"/tmp/repo" () : G.t));
        expect_invalid_arg ~msg:"empty root" (fun () ->
            ignore (G.v ~root:"" () : G.t)));
  ]

let discovery_tests =
  [
    test "discovers a repository root from a nested directory" (fun () ->
        with_review_fixture (fun fixture ->
            let cwd = Filename.concat fixture.root "src" in
            let t = expect_git_ok ~msg:"discover" (G.discover ~cwd ()) in
            equal ~msg:"discovered root" string fixture.root (G.root t);
            equal ~msg:"discovered git" string "git" (G.git t)));
    test "reports invalid repositories and missing git executables" (fun () ->
        with_temp_dir "errors" (fun root ->
            let invalid =
              expect_git_error ~msg:"invalid repository"
                (G.discover ~cwd:root ())
            in
            expect_error_kind ~msg:"invalid repository"
              (function
                | G.Error.Invalid_repository path -> String.equal path root
                | _ -> false)
              invalid;
            let missing =
              expect_git_error ~msg:"missing git"
                (G.discover ~git:"sift-git-definitely-missing" ~cwd:root ())
            in
            expect_error_kind ~msg:"missing git"
              (function
                | G.Error.Git_not_found git ->
                    String.equal git "sift-git-definitely-missing"
                | _ -> false)
              missing));
  ]

let revision_tests =
  [
    test "resolves explicit revisions, default tip, default base, and ranges"
      (fun () ->
        with_review_fixture (fun fixture ->
            let t = repo fixture.root in
            let base =
              expect_git_ok ~msg:"resolve HEAD~1"
                (G.resolve_revision t "HEAD~1")
            in
            let tip = expect_git_ok ~msg:"default tip" (G.default_tip t) in
            let default_base =
              expect_git_ok ~msg:"default base" (G.default_base t)
            in
            let range =
              expect_git_ok ~msg:"resolve range"
                (G.resolve ~base:"HEAD~1" ~tip:"HEAD" t ())
            in
            expect_revision ~msg:"resolved base" fixture.base base;
            expect_revision ~msg:"default base" fixture.base default_base;
            expect_revision ~msg:"default tip" fixture.tip tip;
            expect_revision ~msg:"range base" fixture.base range.G.base;
            expect_revision ~msg:"range tip" fixture.tip range.G.tip));
    test "reports failed revisions and rejects empty revision inputs" (fun () ->
        with_review_fixture (fun fixture ->
            let t = repo fixture.root in
            let e =
              expect_git_error ~msg:"bad revision"
                (G.resolve_revision t "refs/heads/does-not-exist")
            in
            expect_error_kind ~msg:"bad revision"
              (function G.Error.Git_failed _ -> true | _ -> false)
              e;
            expect_invalid_arg ~msg:"empty revision" (fun () ->
                ignore
                  (G.resolve_revision t "" : (G.revision, G.Error.t) result));
            expect_invalid_arg ~msg:"empty base" (fun () ->
                ignore (G.resolve ~base:"" t () : (G.range, G.Error.t) result));
            expect_invalid_arg ~msg:"empty tip" (fun () ->
                ignore
                  (G.default_base ~tip:"" t : (G.revision, G.Error.t) result))));
  ]

let diff_tests =
  [
    test "generates parsed diffs for added, deleted, modified, and binary files"
      (fun () ->
        with_review_fixture (fun fixture ->
            let t = repo fixture.root in
            let diff =
              expect_git_ok ~msg:"diff"
                (G.diff t { G.base = fixture.base; tip = fixture.tip })
            in
            equal ~msg:"file count" int 4 (D.file_count diff);
            let added =
              expect_file ~msg:"added file" ~path:"src/added.ml" diff
            in
            let deleted =
              expect_file ~msg:"deleted file" ~path:"src/delete.ml" diff
            in
            let modified =
              expect_file ~msg:"modified file" ~path:"src/main.ml" diff
            in
            let binary =
              expect_file ~msg:"binary file" ~path:"assets/blob.bin" diff
            in
            is_true ~msg:"added status"
              (D.File.equal_status D.File.Added (D.File.status added));
            is_true ~msg:"deleted status"
              (D.File.equal_status D.File.Deleted (D.File.status deleted));
            is_true ~msg:"modified status"
              (D.File.equal_status D.File.Modified (D.File.status modified));
            is_true ~msg:"binary content" (D.File.is_binary binary);
            is_true ~msg:"text content" (D.File.is_text modified)));
  ]

let cr_tests =
  [
    test "scans CR items from tip-side text paths only, in diff order"
      (fun () ->
        with_review_fixture (fun fixture ->
            let t = repo fixture.root in
            let base = fixture.base in
            let tip = fixture.tip in
            let diff = expect_git_ok ~msg:"diff" (G.diff t { G.base; tip }) in
            let items =
              expect_git_ok ~msg:"cr items" (G.cr_items t ~tip ~diff)
            in
            match items with
            | [ added; malformed; main_first; main_second ] ->
                expect_item ~msg:"added" ~path:"src/added.ml"
                  ~body:"added file item" added;
                equal ~msg:"malformed path" string "src/added.ml"
                  (C.Item.path malformed);
                is_false ~msg:"malformed item" (C.Item.is_valid malformed);
                expect_item ~msg:"main first" ~path:"src/main.ml"
                  ~body:"first tip item" main_first;
                expect_item ~msg:"main second" ~path:"src/main.ml"
                  ~body:"second tip item" main_second
            | items ->
                failf "expected four CR items, got %d" (List.length items)));
  ]

let load_tests =
  [
    test "loads uncommitted tracked worktree changes" (fun () ->
        with_temp_dir "worktree" (fun root ->
            let _base, tip = setup_review_repo root in
            write_file root "src/main.ml"
              (String.concat "\n"
                 [
                   "let value = 3";
                   "(* CR worktree: uncommitted item *)";
                   "let extra = true";
                   "";
                 ]);
            let t = repo root in
            let input =
              expect_git_ok ~msg:"load worktree"
                (G.load_worktree ~title:"Worktree review" t ())
            in
            equal ~msg:"title" (option string) (Some "Worktree review")
              (F.title input.G.feature);
            expect_revision ~msg:"feature base" tip (F.base input.G.feature);
            equal ~msg:"feature tip" string "WORKTREE"
              (F.Revision.to_string (F.tip input.G.feature));
            equal ~msg:"loaded files" int 1
              (D.file_count (F.diff input.G.feature));
            let file =
              expect_file ~msg:"worktree file" ~path:"src/main.ml"
                (F.diff input.G.feature)
            in
            is_true ~msg:"worktree file modified"
              (D.File.equal_status D.File.Modified (D.File.status file));
            match input.G.cr_items with
            | [ item ] ->
                expect_item ~msg:"worktree CR" ~path:"src/main.ml"
                  ~body:"uncommitted item" item
            | items ->
                failf "expected one worktree CR item, got %d"
                  (List.length items)));
    test "loads a feature and CR items from an explicit review range" (fun () ->
        with_review_fixture (fun fixture ->
            let t = repo fixture.root in
            let input =
              expect_git_ok ~msg:"load"
                (G.load ~title:"Fixture review" ~base:"HEAD~1" ~tip:"HEAD" t ())
            in
            equal ~msg:"title" (option string) (Some "Fixture review")
              (F.title input.G.feature);
            expect_revision ~msg:"feature base" fixture.base
              (F.base input.G.feature);
            expect_revision ~msg:"feature tip" fixture.tip
              (F.tip input.G.feature);
            equal ~msg:"loaded files" int 4
              (D.file_count (F.diff input.G.feature));
            equal ~msg:"loaded CR items" int 4 (List.length input.G.cr_items)));
    test "reports load errors at the failing stage and rejects empty titles"
      (fun () ->
        with_review_fixture (fun fixture ->
            let t = repo fixture.root in
            let e =
              expect_git_error ~msg:"load bad base"
                (G.load ~base:"refs/heads/does-not-exist" t ())
            in
            expect_error_kind ~msg:"load bad base"
              (function G.Error.Git_failed _ -> true | _ -> false)
              e;
            expect_invalid_arg ~msg:"empty title" (fun () ->
                ignore (G.load ~title:"" t () : (G.input, G.Error.t) result))));
  ]

let fingerprint_tests =
  [
    test "worktree fingerprint follows tracked content changes" (fun () ->
        with_temp_dir "fingerprint" (fun root ->
            let _, _ = setup_review_repo root in
            let t = repo root in
            let fingerprint () =
              expect_git_ok ~msg:"worktree fingerprint"
                (G.worktree_fingerprint t)
            in
            let initial = fingerprint () in
            write_file root "src/main.ml"
              (String.concat "\n"
                 [
                   "let value = 3";
                   "(* CR worktree: uncommitted item *)";
                   "let extra = true";
                   "";
                 ]);
            let changed = fingerprint () in
            is_false ~msg:"tracked edit changes fingerprint"
              (G.Fingerprint.equal initial changed);
            write_file root "src/main.ml"
              (String.concat "\n"
                 [
                   "let value = 4";
                   "(* CR worktree: uncommitted item *)";
                   "let extra = true";
                   "";
                 ]);
            let changed_again = fingerprint () in
            is_false ~msg:"second tracked edit changes fingerprint"
              (G.Fingerprint.equal changed changed_again);
            write_file root "src/untracked.ml" "let ignored = true\n";
            is_true ~msg:"untracked file ignored"
              (G.Fingerprint.equal changed_again (fingerprint ()))));
    test "default worktree fingerprint follows HEAD after commit" (fun () ->
        with_temp_dir "fingerprint-commit" (fun root ->
            let _, _ = setup_review_repo root in
            let t = repo root in
            let fingerprint () =
              expect_git_ok ~msg:"worktree fingerprint"
                (G.worktree_fingerprint t)
            in
            let initial = fingerprint () in
            write_file root "src/main.ml"
              (String.concat "\n"
                 [
                   "let value = 3";
                   "(* CR worktree: uncommitted item *)";
                   "let extra = true";
                   "";
                 ]);
            let changed = fingerprint () in
            is_false ~msg:"tracked edit changes fingerprint"
              (G.Fingerprint.equal initial changed);
            git_quiet root "add src/main.ml";
            ignore
              (commit root ~message:"commit worktree changes" : F.Revision.t);
            is_true ~msg:"committed changes no longer appear in worktree diff"
              (G.Fingerprint.equal initial (fingerprint ()))));
    test "worktree fingerprint honors explicit base" (fun () ->
        with_temp_dir "fingerprint-base" (fun root ->
            let base, _ = setup_review_repo root in
            write_file root "src/main.ml" "let value = 5\n";
            let t = repo root in
            let default =
              expect_git_ok ~msg:"default fingerprint"
                (G.worktree_fingerprint t)
            in
            let explicit =
              expect_git_ok ~msg:"explicit base fingerprint"
                (G.worktree_fingerprint ~base:(F.Revision.to_string base) t)
            in
            is_false ~msg:"explicit base changes diff basis"
              (G.Fingerprint.equal default explicit)));
    test "worktree fingerprint rejects empty base" (fun () ->
        with_review_fixture (fun fixture ->
            let t = repo fixture.root in
            expect_invalid_arg ~msg:"empty base" (fun () ->
                ignore
                  (G.worktree_fingerprint ~base:"" t
                    : (G.Fingerprint.t, G.Error.t) result))));
  ]

let () =
  run "sift.git"
    [
      group "construction" construction_tests;
      group "discovery" discovery_tests;
      group "revisions" revision_tests;
      group "diffs" diff_tests;
      group "CR scanning" cr_tests;
      group "loading" load_tests;
      group "fingerprints" fingerprint_tests;
    ]
