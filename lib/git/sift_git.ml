module Error = Error

type revision = Sift_feature.Revision.t
type range = { base : revision; tip : revision }
type input = { feature : Sift_feature.t; cr_items : Sift_crs.Item.t list }

module Fingerprint = struct
  type t = string

  let v s =
    if String.equal s "" then invalid_arg "Sift_git.Fingerprint.v: empty";
    s

  let equal = String.equal
  let pp = Format.pp_print_string
end

type worktree_input = { input : input; fingerprint : Fingerprint.t }
type t = { git : string; root : string }

let ( let* ) = Result.bind

let check_non_empty name value =
  if String.equal value "" then invalid_arg ("Sift_git." ^ name)

let v ?(git = "git") ~root () =
  check_non_empty "v: git" git;
  check_non_empty "v: root" root;
  { git; root }

let root t = t.root
let git t = t.git

let status_of_unix = function
  | Unix.WEXITED code -> Error.Exited code
  | Unix.WSIGNALED signal -> Signaled signal
  | Unix.WSTOPPED signal -> Stopped signal

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
      let len = in_channel_length ic in
      really_input_string ic len)

let with_temp_file prefix f =
  let path = Filename.temp_file prefix ".tmp" in
  Fun.protect
    ~finally:(fun () -> if Sys.file_exists path then Sys.remove path)
    (fun () -> f path)

let command ~cwd ~git args = { Error.cwd; argv = git :: "-C" :: cwd :: args }
let close_noerr fd = try Unix.close fd with Unix.Unix_error _ -> ()

let with_fd fd f =
  Fun.protect ~finally:(fun () -> close_noerr fd) (fun () -> f fd)

let with_openfile path flags perm f =
  let fd = Unix.openfile path flags perm in
  with_fd fd f

let run_process (command : Error.command) ~git ~stdin_fd ~stdout_fd ~stderr_fd =
  let pid =
    Unix.create_process git
      (Array.of_list command.argv)
      stdin_fd stdout_fd stderr_fd
  in
  let _, status = Unix.waitpid [] pid in
  status

let run_git_raw ~cwd ~git args =
  let command = command ~cwd ~git args in
  try
    with_temp_file "sift-git-out-" (fun stdout_path ->
        with_temp_file "sift-git-err-" (fun stderr_path ->
            with_openfile Filename.null [ Unix.O_RDONLY ] 0 (fun stdin_fd ->
                with_openfile stdout_path [ Unix.O_WRONLY; Unix.O_TRUNC ] 0o600
                  (fun stdout_fd ->
                    with_openfile stderr_path [ Unix.O_WRONLY; Unix.O_TRUNC ]
                      0o600 (fun stderr_fd ->
                        let status =
                          run_process command ~git ~stdin_fd ~stdout_fd
                            ~stderr_fd
                        in
                        let stdout = read_file stdout_path in
                        let stderr = read_file stderr_path in
                        Ok (stdout, stderr, status_of_unix status, command))))))
  with
  | Unix.Unix_error (Unix.ENOENT, _, _) -> Error (Error.Git_not_found git)
  | Unix.Unix_error (code, name, arg) ->
      Error
        (Error.Io
           (Printf.sprintf "%s(%s): %s" name arg (Unix.error_message code)))

let run_git ~cwd ~git args =
  let* stdout, stderr, status, command = run_git_raw ~cwd ~git args in
  match status with
  | Error.Exited 0 ->
      ignore (stderr : string);
      ignore (command : Error.command);
      Ok stdout
  | Error.Exited _ | Error.Signaled _ | Error.Stopped _ ->
      Error (Error.Git_failed (command, status, stderr))

let trim = String.trim

let prefix_depth prefix =
  String.split_on_char '/' prefix
  |> List.filter (fun part -> not (String.equal part ""))
  |> List.length

let dirname_n path n =
  let rec loop path n =
    if n = 0 then path else loop (Filename.dirname path) (n - 1)
  in
  loop path n

let discovered_root ~cwd ~git_root ~prefix =
  let prefix = trim prefix in
  if String.equal prefix "" then git_root
  else dirname_n cwd (prefix_depth prefix)

let run_git_trimmed ~cwd ~git args =
  let* stdout = run_git ~cwd ~git args in
  Ok (trim stdout)

let invalid_repository cwd = Error (Error.Invalid_repository cwd)
let no_worktree cwd = Error (Error.No_worktree cwd)

let discover_root ~cwd ~git =
  match run_git_trimmed ~cwd ~git [ "rev-parse"; "--show-toplevel" ] with
  | Error (Error.Git_failed _) -> no_worktree cwd
  | Error error -> Error error
  | Ok git_root ->
      let* prefix = run_git ~cwd ~git [ "rev-parse"; "--show-prefix" ] in
      Ok (discovered_root ~cwd ~git_root ~prefix)

let discover_worktree ~cwd ~git =
  match run_git_raw ~cwd ~git [ "rev-parse"; "--is-inside-work-tree" ] with
  | Error error -> Error error
  | Ok (stdout, stderr, Error.Exited 0, command) ->
      ignore (stderr : string);
      ignore (command : Error.command);
      if String.equal (trim stdout) "true" then discover_root ~cwd ~git
      else no_worktree cwd
  | Ok (stdout, stderr, status, command) ->
      ignore (stdout : string);
      ignore (stderr : string);
      ignore (status : Error.status);
      ignore (command : Error.command);
      invalid_repository cwd

let discover ?(git = "git") ?cwd () =
  check_non_empty "discover: git" git;
  let cwd = match cwd with Some cwd -> cwd | None -> Sys.getcwd () in
  check_non_empty "discover: cwd" cwd;
  match discover_worktree ~cwd ~git with
  | Ok root -> Ok (v ~git ~root ())
  | Error error -> Error error

let revision_of_stdout stdout = Sift_feature.Revision.v (trim stdout)

let resolve_revision t spec =
  check_non_empty "resolve_revision" spec;
  let* stdout =
    run_git ~cwd:t.root ~git:t.git
      [ "rev-parse"; "--verify"; spec ^ "^{commit}" ]
  in
  Ok (revision_of_stdout stdout)

let default_tip t = resolve_revision t "HEAD"

let merge_base t ~tip reference =
  let* stdout =
    run_git ~cwd:t.root ~git:t.git [ "merge-base"; tip; reference ]
  in
  Ok (revision_of_stdout stdout)

let current_upstream t =
  run_git_trimmed ~cwd:t.root ~git:t.git
    [ "rev-parse"; "--abbrev-ref"; "--symbolic-full-name"; "@{upstream}" ]

let default_base ?(tip = "HEAD") t =
  check_non_empty "default_base: tip" tip;
  match current_upstream t with
  | Ok upstream -> merge_base t ~tip upstream
  | Error (Error.Git_not_found _ as error) -> Error error
  | Error (Error.Io _ as error) -> Error error
  | Error (Error.Diff _ as error) -> Error error
  | Error (Error.Invalid_repository _ as error) -> Error error
  | Error (Error.No_worktree _ as error) -> Error error
  | Error (Error.Git_failed _) -> merge_base t ~tip "origin/HEAD"

let resolve ?base ?(tip = "HEAD") t () =
  Option.iter (check_non_empty "resolve: base") base;
  check_non_empty "resolve: tip" tip;
  let tip_spec = tip in
  let* tip = resolve_revision t tip_spec in
  let* base =
    match base with
    | Some base -> resolve_revision t base
    | None -> default_base ~tip:tip_spec t
  in
  Ok { base; tip }

let diff t range =
  let base = Sift_feature.Revision.to_string range.base in
  let tip = Sift_feature.Revision.to_string range.tip in
  let* stdout =
    run_git ~cwd:t.root ~git:t.git
      [ "diff"; "--no-color"; "--no-ext-diff"; base; tip ]
  in
  match Sift_diff.Parser.unified stdout with
  | Ok diff -> Ok diff
  | Error error -> Error (Error.Diff error)

let worktree_tip = Sift_feature.Revision.v "WORKTREE"

let worktree_diff t ~base =
  let base = Sift_feature.Revision.to_string base in
  let* stdout =
    run_git ~cwd:t.root ~git:t.git
      [ "diff"; "--no-color"; "--no-ext-diff"; base ]
  in
  match Sift_diff.Parser.unified stdout with
  | Ok diff -> Ok diff
  | Error error -> Error (Error.Diff error)

let file_is_deleted file =
  Sift_diff.File.equal_status
    (Sift_diff.File.status file)
    Sift_diff.File.Deleted

let cr_path file =
  if Sift_diff.File.is_text file && not (file_is_deleted file) then
    Sift_diff.File.new_path file
  else None

let blob_spec ~tip ~path = Sift_feature.Revision.to_string tip ^ ":" ^ path

let source t ~tip ~path =
  check_non_empty "source: path" path;
  run_git ~cwd:t.root ~git:t.git
    [ "show"; "--no-ext-diff"; blob_spec ~tip ~path ]

let cr_items_for_path t ~tip path =
  let* source = source t ~tip ~path in
  Ok (Sift_crs.Parser.source ~path source)

let worktree_path t path = Filename.concat t.root path

let worktree_source t ~path =
  check_non_empty "worktree_source: path" path;
  try Ok (read_file (worktree_path t path))
  with Sys_error message -> Error (Error.Io message)

let worktree_cr_items_for_path t path =
  let* source = worktree_source t ~path in
  Ok (Sift_crs.Parser.source ~path source)

let cr_items_for_file t ~tip file =
  match cr_path file with
  | None -> Ok []
  | Some path -> cr_items_for_path t ~tip path

let cr_items t ~tip ~diff =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | file :: files ->
        let* items = cr_items_for_file t ~tip file in
        loop (List.rev_append items acc) files
  in
  loop [] (Sift_diff.files diff)

let worktree_cr_items_for_file t file =
  match cr_path file with
  | None -> Ok []
  | Some path -> worktree_cr_items_for_path t path

let worktree_cr_items t ~diff =
  let rec loop acc = function
    | [] -> Ok (List.rev acc)
    | file :: files ->
        let* items = worktree_cr_items_for_file t file in
        loop (List.rev_append items acc) files
  in
  loop [] (Sift_diff.files diff)

let load ?title ?base ?tip t () =
  Option.iter (check_non_empty "load: title") title;
  let* range = resolve ?base ?tip t () in
  let* diff = diff t range in
  let* cr_items = cr_items t ~tip:range.tip ~diff in
  let feature =
    Sift_feature.v ?title ~base:range.base ~tip:range.tip ~diff ()
  in
  Ok { feature; cr_items }

let load_worktree ?title ?base t () =
  Option.iter (check_non_empty "load_worktree: title") title;
  Option.iter (check_non_empty "load_worktree: base") base;
  let* base =
    match base with
    | Some base -> resolve_revision t base
    | None -> default_tip t
  in
  let* diff = worktree_diff t ~base in
  let* cr_items = worktree_cr_items t ~diff in
  let feature = Sift_feature.v ?title ~base ~tip:worktree_tip ~diff () in
  Ok { feature; cr_items }

let worktree_fingerprint ?base t =
  Option.iter (check_non_empty "worktree_fingerprint: base") base;
  let* base =
    match base with
    | Some base -> resolve_revision t base
    | None -> default_tip t
  in
  let base = Sift_feature.Revision.to_string base in
  let* stdout =
    run_git ~cwd:t.root ~git:t.git
      [ "diff"; "--no-color"; "--no-ext-diff"; base ]
  in
  Ok (Digest.to_hex (Digest.string stdout))

let load_worktree_stable ?title ?base t () =
  Option.iter (check_non_empty "load_worktree_stable: title") title;
  Option.iter (check_non_empty "load_worktree_stable: base") base;
  let* before = worktree_fingerprint ?base t in
  let* input = load_worktree ?title ?base t () in
  let* after = worktree_fingerprint ?base t in
  if Fingerprint.equal before after then Ok { input; fingerprint = after }
  else Error (Error.Io "worktree changed while loading review input")

let equal a b = String.equal a.git b.git && String.equal a.root b.root

let compare a b =
  match String.compare a.git b.git with
  | 0 -> String.compare a.root b.root
  | n -> n

let pp ppf t = Format.fprintf ppf "%s:%s" t.git t.root
