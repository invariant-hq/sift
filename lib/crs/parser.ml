let is_space = function ' ' | '\t' | '\n' | '\r' -> true | _ -> false

let skip_spaces s i =
  let len = String.length s in
  let rec loop i = if i < len && is_space s.[i] then loop (i + 1) else i in
  loop i

let has_prefix s i prefix =
  let len = String.length s in
  let plen = String.length prefix in
  i + plen <= len && String.equal (String.sub s i plen) prefix

let is_token_stop = function
  | ' ' | '\t' | '\n' | '\r' | ':' -> true
  | _ -> false

let read_token s i =
  let len = String.length s in
  let rec loop j =
    if j < len && not (is_token_stop s.[j]) then loop (j + 1) else j
  in
  let j = loop i in
  if j = i then None else Some (String.sub s i (j - i), j)

let trim = String.trim
let error kind = Error (Error.make kind)

let parse_header_prefix s ~colon =
  let ( let* ) = Result.bind in
  let len = String.length s in
  let i = skip_spaces s 0 in
  let status_text, i =
    if has_prefix s i "XCR" then ("XCR", i + 3)
    else if has_prefix s i "CR" then ("CR", i + 2)
    else ("", i)
  in
  match Status.of_string status_text with
  | None -> error (Error.Invalid_status status_text)
  | Some status -> (
      let* priority, i =
        if i < len && s.[i] = '-' then
          match read_token s (i + 1) with
          | None -> Error (Error.make (Error.Invalid_priority ""))
          | Some (suffix, j) -> (
              match Priority.of_suffix suffix with
              | None -> Error (Error.make (Error.Invalid_priority suffix))
              | Some priority -> Ok (priority, j))
        else Ok (Priority.Now, i)
      in
      if i >= len || not (is_space s.[i]) then
        error (Error.Invalid_header "expected whitespace before reporter")
      else
        let i = skip_spaces s i in
        match read_token s i with
        | None -> error (Error.Invalid_header "expected reporter")
        | Some (reporter_text, i) ->
            let* reporter = Handle.of_string reporter_text in
            let i_after_reporter = i in
            let i = skip_spaces s i in
            let* recipient, i =
              match read_token s i with
              | Some ("for", j) when j < len && is_space s.[j] -> (
                  let j = skip_spaces s j in
                  match read_token s j with
                  | None ->
                      Error
                        (Error.make (Error.Invalid_header "expected recipient"))
                  | Some (recipient_text, k) ->
                      let* recipient = Handle.of_string recipient_text in
                      Ok (Some recipient, k))
              | Some ("for", _) ->
                  Error (Error.make (Error.Invalid_header "expected recipient"))
              | Some _ -> Ok (None, i_after_reporter)
              | None -> Ok (None, i_after_reporter)
            in
            let i = skip_spaces s i in
            if colon then
              if i < len && s.[i] = ':' then
                Ok (Header.make ~status ~priority ~reporter ?recipient (), i + 1)
              else error (Error.Invalid_header "expected ':'")
            else if i = len then
              Ok (Header.make ~status ~priority ~reporter ?recipient (), i)
            else error (Error.Invalid_header "unexpected text after header"))

let header s =
  match parse_header_prefix s ~colon:false with
  | Ok (header, _) -> Ok header
  | Error e -> Error e

let comment s =
  match parse_header_prefix s ~colon:true with
  | Error e -> Error e
  | Ok (header, body_start) ->
      let body =
        String.sub s body_start (String.length s - body_start) |> trim
      in
      Ok (Comment.make ~header ~body)

let cr_like s =
  let len = String.length s in
  let i = skip_spaces s 0 in
  let next j = j >= len || is_space s.[j] || s.[j] = '-' || s.[j] = ':' in
  (has_prefix s i "CR" && next (i + 2)) || (has_prefix s i "XCR" && next (i + 3))

let position_of_offset s offset =
  let max = min offset (String.length s) in
  let line = ref 1 in
  let col = ref 0 in
  for i = 0 to max - 1 do
    if s.[i] = '\n' then (
      incr line;
      col := 0)
    else incr col
  done;
  (!line, !col)

let span_of_offsets source start_offset stop_offset =
  let start_line, start_col = position_of_offset source start_offset in
  let stop_line, stop_col = position_of_offset source stop_offset in
  Span.v ~start_offset ~stop_offset ~start_line ~start_col ~stop_line ~stop_col
    ()

let item_of_comment ~path ~syntax ~source ~raw_start ~raw_stop ~content =
  if cr_like content then
    let raw = String.sub source raw_start (raw_stop - raw_start) in
    let span = span_of_offsets source raw_start raw_stop in
    let result =
      match comment content with
      | Ok _ as ok -> ok
      | Error e -> Error (Error.with_span span e)
    in
    Some (Item.make ~path ~syntax ~span ~raw result)
  else None

let find_ocaml_block_end source body_start =
  let len = String.length source in
  let rec loop depth i =
    if i + 1 >= len then None
    else if source.[i] = '(' && source.[i + 1] = '*' then
      loop (depth + 1) (i + 2)
    else if source.[i] = '*' && source.[i + 1] = ')' then
      if depth = 1 then Some i else loop (depth - 1) (i + 2)
    else loop depth (i + 1)
  in
  loop 1 body_start

let find_sub source start needle =
  let len = String.length source in
  let nlen = String.length needle in
  let rec loop i =
    if i + nlen > len then None
    else if has_prefix source i needle then Some i
    else loop (i + 1)
  in
  loop start

let line_end source i =
  let len = String.length source in
  let rec loop i = if i < len && source.[i] <> '\n' then loop (i + 1) else i in
  loop i

let next_line_start source i =
  let len = String.length source in
  if i < len && source.[i] = '\n' then i + 1 else i

let line_start_of_offset source offset =
  let rec loop i =
    if i <= 0 then 0 else if source.[i - 1] = '\n' then i else loop (i - 1)
  in
  loop offset

let skip_double_quoted source start =
  let len = String.length source in
  let rec loop escaped i =
    if i >= len then len
    else if escaped then loop false (i + 1)
    else
      match source.[i] with
      | '\\' -> loop true (i + 1)
      | '"' -> i + 1
      | _ -> loop false (i + 1)
  in
  loop false (start + 1)

let line_marker_at source i =
  let len = String.length source in
  if i >= len then None
  else
    match source.[i] with
    | '/' when i + 1 < len && source.[i + 1] = '/' ->
        let j = ref (i + 2) in
        while !j < len && source.[!j] = '/' do
          incr j
        done;
        Some (Syntax.C_line, i, !j)
    | '#' ->
        let j = ref (i + 1) in
        while !j < len && source.[!j] = '#' do
          incr j
        done;
        Some (Syntax.Shell_line, i, !j)
    | ';' ->
        let j = ref (i + 1) in
        while !j < len && source.[!j] = ';' do
          incr j
        done;
        Some (Syntax.Lisp_line, i, !j)
    | '-' when i + 1 < len && source.[i + 1] = '-' ->
        let j = ref (i + 2) in
        while !j < len && source.[!j] = '-' do
          incr j
        done;
        Some (Syntax.Sql_line, i, !j)
    | _ -> None

let line_comment_at source line_start =
  line_marker_at source (skip_spaces source line_start)

let line_content source content_start line_stop =
  let content_start =
    if
      content_start < line_stop
      && (source.[content_start] = ' ' || source.[content_start] = '\t')
    then content_start + 1
    else content_start
  in
  String.sub source content_start (line_stop - content_start)

let same_line_syntax a b =
  match (a, b) with
  | Syntax.C_line, Syntax.C_line
  | Syntax.Shell_line, Syntax.Shell_line
  | Syntax.Lisp_line, Syntax.Lisp_line
  | Syntax.Sql_line, Syntax.Sql_line ->
      true
  | _ -> false

let collect_line_comment source syntax content_start first_line_stop =
  let len = String.length source in
  let buf = Buffer.create 64 in
  Buffer.add_string buf (line_content source content_start first_line_stop);
  let rec loop raw_stop next_start =
    if next_start >= len then raw_stop
    else
      match line_comment_at source next_start with
      | None -> raw_stop
      | Some (next_syntax, _, next_content_start)
        when same_line_syntax syntax next_syntax ->
          let stop = line_end source next_content_start in
          let content = line_content source next_content_start stop in
          if cr_like content then raw_stop
          else (
            Buffer.add_char buf '\n';
            Buffer.add_string buf content;
            loop stop (next_line_start source stop))
      | Some _ -> raw_stop
  in
  let raw_stop =
    loop first_line_stop (next_line_start source first_line_stop)
  in
  (raw_stop, Buffer.contents buf)

let source ~path s =
  let len = String.length s in
  let acc = ref [] in
  let push item = acc := item :: !acc in
  let rec scan i line_start =
    if i >= len then ()
    else if s.[i] = '"' then
      let next = skip_double_quoted s i in
      scan next (line_start_of_offset s next)
    else if i + 1 < len && s.[i] = '(' && s.[i + 1] = '*' then (
      match find_ocaml_block_end s (i + 2) with
      | None -> scan (i + 2) line_start
      | Some end_start ->
          let raw_stop = end_start + 2 in
          let content = String.sub s (i + 2) (end_start - i - 2) in
          (match
             item_of_comment ~path ~syntax:Syntax.Ocaml_block ~source:s
               ~raw_start:i ~raw_stop ~content
           with
          | None -> ()
          | Some item -> push item);
          scan raw_stop (line_start_of_offset s raw_stop))
    else if i + 1 < len && s.[i] = '/' && s.[i + 1] = '*' then (
      match find_sub s (i + 2) "*/" with
      | None -> scan (i + 2) line_start
      | Some end_start ->
          let raw_stop = end_start + 2 in
          let content = String.sub s (i + 2) (end_start - i - 2) in
          (match
             item_of_comment ~path ~syntax:Syntax.C_block ~source:s ~raw_start:i
               ~raw_stop ~content
           with
          | None -> ()
          | Some item -> push item);
          scan raw_stop (line_start_of_offset s raw_stop))
    else if i + 3 < len && has_prefix s i "<!--" then (
      match find_sub s (i + 4) "-->" with
      | None -> scan (i + 4) line_start
      | Some end_start ->
          let raw_stop = end_start + 3 in
          let content = String.sub s (i + 4) (end_start - i - 4) in
          (match
             item_of_comment ~path ~syntax:Syntax.Xml_block ~source:s
               ~raw_start:i ~raw_stop ~content
           with
          | None -> ()
          | Some item -> push item);
          scan raw_stop (line_start_of_offset s raw_stop))
    else
      match line_marker_at s i with
      | Some (syntax, raw_start, content_start) -> (
          let first_line_stop = line_end s content_start in
          let raw_stop, content =
            collect_line_comment s syntax content_start first_line_stop
          in
          match
            item_of_comment ~path ~syntax ~source:s ~raw_start ~raw_stop
              ~content
          with
          | None -> scan (i + 1) line_start
          | Some item ->
              push item;
              scan (next_line_start s raw_stop) (next_line_start s raw_stop))
      | None ->
          if i = line_start then (
            match line_comment_at s line_start with
            | None -> scan (i + 1) line_start
            | Some (syntax, raw_start, content_start) ->
                let first_line_stop = line_end s content_start in
                let raw_stop, content =
                  collect_line_comment s syntax content_start first_line_stop
                in
                (match
                   item_of_comment ~path ~syntax ~source:s ~raw_start ~raw_stop
                     ~content
                 with
                | None -> ()
                | Some item -> push item);
                scan (next_line_start s raw_stop) (next_line_start s raw_stop))
          else if s.[i] = '\n' then scan (i + 1) (i + 1)
          else scan (i + 1) line_start
  in
  scan 0 0;
  List.rev !acc
