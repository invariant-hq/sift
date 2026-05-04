type config = {
  cwd : string option;
  git : string;
  base : string option;
  tip : string option;
  title : string option;
}

type parse_result = Run of config | Help

exception Cli_error of string

let program = "sift"

let usage =
  String.concat "\n"
    [
      "Usage: sift [OPTIONS]";
      "";
      "Launch a Git-backed Sift review TUI.";
      "";
      "Options:";
      "  -C, --cwd DIR      Discover the Git repository from DIR";
      "      --git PATH     Git executable to use (default: git)";
      "      --base REV     Explicit review base";
      "      --tip REV      Review tip (default: HEAD)";
      "      --title TITLE  Feature title";
      "  -h, --help         Show this help";
    ]

let require_value option_name args =
  match args with
  | value :: rest when String.length value > 0 -> (value, rest)
  | _ -> raise (Cli_error (Printf.sprintf "%s requires a value" option_name))

let split_long_option arg =
  match String.index_opt arg '=' with
  | None -> (arg, None)
  | Some index ->
      let name = String.sub arg 0 index in
      let value = String.sub arg (index + 1) (String.length arg - index - 1) in
      (name, Some value)

let value_for_long_option name inline args =
  match inline with
  | Some value when String.length value > 0 -> (value, args)
  | Some _ -> raise (Cli_error (Printf.sprintf "%s requires a value" name))
  | None -> require_value name args

let parse argv =
  let rec loop config = function
    | [] -> Run config
    | "-h" :: rest | "--help" :: rest ->
        if rest = [] then Help
        else raise (Cli_error "--help takes no arguments")
    | "-C" :: rest ->
        let cwd, rest = require_value "-C" rest in
        loop { config with cwd = Some cwd } rest
    | arg :: rest when String.length arg > 2 && String.sub arg 0 2 = "--" -> (
        let name, inline = split_long_option arg in
        match name with
        | "--cwd" ->
            let cwd, rest = value_for_long_option name inline rest in
            loop { config with cwd = Some cwd } rest
        | "--git" ->
            let git, rest = value_for_long_option name inline rest in
            loop { config with git } rest
        | "--base" ->
            let base, rest = value_for_long_option name inline rest in
            loop { config with base = Some base } rest
        | "--tip" ->
            let tip, rest = value_for_long_option name inline rest in
            loop { config with tip = Some tip } rest
        | "--title" ->
            let title, rest = value_for_long_option name inline rest in
            loop { config with title = Some title } rest
        | _ -> raise (Cli_error (Printf.sprintf "unknown option %s" name)))
    | arg :: _ when String.length arg > 0 && arg.[0] = '-' ->
        raise (Cli_error (Printf.sprintf "unknown option %s" arg))
    | arg :: _ ->
        raise (Cli_error (Printf.sprintf "unexpected argument %s" arg))
  in
  let args =
    match Array.to_list argv with _program :: args -> args | [] -> []
  in
  loop { cwd = None; git = "git"; base = None; tip = None; title = None } args

let print_usage out_channel =
  output_string out_channel usage;
  output_char out_channel '\n'

let exit_with_usage message =
  Printf.eprintf "%s: %s\n\n" program message;
  print_usage stderr;
  exit 2

let exit_with_error message =
  Printf.eprintf "%s: %s\n" program message;
  exit 1

let ( let* ) = Result.bind

let review_of_input input =
  Sift_review.v ~feature:input.Sift_git.feature ~cr_items:input.cr_items

let should_watch config =
  match (config.base, config.tip) with
  | None, None -> true
  | Some _, _ | None, Some _ -> false

let load_input config repo =
  let load =
    match (config.base, config.tip) with
    | None, None -> Sift_git.load_worktree ?title:config.title repo
    | Some _, _ | None, Some _ ->
        Sift_git.load ?title:config.title ?base:config.base ?tip:config.tip repo
  in
  match load () with
  | Error error ->
      Error
        (Format.asprintf "review loading failed: %a" Sift_git.Error.pp error)
  | Ok input -> Ok input

let load_review config repo =
  let* input = load_input config repo in
  Ok (review_of_input input)

type initial_review = {
  review : Sift_review.t;
  fingerprint : Sift_git.Fingerprint.t option;
}

let load_initial_review config repo =
  if should_watch config then
    match Sift_git.load_worktree_stable ?title:config.title repo () with
    | Error error ->
        Error
          (Format.asprintf "review loading failed: %a" Sift_git.Error.pp error)
    | Ok { input; fingerprint } ->
        Ok { review = review_of_input input; fingerprint = Some fingerprint }
  else
    let* review = load_review config repo in
    Ok { review; fingerprint = None }

let base_of_review review =
  let feature = Sift_review.feature review in
  Sift_feature.Revision.to_string (Sift_feature.base feature)

let worktree_base config review =
  if should_watch config then None else Some (base_of_review review)

let worktree_fingerprint config repo review =
  match
    Sift_git.worktree_fingerprint ?base:(worktree_base config review) repo
  with
  | Ok fingerprint -> Ok fingerprint
  | Error error ->
      Error
        (Format.asprintf "worktree fingerprint failed: %a" Sift_git.Error.pp
           error)

let discover config =
  match Sift_git.discover ~git:config.git ?cwd:config.cwd () with
  | Ok repo -> Ok repo
  | Error error ->
      Error
        (Format.asprintf "Git repository discovery failed: %a" Sift_git.Error.pp
           error)

let read_file path =
  let ic = open_in_bin path in
  Fun.protect
    ~finally:(fun () -> close_in_noerr ic)
    (fun () ->
      let len = in_channel_length ic in
      really_input_string ic len)

let write_file path content =
  let oc = open_out_bin path in
  Fun.protect
    ~finally:(fun () -> close_out_noerr oc)
    (fun () -> output_string oc content)

let store_namespace repo = Sift_git.root repo

let state_home () =
  match Sys.getenv_opt "XDG_STATE_HOME" with
  | Some dir when not (String.equal (String.trim dir) "") -> dir
  | Some _ | None -> (
      match Sys.getenv_opt "HOME" with
      | Some home when not (String.equal (String.trim home) "") ->
          Filename.concat (Filename.concat home ".local") "state"
      | Some _ | None -> Filename.get_temp_dir_name ())

let store_dir () =
  Filename.concat (Filename.concat (state_home ()) "sift") "reviews"

let rec mkdir_p path =
  if String.equal path "" || String.equal path Filename.current_dir_name then
    Ok ()
  else if Sys.file_exists path then
    if Sys.is_directory path then Ok () else Error (path ^ " is not a directory")
  else
    let parent = Filename.dirname path in
    match if String.equal parent path then Ok () else mkdir_p parent with
    | Error message -> Error message
    | Ok () -> (
        try
          Sys.mkdir path 0o755;
          Ok ()
        with Sys_error message ->
          if Sys.file_exists path && Sys.is_directory path then Ok ()
          else Error message)

let store_io : Sift_store.Fs.io =
  {
    read =
      (fun path ->
        try Ok (read_file path)
        with Sys_error message -> Error (Sift_store.Error.Io message));
    write =
      (fun path bytes ->
        try
          write_file path bytes;
          Ok ()
        with Sys_error message -> Error (Sift_store.Error.Io message));
    mkdir_p =
      (fun path ->
        Result.map_error
          (fun message -> Sift_store.Error.Io message)
          (mkdir_p path));
  }

let store_byte_codec : Sift_store.t Sift_store.Fs.codec =
  {
    encode =
      (fun store ->
        Marshal.to_string (Sift_store.Codec.encode Sift_store.codec store) []);
    decode =
      (fun bytes ->
        try
          let value : Sift_store.Codec.value = Marshal.from_string bytes 0 in
          Sift_store.Codec.decode Sift_store.codec value
        with _ -> Error (Sift_store.Error.Decode "invalid store file"));
  }

let store_path repo review =
  let store = Sift_store.of_review ~namespace:(store_namespace repo) review in
  Sift_store.Fs.file ~dir:(store_dir ()) (Sift_store.key store)

let load_stored_review repo review =
  let path = store_path repo review in
  if not (Sys.file_exists path) then Ok review
  else
    match Sift_store.Fs.load store_io store_byte_codec path with
    | Error error ->
        Error
          (Format.asprintf "review state loading failed: %a" Sift_store.Error.pp
             error)
    | Ok store -> Ok (Sift_store.apply_to_review store review)

let save_review repo review =
  let store = Sift_store.of_review ~namespace:(store_namespace repo) review in
  let path = Sift_store.Fs.file ~dir:(store_dir ()) (Sift_store.key store) in
  match Sift_store.Fs.save store_io store_byte_codec path store with
  | Ok () -> Ok ()
  | Error error ->
      Error
        (Format.asprintf "review state saving failed: %a" Sift_store.Error.pp
           error)

let extension path =
  match String.rindex_opt path '.' with
  | None -> ""
  | Some index ->
      String.lowercase_ascii
        (String.sub path index (String.length path - index))

let syntax_for_path path =
  match extension path with
  | ".ml" | ".mli" -> Sift_crs.Syntax.Ocaml_block
  | ".sh" | ".py" | ".rb" | ".yml" | ".yaml" | ".toml" -> Shell_line
  | ".lisp" | ".scm" | ".el" -> Lisp_line
  | ".sql" -> Sql_line
  | ".xml" | ".html" | ".htm" -> Xml_block
  | _ -> C_line

let reporter () =
  let fallback = "reviewer" in
  let candidate =
    match Sys.getenv_opt "USER" with
    | Some user when not (String.equal (String.trim user) "") -> user
    | Some _ | None -> fallback
  in
  match Sift_crs.Handle.of_string candidate with
  | Ok handle -> handle
  | Error _ -> Sift_crs.Handle.v fallback

let comment_for_body body =
  let header = Sift_crs.Header.make ~reporter:(reporter ()) () in
  Sift_crs.Comment.make ~header ~body

let target_of_scope scope =
  match Sift_review.Scope.view scope with
  | Feature -> Error "cannot attach a comment to the whole feature yet"
  | File path -> Ok (path, Sift_crs.Edit.End_of_file)
  | Hunk hunk ->
      let anchor =
        if hunk.new_count > 0 && hunk.new_start > 0 then
          Sift_crs.Edit.Before_line hunk.new_start
        else End_of_file
      in
      Ok (hunk.path, anchor)
  | Line (_, path, line) -> Ok (path, Sift_crs.Edit.Before_line line)

let add_comment repo (comment : Sift_tui.comment) =
  match target_of_scope comment.scope with
  | Error message -> Error message
  | Ok (path, anchor) -> (
      let full_path = Filename.concat (Sift_git.root repo) path in
      try
        let source = read_file full_path in
        let syntax = syntax_for_path path in
        let cr = comment_for_body comment.body in
        match Sift_crs.Edit.attach ~source ~syntax ~anchor cr with
        | Error error -> Error (Format.asprintf "%a" Sift_crs.Error.pp error)
        | Ok edit -> (
            match Sift_crs.Edit.apply edit ~source with
            | Error error ->
                Error (Format.asprintf "%a" Sift_crs.Error.pp error)
            | Ok source ->
                write_file full_path source;
                Ok path)
      with Sys_error message -> Error message)

let source_range_valid source start_offset stop_offset =
  start_offset >= 0 && stop_offset >= start_offset
  && stop_offset <= String.length source

let line_start_before source offset =
  let rec loop i =
    if i <= 0 then 0 else if source.[i - 1] = '\n' then i else loop (i - 1)
  in
  loop offset

let line_end_after source offset =
  let len = String.length source in
  let rec loop i =
    if i >= len || source.[i] = '\n' then i else loop (i + 1)
  in
  loop offset

let only_line_space source start_offset stop_offset =
  let rec loop i =
    if i >= stop_offset then true
    else
      match source.[i] with
      | ' ' | '\t' | '\r' -> loop (i + 1)
      | _ -> false
  in
  loop start_offset

let remove_source_range source start_offset stop_offset =
  String.sub source 0 start_offset
  ^ String.sub source stop_offset (String.length source - stop_offset)

let remove_cr_source source item =
  let span = Sift_crs.Item.span item in
  let start_offset = Sift_crs.Span.start_offset span in
  let stop_offset = Sift_crs.Span.stop_offset span in
  if source_range_valid source start_offset stop_offset then (
    let line_start = line_start_before source start_offset in
    let line_end = line_end_after source stop_offset in
    if
      only_line_space source line_start start_offset
      && only_line_space source stop_offset line_end
    then
      let stop_offset =
        if line_end < String.length source && source.[line_end] = '\n' then
          line_end + 1
        else line_end
      in
      Ok (remove_source_range source line_start stop_offset)
    else Sift_crs.Edit.apply (Sift_crs.Edit.remove item) ~source)
  else Sift_crs.Edit.apply (Sift_crs.Edit.remove item) ~source

let remove_cr repo (cr : Sift_tui.cr) =
  let item = cr.item in
  let path = Sift_crs.Item.path item in
  let full_path = Filename.concat (Sift_git.root repo) path in
  try
    let source = read_file full_path in
    match remove_cr_source source item with
    | Error error -> Error (Format.asprintf "%a" Sift_crs.Error.pp error)
    | Ok source ->
        write_file full_path source;
        Ok ()
  with Sys_error message -> Error message

let replace_cr repo (cr : Sift_tui.cr) comment =
  let item = cr.item in
  let path = Sift_crs.Item.path item in
  let full_path = Filename.concat (Sift_git.root repo) path in
  try
    let source = read_file full_path in
    match Sift_crs.Edit.replace item comment with
    | Error error -> Error (Format.asprintf "%a" Sift_crs.Error.pp error)
    | Ok edit -> (
        match Sift_crs.Edit.apply edit ~source with
        | Error error -> Error (Format.asprintf "%a" Sift_crs.Error.pp error)
        | Ok source ->
            write_file full_path source;
            Ok path)
  with Sys_error message -> Error message

let edit_cr repo (cr : Sift_tui.cr) body =
  match Sift_crs.Item.comment cr.item with
  | Error error -> Error (Format.asprintf "%a" Sift_crs.Error.pp error)
  | Ok comment ->
      let comment =
        Sift_crs.Comment.make ~header:(Sift_crs.Comment.header comment) ~body
      in
      replace_cr repo cr comment

let resolved_comment comment =
  let header =
    Sift_crs.Header.make ~status:Sift_crs.Status.XCR
      ~priority:(Sift_crs.Comment.priority comment)
      ~reporter:(reporter ())
      ~recipient:(Sift_crs.Comment.reporter comment)
      ()
  in
  Sift_crs.Comment.make ~header ~body:(Sift_crs.Comment.body comment)

let resolve_cr repo (cr : Sift_tui.cr) =
  match Sift_crs.Item.comment cr.item with
  | Error error -> Error (Format.asprintf "%a" Sift_crs.Error.pp error)
  | Ok comment -> replace_cr repo cr (resolved_comment comment)

let cr_body item =
  match Sift_crs.Item.comment item with
  | Error _ -> None
  | Ok comment -> Some (String.trim (Sift_crs.Comment.body comment))

let cr_status item =
  match Sift_crs.Item.comment item with
  | Error _ -> None
  | Ok comment -> Some (Sift_crs.Comment.status comment)

let find_comment_cr ?status review ~path ~body =
  let rec loop index = function
    | [] -> None
    | item :: rest ->
        let status_matches =
          match status with
          | None -> true
          | Some status ->
              Option.equal Sift_crs.Status.equal (cr_status item) (Some status)
        in
        if
          String.equal (Sift_crs.Item.path item) path
          && Option.equal String.equal (cr_body item) (Some body)
          && status_matches
        then Some index
        else loop (index + 1) rest
  in
  loop 0 (Sift_review.cr_items review)

module Live_worktree = Sift_runner.Live_worktree

type select_after_reload =
  | Keep_cursor
  | Select_cr of {
      path : string;
      body : string;
      status : Sift_crs.Status.t option;
    }

type cr_reload = { load : Live_worktree.load; select : select_after_reload }
type cr_reload_error = Mutation_failed of string | Reload_failed of string

let select_cr ?status ~path ~body () = Select_cr { path; body; status }

type model = {
  config : config;
  repo : Sift_git.t;
  tui : Sift_tui.t;
  live : Live_worktree.t;
}

type msg =
  | Tui of Sift_tui.msg
  | Watch_tick of float
  | Watch_fingerprint_loaded of
      float * Live_worktree.request * (Sift_git.Fingerprint.t, string) result
  | Watch_input_loaded of
      Live_worktree.request * (Live_worktree.load, string) result
  | Cr_input_loaded of
      Live_worktree.request * (cr_reload, cr_reload_error) result

let set_tui_error tui message =
  fst (Sift_tui.update (Sift_tui.Report_error message) tui)

let persist_review model review =
  match save_review model.repo review with
  | Ok () -> model
  | Error message -> { model with tui = set_tui_error model.tui message }

let load_worktree_review config repo review =
  match
    Sift_git.load_worktree_stable ?title:config.title
      ?base:(worktree_base config review)
      repo ()
  with
  | Ok { input; fingerprint } -> Ok { Live_worktree.input; fingerprint }
  | Error error ->
      Error
        (Format.asprintf "review loading failed: %a" Sift_git.Error.pp error)

let load_worktree_command config repo review request =
  Mosaic.Cmd.perform (fun dispatch ->
      dispatch
        (Watch_input_loaded (request, load_worktree_review config repo review)))

let fingerprint_command config repo review now request =
  Mosaic.Cmd.perform (fun dispatch ->
      dispatch
        (Watch_fingerprint_loaded
           (now, request, worktree_fingerprint config repo review)))

let cr_reload_command config repo review request mutate =
  Mosaic.Cmd.perform (fun dispatch ->
      match mutate () with
      | Error message ->
          dispatch (Cr_input_loaded (request, Error (Mutation_failed message)))
      | Ok select -> (
          match load_worktree_review config repo review with
          | Error message ->
              dispatch
                (Cr_input_loaded (request, Error (Reload_failed message)))
          | Ok load -> dispatch (Cr_input_loaded (request, Ok { load; select }))
          ))

let replace_tui ?select tui review =
  let msg =
    match select with
    | None -> Sift_tui.Replace_review review
    | Some cursor -> Sift_tui.Replace_review_and_select (review, cursor)
  in
  fst (Sift_tui.update msg tui)

let select_cursor review = function
  | Keep_cursor -> None
  | Select_cr { path; body; status } ->
      Option.map
        (fun index -> Sift_review.Cursor.cr index)
        (find_comment_cr ?status review ~path ~body)

let apply_loaded_review ?select model review =
  let tui = replace_tui ?select model.tui review in
  (persist_review { model with tui } review, Mosaic.Cmd.none)

let command_of_live_load_action model now = function
  | Live_worktree.Load_fingerprint request ->
      Some
        (fingerprint_command model.config model.repo
           (Live_worktree.review model.live)
           now request)
  | Live_worktree.Load_worktree (request, _) ->
      Some
        (load_worktree_command model.config model.repo
           (Live_worktree.review model.live)
           request)
  | Live_worktree.Replace_review _ | Live_worktree.Report_error _ -> None

let apply_live_action now (model, commands) = function
  | (Live_worktree.Load_fingerprint _ | Live_worktree.Load_worktree _) as action
    -> (
      match command_of_live_load_action model now action with
      | None -> (model, commands)
      | Some command -> (model, command :: commands))
  | Live_worktree.Replace_review review ->
      ({ model with tui = replace_tui model.tui review }, commands)
  | Live_worktree.Report_error message ->
      ({ model with tui = set_tui_error model.tui message }, commands)

let apply_live_actions model now actions =
  let model, commands =
    List.fold_left (apply_live_action now) (model, []) actions
  in
  (model, Mosaic.Cmd.batch (List.rev commands))

let step_live ?(now = 0.) event model =
  let live, actions = Live_worktree.step event model.live in
  let model = { model with live } in
  apply_live_actions model now actions

let clean_worktree_at_tip repo tip =
  let base = Sift_feature.Revision.to_string tip in
  match Sift_git.load_worktree_stable ~base repo () with
  | Error error ->
      Error
        (Format.asprintf "cannot verify clean worktree: %a" Sift_git.Error.pp
           error)
  | Ok { input; _ } ->
      if Sift_diff.file_count (Sift_feature.diff input.feature) = 0 then Ok ()
      else
        Error
          "cannot write source CRs for an explicit review while the worktree \
           has tracked changes"

let source_mutation_allowed model =
  match Live_worktree.mode model.live with
  | Live_worktree.Worktree -> Ok ()
  | Live_worktree.Off -> (
      let review = Live_worktree.review model.live in
      let feature = Sift_review.feature review in
      let tip = Sift_feature.tip feature in
      if Sift_feature.Revision.equal tip (Sift_feature.Revision.v "WORKTREE")
      then Ok ()
      else
        match Sift_git.default_tip model.repo with
        | Error error ->
            Error
              (Format.asprintf "cannot verify review tip: %a" Sift_git.Error.pp
                 error)
        | Ok head when Sift_feature.Revision.equal head tip ->
            clean_worktree_at_tip model.repo tip
        | Ok _ ->
            Error
              "cannot write source CRs for an explicit review unless the \
               worktree is checked out at the reviewed tip")

let source_mutation_fingerprint model =
  match Live_worktree.mode model.live with
  | Live_worktree.Off -> Ok None
  | Live_worktree.Worktree ->
      Result.map Option.some
        (worktree_fingerprint model.config model.repo
           (Live_worktree.review model.live))

let source_mutation_started model fingerprint =
  match fingerprint with
  | None -> Live_worktree.source_mutation_started model.live
  | Some fingerprint ->
      Live_worktree.source_mutation_started ~fingerprint model.live

let source_mutation_event model mutate =
  match source_mutation_allowed model with
  | Error message ->
      ({ model with tui = set_tui_error model.tui message }, Mosaic.Cmd.none)
  | Ok () -> (
      match source_mutation_fingerprint model with
      | Error message ->
          ({ model with tui = set_tui_error model.tui message }, Mosaic.Cmd.none)
      | Ok fingerprint -> (
          match source_mutation_started model fingerprint with
          | Error message ->
              ( { model with tui = set_tui_error model.tui message },
                Mosaic.Cmd.none )
          | Ok (live, request) ->
              let command =
                cr_reload_command model.config model.repo
                  (Live_worktree.review live)
                  request mutate
              in
              ({ model with live }, command)))

let handle_tui_message model = function
  | Sift_tui.Review_changed review ->
      let model, command =
        step_live (Live_worktree.Review_changed review) model
      in
      (persist_review model review, command)
  | Comment_submitted comment ->
      source_mutation_event model (fun () ->
          Result.map
            (fun path -> select_cr ~path ~body:comment.body ())
            (add_comment model.repo comment))
  | Cr_removed cr ->
      source_mutation_event model (fun () ->
          Result.map (fun () -> Keep_cursor) (remove_cr model.repo cr))
  | Cr_edited (cr, body) ->
      source_mutation_event model (fun () ->
          Result.map
            (fun path -> select_cr ~path ~body ())
            (edit_cr model.repo cr body))
  | Cr_resolved cr ->
      let body = Option.value ~default:"" (cr_body cr.item) in
      source_mutation_event model (fun () ->
          Result.map
            (fun path -> select_cr ~path ~body ~status:Sift_crs.Status.XCR ())
            (resolve_cr model.repo cr))
  | msg ->
      let tui, command = Sift_tui.update msg model.tui in
      ({ model with tui }, Mosaic.Cmd.map (fun msg -> Tui msg) command)

let update_tui msg model =
  handle_tui_message model msg

let update msg model =
  match msg with
  | Tui msg -> update_tui msg model
  | Watch_tick now -> step_live ~now (Live_worktree.Tick now) model
  | Watch_fingerprint_loaded (now, request, result) ->
      step_live ~now
        (Live_worktree.Fingerprint_loaded (now, request, result))
        model
  | Watch_input_loaded (request, result) ->
      let model, command =
        step_live (Live_worktree.Worktree_loaded (request, result)) model
      in
      (persist_review model (Live_worktree.review model.live), command)
  | Cr_input_loaded (request, Error (Mutation_failed message)) ->
      let live, active =
        Live_worktree.source_mutation_aborted model.live request
      in
      if active then
        ( { model with live; tui = set_tui_error model.tui message },
          Mosaic.Cmd.none )
      else ({ model with live }, Mosaic.Cmd.none)
  | Cr_input_loaded (request, Error (Reload_failed message)) -> (
      let live, result =
        Live_worktree.source_mutation_loaded model.live request (Error message)
      in
      match result with
      | Ok None -> ({ model with live }, Mosaic.Cmd.none)
      | Ok (Some _) -> assert false
      | Error message ->
          ( { model with live; tui = set_tui_error model.tui message },
            Mosaic.Cmd.none ))
  | Cr_input_loaded (request, Ok { load; select }) -> (
      let live, result =
        Live_worktree.source_mutation_loaded model.live request (Ok load)
      in
      match result with
      | Error message ->
          ( { model with live; tui = set_tui_error model.tui message },
            Mosaic.Cmd.none )
      | Ok None -> ({ model with live }, Mosaic.Cmd.none)
      | Ok (Some review) ->
          let select = select_cursor review select in
          apply_loaded_review ?select { model with live } review)

let view model = Mosaic.map (fun msg -> Tui msg) (Sift_tui.view model.tui)

let subscriptions model =
  let tui =
    Mosaic.Sub.map (fun msg -> Tui msg) (Sift_tui.subscriptions model.tui)
  in
  match Live_worktree.mode model.live with
  | Live_worktree.Off -> tui
  | Live_worktree.Worktree ->
      Mosaic.Sub.batch
        [
          tui;
          Mosaic.Sub.every 0.5 (fun () -> Watch_tick (Unix.gettimeofday ()));
        ]

let app ~config ~repo ~live ~tui_config review =
  let init () =
    ( { config; repo; tui = Sift_tui.make ~config:tui_config review; live },
      Mosaic.Cmd.none )
  in
  { Mosaic.init; update; view; subscriptions }

let initial_live config review fingerprint =
  if should_watch config then
    match fingerprint with
    | Some fingerprint ->
        Ok
          (Live_worktree.make Live_worktree.Worktree ~review
             ~fingerprint:(Some fingerprint) ())
    | None -> Error "live worktree review loaded without a stable fingerprint"
  else Ok (Live_worktree.make Live_worktree.Off ~review ~fingerprint:None ())

let review_source repo ~review ~path =
  let feature = Sift_review.feature review in
  let tip = Sift_feature.tip feature in
  let result =
    if Sift_feature.Revision.equal tip (Sift_feature.Revision.v "WORKTREE") then
      Sift_git.worktree_source repo ~path
    else Sift_git.source repo ~tip ~path
  in
  match result with Ok source -> Some source | Error _ -> None

let run config =
  match discover config with
  | Error message -> exit_with_error message
  | Ok repo -> (
      match load_initial_review config repo with
      | Error message -> exit_with_error message
      | Ok { review; fingerprint } -> (
          match load_stored_review repo review with
          | Error message -> exit_with_error message
          | Ok review ->
              let tui_config =
                Sift_tui.Config.make ~workspace_label:(Sift_git.root repo)
                  ~source:(review_source repo) ()
              in
              let live =
                match initial_live config review fingerprint with
                | Ok live -> live
                | Error message -> exit_with_error message
              in
              Mosaic.run (app ~config ~repo ~live ~tui_config review)))

let () =
  try
    match parse Sys.argv with
    | Help ->
        print_usage stdout;
        exit 0
    | Run config -> run config
  with Cli_error message -> exit_with_usage message
