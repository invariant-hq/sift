type source_context = {
  file : Sift_diff.File.t;
  text : string;
  first_line : int;
  anchor_line : int;
}

type content =
  | No_file
  | Binary of Sift_diff.File.t
  | Empty of Sift_diff.File.t
  | Source_unavailable of Sift_diff.File.t * Review_context.line
  | Source_context of source_context
  | Patch of Sift_diff.File.t * Mosaic.Diff.Patch.t

type t = {
  context : Review_context.t;
  file : Sift_diff.File.t option;
  scope : Sift_review.Scope.t option;
  line : Review_context.line option;
  content : content;
}

let patch_line line =
  let tag =
    match Sift_diff.Line.kind line with
    | Context -> Mosaic.Diff.Patch.Context
    | Added -> Added
    | Removed -> Removed
  in
  { Mosaic.Diff.Patch.tag; content = Sift_diff.Line.text line }

let patch_hunk hunk =
  {
    Mosaic.Diff.Patch.old_start = Sift_diff.Hunk.old_start hunk;
    old_lines = Sift_diff.Hunk.old_count hunk;
    new_start = Sift_diff.Hunk.new_start hunk;
    new_lines = Sift_diff.Hunk.new_count hunk;
    lines = List.map patch_line (Sift_diff.Hunk.lines hunk);
  }

let patch_file file =
  match Sift_diff.File.content file with
  | Binary -> Binary file
  | Text hunks ->
      let patch = Mosaic.Diff.Patch.make (List.map patch_hunk hunks) in
      if Mosaic.Diff.Patch.is_empty patch then Empty file
      else Patch (file, patch)

let line_in_range line ~start ~count =
  count > 0 && line >= start && line < start + count

let line_in_hunk (line : Review_context.line) hunk =
  match line.side with
  | Old ->
      line_in_range line.number
        ~start:(Sift_diff.Hunk.old_start hunk)
        ~count:(Sift_diff.Hunk.old_count hunk)
  | New ->
      line_in_range line.number
        ~start:(Sift_diff.Hunk.new_start hunk)
        ~count:(Sift_diff.Hunk.new_count hunk)

let line_in_file line file =
  match Sift_diff.File.content file with
  | Binary -> false
  | Text hunks -> List.exists (line_in_hunk line) hunks

let split_source source =
  let lines = String.split_on_char '\n' source in
  match List.rev lines with "" :: rest -> List.rev rest | _ -> lines

let slice_lines lines ~first ~last =
  let buffer = Buffer.create 256 in
  let line_number = ref 1 in
  List.iter
    (fun line ->
      if !line_number >= first && !line_number <= last then begin
        if Buffer.length buffer > 0 then Buffer.add_char buffer '\n';
        Buffer.add_string buffer line
      end;
      incr line_number)
    lines;
  Buffer.contents buffer

let source_context file (line : Review_context.line) source =
  let lines = split_source source in
  let line_count = List.length lines in
  if line.number < 1 || line.number > line_count then None
  else
    let margin = 8 in
    let first_line = max 1 (line.number - margin) in
    let last_line = min line_count (line.number + margin) in
    Some
      {
        file;
        text = slice_lines lines ~first:first_line ~last:last_line;
        first_line;
        anchor_line = line.number;
      }

let source_content ~source file (line : Review_context.line) =
  let path = Sift_diff.File.path file in
  match source ~path with
  | None -> Source_unavailable (file, line)
  | Some text -> (
      match source_context file line text with
      | None -> Source_unavailable (file, line)
      | Some context -> Source_context context)

let needs_source_context context file (line : Review_context.line) =
  Option.is_some (Review_context.cr context)
  && Sift_review.Scope.equal_side line.side Sift_review.Scope.New
  && not (line_in_file line file)

let file_content ~source context file =
  match Review_context.line context with
  | Some line when needs_source_context context file line ->
      source_content ~source file line
  | Some _ | None -> patch_file file

let no_source ~path:_ = None

let v ?(source = no_source) context =
  let file = Review_context.file context in
  let scope = Review_context.scope context in
  let line = Review_context.line context in
  let content =
    match file with
    | None -> No_file
    | Some file -> file_content ~source context file
  in
  { context; file; scope; line; content }

let context t = t.context
let file t = t.file
let scope t = t.scope
let line t = t.line
let content t = t.content

let patch t =
  match t.content with
  | No_file | Binary _ | Empty _ | Source_unavailable _ | Source_context _ ->
      None
  | Patch (_, patch) -> Some patch
