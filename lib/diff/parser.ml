type git_meta = {
  mutable old_path : string option;
  mutable new_path : string option;
  mutable status : File.status option;
  mutable binary : bool;
}

exception Parse_error of Error.t

let error ?line msg =
  let err = Error.make (Invalid_unified_diff msg) in
  match line with None -> err | Some line -> Error.with_line line err

let raise_error ?line msg = raise_notrace (Parse_error (error ?line msg))

let starts_with ~prefix s =
  let prefix_len = String.length prefix in
  let len = String.length s in
  let rec loop i =
    i = prefix_len
    || Char.equal (String.unsafe_get s i) (String.unsafe_get prefix i)
       && loop (i + 1)
  in
  len >= prefix_len && loop 0

let drop_prefix ~prefix s =
  String.sub s (String.length prefix) (String.length s - String.length prefix)

let trim = String.trim

let strip_cr s =
  let len = String.length s in
  if len > 0 && Char.equal s.[len - 1] '\r' then String.sub s 0 (len - 1) else s

let split_lines s =
  let len = String.length s in
  let rec loop acc start i =
    if i = len then
      if start = len then List.rev acc
      else List.rev (strip_cr (String.sub s start (len - start)) :: acc)
    else if Char.equal s.[i] '\n' then
      let line = strip_cr (String.sub s start (i - start)) in
      loop (line :: acc) (i + 1) (i + 1)
    else loop acc start (i + 1)
  in
  loop [] 0 0

let unquote s =
  let len = String.length s in
  if len >= 2 && Char.equal s.[0] '"' && Char.equal s.[len - 1] '"' then
    String.sub s 1 (len - 2)
  else s

let normalize_path raw =
  let path = raw |> trim |> unquote in
  if String.equal path "/dev/null" then None
  else if starts_with ~prefix:"a/" path || starts_with ~prefix:"b/" path then
    Some (String.sub path 2 (String.length path - 2))
  else Some path

let header_path s =
  let s = trim s in
  let stop =
    match String.index_opt s '\t' with Some i -> i | None -> String.length s
  in
  String.sub s 0 stop

let tokenize s =
  let len = String.length s in
  let rec skip_spaces i =
    if i < len && Char.equal s.[i] ' ' then skip_spaces (i + 1) else i
  in
  let rec quoted buf i =
    if i >= len then (Buffer.contents buf, i)
    else
      match s.[i] with
      | '"' -> (Buffer.contents buf, i + 1)
      | '\\' when i + 1 < len ->
          Buffer.add_char buf s.[i + 1];
          quoted buf (i + 2)
      | c ->
          Buffer.add_char buf c;
          quoted buf (i + 1)
  in
  let rec bare start i =
    if i >= len || Char.equal s.[i] ' ' then (String.sub s start (i - start), i)
    else bare start (i + 1)
  in
  let rec loop acc i =
    let i = skip_spaces i in
    if i >= len then List.rev acc
    else
      let token, next =
        if Char.equal s.[i] '"' then quoted (Buffer.create 16) (i + 1)
        else bare i i
      in
      loop (token :: acc) next
  in
  loop [] 0

let parse_diff_git line =
  let rest = drop_prefix ~prefix:"diff --git " line in
  match tokenize rest with
  | old_path :: new_path :: _ ->
      (normalize_path old_path, normalize_path new_path)
  | _ -> (None, None)

let parse_int s =
  match int_of_string_opt s with
  | Some n -> Ok n
  | None -> Error "expected integer"

let parse_range prefix token =
  if String.length token < 2 || not (Char.equal token.[0] prefix) then
    Error "expected range"
  else
    let body = String.sub token 1 (String.length token - 1) in
    match String.index_opt body ',' with
    | None -> (
        match parse_int body with
        | Ok start -> Ok (start, 1)
        | Error msg -> Error msg)
    | Some comma -> (
        let start = String.sub body 0 comma in
        let count =
          String.sub body (comma + 1) (String.length body - comma - 1)
        in
        match (parse_int start, parse_int count) with
        | Ok start, Ok count -> Ok (start, count)
        | Error msg, _ | _, Error msg -> Error msg)

let parse_hunk_header line =
  if not (starts_with ~prefix:"@@ " line) then Error "expected hunk header"
  else
    let rec closing i =
      if i + 2 >= String.length line then None
      else if
        Char.equal line.[i] ' '
        && Char.equal line.[i + 1] '@'
        && Char.equal line.[i + 2] '@'
      then Some i
      else closing (i + 1)
    in
    match closing 3 with
    | None -> Error "unterminated hunk header"
    | Some stop -> (
        let spec = String.sub line 3 (stop - 3) |> trim in
        match tokenize spec with
        | old_range :: new_range :: _ -> (
            match (parse_range '-' old_range, parse_range '+' new_range) with
            | Ok (old_start, old_count), Ok (new_start, new_count) ->
                Ok (old_start, old_count, new_start, new_count)
            | Error msg, _ | _, Error msg -> Error msg)
        | _ -> Error "malformed hunk header")

let is_no_newline_marker line = String.equal line "\\ No newline at end of file"

let parse_hunk lines index =
  let line_no = index + 1 in
  match parse_hunk_header lines.(index) with
  | Error msg -> Error (error ~line:line_no msg)
  | Ok (old_start, old_count, new_start, new_count) ->
      let old_seen = ref 0 in
      let new_seen = ref 0 in
      let hunk_lines = ref [] in
      let i = ref (index + 1) in
      let done_counts () = !old_seen = old_count && !new_seen = new_count in
      while !i < Array.length lines && not (done_counts ()) do
        let line = lines.(!i) in
        if is_no_newline_marker line then incr i
        else if String.length line = 0 then
          raise_error ~line:(!i + 1) "empty line in hunk body"
        else
          let text = String.sub line 1 (String.length line - 1) in
          let diff_line =
            match line.[0] with
            | ' ' ->
                incr old_seen;
                incr new_seen;
                Some (Line.make Context ~text)
            | '+' ->
                incr new_seen;
                Some (Line.make Added ~text)
            | '-' ->
                incr old_seen;
                Some (Line.make Removed ~text)
            | _ -> None
          in
          match diff_line with
          | Some diff_line ->
              if !old_seen > old_count || !new_seen > new_count then
                raise_error ~line:(!i + 1) "too many lines in hunk body";
              hunk_lines := diff_line :: !hunk_lines;
              incr i
          | None -> raise_error ~line:(!i + 1) "invalid hunk body line"
      done;
      if not (done_counts ()) then Error (error ~line:line_no "truncated hunk")
      else (
        while !i < Array.length lines && is_no_newline_marker lines.(!i) do
          incr i
        done;
        match
          Hunk.make ~old_start ~old_count ~new_start ~new_count
            (List.rev !hunk_lines)
        with
        | Ok hunk -> Ok (hunk, !i)
        | Error hunk_error ->
            Error
              (Error.with_line line_no
                 (Error.make
                    (Invalid_unified_diff
                       (Format.asprintf "%a" Error.pp hunk_error)))))

let parse_hunk lines index =
  try parse_hunk lines index with Parse_error err -> Error err

let status_of_paths old_path new_path =
  match (old_path, new_path) with
  | None, Some _ -> File.Added
  | Some _, None -> Deleted
  | Some _, Some _ | None, None -> Modified

let make_file ?line meta hunks =
  let status =
    match meta.status with
    | Some status -> status
    | None -> status_of_paths meta.old_path meta.new_path
  in
  let content = if meta.binary then File.Binary else Text (List.rev hunks) in
  match
    File.make ?old_path:meta.old_path ?new_path:meta.new_path ~status content
  with
  | Ok file -> Ok file
  | Error file_error ->
      let err =
        Error.make
          (Invalid_unified_diff (Format.asprintf "%a" Error.pp file_error))
      in
      Error
        (match line with None -> err | Some line -> Error.with_line line err)

let parse_file_headers lines index meta =
  if index + 1 >= Array.length lines then
    Error (error ~line:(index + 1) "missing +++ header")
  else
    let old_line = lines.(index) in
    let new_line = lines.(index + 1) in
    if not (starts_with ~prefix:"--- " old_line) then
      Error (error ~line:(index + 1) "missing --- header")
    else if not (starts_with ~prefix:"+++ " new_line) then
      Error (error ~line:(index + 2) "missing +++ header")
    else (
      meta.old_path <-
        normalize_path (header_path (drop_prefix ~prefix:"--- " old_line));
      meta.new_path <-
        normalize_path (header_path (drop_prefix ~prefix:"+++ " new_line));
      Ok (index + 2))

let parse_git_file lines start =
  let old_path, new_path = parse_diff_git lines.(start) in
  let meta = { old_path; new_path; status = None; binary = false } in
  let hunks = ref [] in
  let i = ref (start + 1) in
  let text_started = ref false in
  let finished = ref false in
  while !i < Array.length lines && not !finished do
    let line = lines.(!i) in
    if starts_with ~prefix:"diff --git " line then finished := true
    else if starts_with ~prefix:"new file mode " line then (
      meta.old_path <- None;
      meta.status <- Some Added;
      incr i)
    else if starts_with ~prefix:"deleted file mode " line then (
      meta.new_path <- None;
      meta.status <- Some Deleted;
      incr i)
    else if starts_with ~prefix:"rename from " line then (
      meta.old_path <- normalize_path (drop_prefix ~prefix:"rename from " line);
      meta.status <- Some Renamed;
      incr i)
    else if starts_with ~prefix:"rename to " line then (
      meta.new_path <- normalize_path (drop_prefix ~prefix:"rename to " line);
      meta.status <- Some Renamed;
      incr i)
    else if starts_with ~prefix:"copy from " line then (
      meta.old_path <- normalize_path (drop_prefix ~prefix:"copy from " line);
      meta.status <- Some Copied;
      incr i)
    else if starts_with ~prefix:"copy to " line then (
      meta.new_path <- normalize_path (drop_prefix ~prefix:"copy to " line);
      meta.status <- Some Copied;
      incr i)
    else if
      starts_with ~prefix:"Binary files " line
      || String.equal line "GIT binary patch"
    then (
      meta.binary <- true;
      incr i)
    else if starts_with ~prefix:"--- " line then (
      match parse_file_headers lines !i meta with
      | Error err -> raise_notrace (Parse_error err)
      | Ok next ->
          text_started := true;
          i := next)
    else if starts_with ~prefix:"@@ " line then (
      match parse_hunk lines !i with
      | Error err -> raise_notrace (Parse_error err)
      | Ok (hunk, next) ->
          hunks := hunk :: !hunks;
          i := next)
    else if String.equal line "" then incr i
    else if !text_started && not meta.binary then
      raise_error ~line:(!i + 1) "unexpected line in unified diff"
    else incr i
  done;
  match make_file ~line:(start + 1) meta !hunks with
  | Ok file -> Ok (file, !i)
  | Error err -> Error err

let parse_plain_file lines start =
  let meta =
    { old_path = None; new_path = None; status = None; binary = false }
  in
  match parse_file_headers lines start meta with
  | Error err -> Error err
  | Ok next ->
      let hunks = ref [] in
      let i = ref next in
      let finished = ref false in
      while !i < Array.length lines && not !finished do
        let line = lines.(!i) in
        if starts_with ~prefix:"diff --git " line then finished := true
        else if starts_with ~prefix:"--- " line then finished := true
        else if starts_with ~prefix:"@@ " line then (
          match parse_hunk lines !i with
          | Error err -> raise_notrace (Parse_error err)
          | Ok (hunk, next) ->
              hunks := hunk :: !hunks;
              i := next)
        else if String.equal line "" then incr i
        else raise_error ~line:(!i + 1) "unexpected line in unified diff"
      done;
      make_file ~line:(start + 1) meta !hunks
      |> Result.map (fun file -> (file, !i))

let unified s =
  let lines = Array.of_list (split_lines s) in
  let files = ref [] in
  let i = ref 0 in
  let parse_current () =
    let line = lines.(!i) in
    if starts_with ~prefix:"diff --git " line then parse_git_file lines !i
    else if starts_with ~prefix:"--- " line then parse_plain_file lines !i
    else Error (error ~line:(!i + 1) "expected file header")
  in
  try
    while !i < Array.length lines do
      if String.equal lines.(!i) "" then incr i
      else
        match parse_current () with
        | Error err -> raise_notrace (Parse_error err)
        | Ok (file, next) ->
            files := file :: !files;
            i := next
    done;
    Ok (Diff.make (List.rev !files))
  with Parse_error err -> Error err

let file_unified s =
  match unified s with
  | Error err -> Error err
  | Ok diff -> (
      match Diff.files diff with
      | [ file ] -> Ok file
      | [] -> Error (error "expected one file diff, found none")
      | _ :: _ :: _ -> Error (error "expected one file diff, found multiple"))
