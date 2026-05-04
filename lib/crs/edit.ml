type anchor = Before_line of int | After_line of int | End_of_file
type t = { start_offset : int; stop_offset : int; replacement : string }

let start_offset t = t.start_offset
let stop_offset t = t.stop_offset
let replacement t = t.replacement
let render_comment comment = Format.asprintf "%a" Comment.pp comment

let render_line marker text =
  let len = String.length text in
  let buf = Buffer.create (len + 8) in
  let add_marker () =
    Buffer.add_string buf marker;
    Buffer.add_char buf ' '
  in
  add_marker ();
  for i = 0 to len - 1 do
    let c = text.[i] in
    Buffer.add_char buf c;
    if c = '\n' then add_marker ()
  done;
  Buffer.contents buf

let render syntax comment =
  let text = render_comment comment in
  match syntax with
  | Syntax.Ocaml_block -> "(* " ^ text ^ " *)"
  | Syntax.C_block -> "/* " ^ text ^ " */"
  | Syntax.Xml_block -> "<!-- " ^ text ^ " -->"
  | Syntax.C_line -> render_line "//" text
  | Syntax.Shell_line -> render_line "#" text
  | Syntax.Lisp_line -> render_line ";" text
  | Syntax.Sql_line -> render_line "--" text

let line_count source =
  let len = String.length source in
  if len = 0 then 0
  else
    let count = ref 1 in
    for i = 0 to len - 1 do
      if source.[i] = '\n' && i + 1 < len then incr count
    done;
    !count

let offset_before_line source line =
  if line < 1 then None
  else if line = 1 then Some 0
  else
    let len = String.length source in
    let current = ref 1 in
    let result = ref None in
    let i = ref 0 in
    while !result = None && !i < len do
      if source.[!i] = '\n' then (
        incr current;
        if !current = line then result := Some (!i + 1));
      incr i
    done;
    !result

let line_end_including_newline source line =
  match offset_before_line source line with
  | None -> None
  | Some start ->
      let len = String.length source in
      let rec loop i =
        if i >= len then len
        else if source.[i] = '\n' then i + 1
        else loop (i + 1)
      in
      Some (loop start)

let insert_text source offset text =
  let len = String.length source in
  let prefix_newline = offset > 0 && source.[offset - 1] <> '\n' in
  let suffix_newline = offset < len && not (String.equal text "") in
  let buf = Buffer.create (String.length text + 2) in
  if prefix_newline then Buffer.add_char buf '\n';
  Buffer.add_string buf text;
  if suffix_newline then Buffer.add_char buf '\n';
  Buffer.contents buf

let attach ~source ~syntax ~anchor comment =
  let text = render syntax comment in
  let lines = line_count source in
  let offset =
    match anchor with
    | Before_line line -> (
        if line < 1 || line > lines + 1 then
          Error
            (Error.make
               (Error.Invalid_anchor ("before line " ^ string_of_int line)))
        else if line = lines + 1 then Ok (String.length source)
        else
          match offset_before_line source line with
          | Some offset -> Ok offset
          | None ->
              Error
                (Error.make
                   (Error.Invalid_anchor ("before line " ^ string_of_int line)))
        )
    | After_line line -> (
        if line < 0 || line > lines then
          Error
            (Error.make
               (Error.Invalid_anchor ("after line " ^ string_of_int line)))
        else if line = 0 then Ok 0
        else
          match line_end_including_newline source line with
          | Some offset -> Ok offset
          | None ->
              Error
                (Error.make
                   (Error.Invalid_anchor ("after line " ^ string_of_int line))))
    | End_of_file -> Ok (String.length source)
  in
  match offset with
  | Error e -> Error e
  | Ok offset ->
      Ok
        {
          start_offset = offset;
          stop_offset = offset;
          replacement = insert_text source offset text;
        }

let replace item comment =
  match Item.comment item with
  | Error _ -> Error (Error.make Error.Stale_item)
  | Ok _ ->
      let span = Item.span item in
      Ok
        {
          start_offset = Span.start_offset span;
          stop_offset = Span.stop_offset span;
          replacement = render (Item.syntax item) comment;
        }

let remove item =
  let span = Item.span item in
  {
    start_offset = Span.start_offset span;
    stop_offset = Span.stop_offset span;
    replacement = "";
  }

let apply t ~source =
  let len = String.length source in
  if t.start_offset < 0 || t.stop_offset < t.start_offset || t.stop_offset > len
  then
    Error
      (Error.make (Error.Invalid_span "replacement range is outside source"))
  else
    Ok
      (String.sub source 0 t.start_offset
      ^ t.replacement
      ^ String.sub source t.stop_offset (len - t.stop_offset))
