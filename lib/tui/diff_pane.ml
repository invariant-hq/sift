open Mosaic

let focus_id = "sift.diff"

type msg =
  | Activate
  | Select_source of Mosaic.Diff.source_line
  | Move_line of Sift_review.Cursor.move

type t = { selected : Mosaic.Diff.source_line option }


let make () = { selected = None }
let activate = Activate

let title_style (theme : Theme.t) =
  Mosaic.Ansi.Style.make ~fg:theme.focus ~bold:true ()

let compact_path ?(limit = 28) path =
  let len = String.length path in
  if limit <= 0 then ""
  else if len <= limit then path
  else if limit <= 3 then String.sub path 0 limit
  else
    let basename =
      match String.rindex_opt path '/' with
      | None -> path
      | Some index -> String.sub path (index + 1) (len - index - 1)
    in
    let base_len = String.length basename in
    if base_len + 4 >= limit then
      let tail_len = min base_len (limit - 3) in
      "..." ^ String.sub basename (base_len - tail_len) tail_len
    else
      let prefix_len = limit - base_len - 4 in
      let prefix = String.sub path 0 prefix_len in
      let prefix =
        if String.ends_with ~suffix:"/" prefix then
          String.sub prefix 0 (String.length prefix - 1)
        else prefix
      in
      prefix ^ "/..." ^ basename

let list_find_index predicate list =
  let rec loop index = function
    | [] -> None
    | value :: rest ->
        if predicate value then Some index else loop (index + 1) rest
  in
  loop 0 list

let handled_key key msg =
  Mosaic.Event.Key.prevent_default key;
  Some msg

let key_message key =
  if Shortcut.matches Shortcut.up key || Shortcut.matches (Shortcut.char 'k') key
  then handled_key key (Move_line Previous)
  else if Shortcut.matches Shortcut.down key || Shortcut.matches (Shortcut.char 'j') key
  then handled_key key (Move_line Next)
  else if Shortcut.matches (Shortcut.char 'g') key then
    handled_key key (Move_line First)
  else if Shortcut.matches (Shortcut.char ~shift:true 'g') key then
    handled_key key (Move_line Last)
  else None


let mouse_message event =
  match Mosaic.Event.Mouse.kind event with
  | Down { button = Left } -> Some Activate
  | Down _ | Up _ | Move | Drag _ | Drag_end _ | Drop _ | Over _ | Out

  | Scroll _ ->
      None

let diff_side = function Sift_review.Scope.Old -> Mosaic.Diff.Old | New -> New

let selected_line_color () : Mosaic.Line_number.line_color =
  let color = Mosaic.Ansi.Color.of_rgba 74 104 120 96 in
  { gutter = color; content = Some color }

let line_highlight ~color ~side ~first ~last =
  if first > last then None else Some { Mosaic.Diff.side; first; last; color }

let range_highlight ~color ~side ~start ~count =
  line_highlight ~color ~side ~first:start ~last:(start + count - 1)

let line_highlights ?selected target =
  let color = selected_line_color () in
  match selected with
  | Some (source : Mosaic.Diff.source_line) ->
      [
        {
          Mosaic.Diff.side = source.side;
          first = source.line;
          last = source.line;
          color;
        };
      ]
  | None -> (
      match Diff_target.scope target with
  | Some scope -> (
      match Sift_review.Scope.view scope with
      | Feature | File _ -> []
      | Hunk hunk ->
          [
            range_highlight ~color ~side:Mosaic.Diff.Old ~start:hunk.old_start
              ~count:hunk.old_count;
            range_highlight ~color ~side:Mosaic.Diff.New ~start:hunk.new_start
              ~count:hunk.new_count;
          ]
          |> List.filter_map Fun.id
      | Line (side, _, line) ->
          [
            {
              Mosaic.Diff.side = diff_side side;
              first = line;
              last = line;
              color;
            };
          ])
  | None -> (
      match Diff_target.line target with
      | None -> []
      | Some line ->
          [
            {
              Mosaic.Diff.side = diff_side line.side;
              first = line.number;
              last = line.number;
              color;
            };
          ]))

let string_of_diff_side = function Mosaic.Diff.Old -> "old" | New -> "new"

let string_of_diff_layout = function
  | Mosaic.Diff.Unified -> "unified"
  | Split -> "split"

let source_of_line (line : Review_context.line) : Mosaic.Diff.source_line =
  { side = diff_side line.side; line = line.number }

let scope_of_source ~path (source : Mosaic.Diff.source_line) =
  match source.side with
  | Mosaic.Diff.Old -> Sift_review.Scope.old_line ~path ~line:source.line
  | Mosaic.Diff.New -> Sift_review.Scope.new_line ~path ~line:source.line

let source_of_hunk (hunk : Sift_review.Scope.hunk) :
    Mosaic.Diff.source_line option =
  if hunk.new_count > 0 then
    Some { side = Mosaic.Diff.New; line = hunk.new_start }
  else if hunk.old_count > 0 then
    Some { side = Mosaic.Diff.Old; line = hunk.old_start }
  else None

let source_line target =
  match Diff_target.scope target with
  | Some scope -> (
      match Sift_review.Scope.view scope with
      | Feature | File _ -> None
      | Hunk hunk -> source_of_hunk hunk
      | Line (side, _, line) -> Some { side = diff_side side; line })
  | None -> Option.map source_of_line (Diff_target.line target)

let scope_of_target_source target source =
  match Diff_target.file target with
  | None -> None
  | Some file -> Some (scope_of_source ~path:(Sift_diff.File.path file) source)

let patch_sources patch =
  let sources = ref [] in
  List.iter
    (fun (hunk : Mosaic.Diff.Patch.hunk) ->
      let old_line = ref hunk.old_start in
      let new_line = ref hunk.new_start in
      List.iter
        (fun (line : Mosaic.Diff.Patch.line) ->
          (match line.tag with
          | Added ->
              sources := { Mosaic.Diff.side = New; line = !new_line } :: !sources;
              incr new_line
          | Removed ->
              sources := { Mosaic.Diff.side = Old; line = !old_line } :: !sources;
              incr old_line
          | Context ->
              sources := { Mosaic.Diff.side = New; line = !new_line } :: !sources;
              incr old_line;
              incr new_line))
        hunk.lines)
    (Mosaic.Diff.Patch.hunks patch);
  List.rev !sources

let source_equal (a : Mosaic.Diff.source_line) (b : Mosaic.Diff.source_line) =
  a.side = b.side && a.line = b.line

let source_index source sources =
  list_find_index (source_equal source) sources

let source_context_line_count context =
  if String.equal context.Diff_target.text "" then 0
  else List.length (String.split_on_char '\n' context.text)

let source_in_range source ~first_line ~line_count =
  source.Mosaic.Diff.side = New && source.line >= first_line
  && source.line < first_line + line_count

let selected_source t target =
  let selected =
    match t.selected with
    | None -> None
    | Some source -> (
        match Diff_target.content target with
        | Patch (_, patch) ->
            if List.exists (source_equal source) (patch_sources patch) then
              Some source
            else None
        | Source_context context ->
            if
              source_in_range source ~first_line:context.first_line
                ~line_count:(source_context_line_count context)
            then Some source
            else None
        | Source_unavailable (_, line) ->
            if source.side = New && source.line = line.number then Some source
            else None
        | No_file | Binary _ | Empty _ -> None)
  in
  match selected with Some _ as selected -> selected | None -> source_line target

let current_or_first_source t target sources =
  match selected_source t target with
  | Some source when List.exists (source_equal source) sources -> Some source
  | Some _ | None -> List.nth_opt sources 0

let target_or_first_source target sources =
  match source_line target with
  | Some source when List.exists (source_equal source) sources -> Some source
  | Some _ | None -> List.nth_opt sources 0

let initial_source target =
  match Diff_target.content target with
  | Patch (_, patch) ->
      let sources = patch_sources patch in
      target_or_first_source target sources
  | Source_context context ->
      Some { Mosaic.Diff.side = New; line = context.anchor_line }
  | Source_unavailable (file, line) ->
      ignore (file : Sift_diff.File.t);
      Some { Mosaic.Diff.side = New; line = line.number }
  | No_file | Binary _ | Empty _ -> None

let move_source_index length current move =
  if length <= 0 then None
  else
    let last = length - 1 in
    let current = max 0 (min last current) in
    match move with
    | Sift_review.Cursor.First -> Some 0
    | Last -> Some last
    | Previous -> Some (max 0 (current - 1))
    | Next -> Some (min last (current + 1))

let move_patch_line t target patch move =
  let sources = patch_sources patch in
  match current_or_first_source t target sources with
  | None -> None
  | Some source ->
      let current = Option.value ~default:0 (source_index source sources) in
      Option.bind
        (move_source_index (List.length sources) current move)
        (List.nth_opt sources)

let move_source_context_line context move =
  let count = source_context_line_count context in
  let current = context.anchor_line - context.first_line in
  match move_source_index count current move with
  | None -> None
  | Some index -> Some { Mosaic.Diff.side = New; line = context.first_line + index }

let move_line t target move =
  match Diff_target.content target with
  | Patch (_, patch) -> move_patch_line t target patch move
  | Source_context context ->
      let context =
        match t.selected with
        | Some selected -> { context with anchor_line = selected.line }
        | None -> context
      in
      move_source_context_line context move
  | Source_unavailable (file, line) ->
      ignore (file : Sift_diff.File.t);
      Some { Mosaic.Diff.side = New; line = line.number }
  | No_file | Binary _ | Empty _ -> None

let update ~target msg t =
  match msg with
  | Activate -> ({ selected = initial_source target }, Cmd.none)
  | Select_source selected -> ({ selected = Some selected }, Cmd.none)
  | Move_line move -> (
      match move_line t target move with
      | None -> (t, Cmd.none)
      | Some selected -> ({ selected = Some selected }, Cmd.none))

let selected_scope t ~target =
  Option.bind (selected_source t target) (scope_of_target_source target)

let reveal ~layout target patch =
  match source_line target with
  | None -> None
  | Some source -> (
      match Mosaic.Diff.source_line_row patch ~layout source with
      | None -> None
      | Some row ->
          let path =
            match Diff_target.file target with
            | None -> ""
            | Some file -> Sift_diff.File.path file
          in
          let key =
            Printf.sprintf "diff:%s:%s:%s:%d:%d" path
              (string_of_diff_layout layout)
              (string_of_diff_side source.side)
              source.line row
          in
          Some
            {
              Mosaic.Scroll_box.key;
              x = None;
              y = Some row;
              align_x = `Nearest;
              align_y = `Nearest;
              margin = 3;
            })

let extension path =
  match String.rindex_opt path '.' with
  | None -> ""
  | Some index ->
      String.lowercase_ascii
        (String.sub path index (String.length path - index))

let ocaml_highlighter =
  lazy
    (Mosaic.Code.Highlighter.sync (fun request ->
         ignore (request.language : string);
         Mosaic.Syntax_highlight.of_triples
           (Tree_sitter_ocaml.highlight_ocaml request.content)))

let ocaml_interface_highlighter =
  lazy
    (Mosaic.Code.Highlighter.sync (fun request ->
         ignore (request.language : string);
         Mosaic.Syntax_highlight.of_triples
           (Tree_sitter_ocaml.highlight_interface request.content)))

let diff_syntax ~language highlighter =
  Mosaic.Diff.syntax ~language ~streaming:true highlighter

let code_syntax ~language highlighter =
  Mosaic.Code.with_highlighter ~language ~streaming:true highlighter

let highlight_for_file file =
  match extension (Sift_diff.File.path file) with
  | ".ml" ->
      let syntax =
        diff_syntax ~language:"ocaml" (Lazy.force ocaml_highlighter)
      in
      Some { Mosaic.Diff.old = syntax; new_ = syntax }
  | ".mli" ->
      let syntax =
        diff_syntax ~language:"ocaml-interface"
          (Lazy.force ocaml_interface_highlighter)
      in
      Some { Mosaic.Diff.old = syntax; new_ = syntax }
  | _ -> None

let source_highlight_for_file file =
  match extension (Sift_diff.File.path file) with
  | ".ml" -> Some (code_syntax ~language:"ocaml" (Lazy.force ocaml_highlighter))
  | ".mli" ->
      Some
        (code_syntax ~language:"ocaml-interface"
           (Lazy.force ocaml_interface_highlighter))
  | _ -> None

let empty_state theme title body =
  box ~flex_direction:Column ~padding:(padding_xy 2 1)
    ~size:{ width = pct 100; height = pct 100 }
    [
      text ~style:(title_style theme) title;
      text ~style:theme.Theme.muted ~wrap:`Word body;
    ]

let source_reveal ?selected (context : Diff_target.source_context) =
  let anchor_line =
    match selected with
    | Some { Mosaic.Diff.side = New; line } -> line
    | Some { side = Old; _ } | None -> context.anchor_line
  in
  let row = anchor_line - context.first_line in
  let path = Sift_diff.File.path context.file in
  let key =
    Printf.sprintf "source:%s:%d:%d" path context.first_line anchor_line
  in
  {
    Mosaic.Scroll_box.key;
    x = None;
    y = Some row;
    align_x = `Nearest;
    align_y = `Nearest;
    margin = 3;
  }

let source_line_colors ?selected (context : Diff_target.source_context) =
  let anchor_line =
    match selected with
    | Some { Mosaic.Diff.side = New; line } -> line
    | Some { side = Old; _ } | None -> context.anchor_line
  in
  let row = anchor_line - context.first_line in
  if row < 0 then [] else [ (row, selected_line_color ()) ]

let source_context ~theme ~show_line_numbers ~wrap ?selected
    (context : Diff_target.source_context) =
  let reveal = source_reveal ?selected context in
  let syntax = source_highlight_for_file context.file in
  let line_colors = source_line_colors ?selected context in
  scroll_box ~id:focus_id ~scroll_y:true ~scroll_x:false ~reveal
    ~on_key:key_message ~on_mouse:mouse_message
    ~size:{ width = pct 100; height = pct 100 }
    ~background:theme.Theme.background
    [
      line_number ~show_line_numbers
        ~line_number_offset:(context.first_line - 1) ~line_colors
        (code ?syntax ~text_style:theme.normal ~wrap context.text);
    ]

let content ~theme ~target ~layout ~show_line_numbers ~wrap ?selected () =
  match Diff_target.content target with
  | No_file ->
      empty_state theme "No file selected"
        "Choose a file from the review queue."
  | Binary _ ->
      empty_state theme "Binary file" "This change cannot be rendered as text."
  | Empty _ ->
      empty_state theme "No text changes"
        "The selected scope has no renderable diff rows."
  | Source_unavailable (_, line) ->
      empty_state theme "Source unavailable"
        (Printf.sprintf
           "The selected line %d is outside the compact diff, but its source \
            text could not be loaded."
           line.number)
  | Source_context context ->
      source_context ~theme ~show_line_numbers ~wrap ?selected context
  | Patch (file, patch) ->
      let reveal =
        match selected with
        | None -> reveal ~layout target patch
        | Some source -> (
            match Mosaic.Diff.source_line_row patch ~layout source with
            | None -> reveal ~layout target patch
            | Some row ->
                let path = Sift_diff.File.path file in
                let key =
                  Printf.sprintf "diff:%s:%s:%s:%d:%d" path
                    (string_of_diff_layout layout)
                    (string_of_diff_side source.side)
                    source.line row
                in
                Some
                  {
                    Mosaic.Scroll_box.key;
                    x = None;
                    y = Some row;
                    align_x = `Nearest;
                    align_y = `Nearest;
                    margin = 3;
                  })
      in
      let on_line_click (hit : Mosaic.Diff.line_hit) =
        Option.map (fun source -> Select_source source) hit.source
      in
      let highlight =
        Option.bind (Diff_target.file target) highlight_for_file
      in
      scroll_box ~id:focus_id ~scroll_y:true ~scroll_x:false ?reveal
        ~on_key:key_message ~on_mouse:mouse_message
        ~size:{ width = pct 100; height = pct 100 }
        ~background:theme.background
        [
          diff ~layout ~theme:theme.diff ?highlight
            ~line_highlights:(line_highlights ?selected target)
            ~show_line_numbers ~wrap ~text_style:theme.normal ~on_line_click
            patch;
        ]

let title target =
  match Diff_target.file target with
  | None -> "diff"
  | Some file -> Sift_diff.File.path file

let viewer_label target layout =
  match Diff_target.content target with
  | Source_unavailable _ | Source_context _ -> "context"
  | No_file | Binary _ | Empty _ | Patch _ -> string_of_diff_layout layout

let review_scope ?selected target =
  match selected with
  | Some source -> scope_of_target_source target source
  | None -> (
      match Diff_target.scope target with
      | Some _ as scope -> scope
      | None -> (
          match (Diff_target.file target, Diff_target.line target) with
          | Some file, Some line ->
              let path = Sift_diff.File.path file in
              Some
                (match line.side with
                | Sift_review.Scope.Old ->
                    Sift_review.Scope.old_line ~path ~line:line.number
                | New -> Sift_review.Scope.new_line ~path ~line:line.number)
          | _ -> None))

let review_badge ~theme ~review ?selected target =
  match review_scope ?selected target with
  | None -> None
  | Some scope ->
      if Sift_review.is_reviewed review scope then
        Some (theme.Theme.reviewed, "R reviewed")
      else Some (theme.unreviewed, "! unreviewed")

let view t ~theme ~review ~target ~layout ~show_line_numbers ~wrap ~focused =
  let selected = if focused then selected_source t target else None in
  let title_style =
    if focused then title_style theme
    else Mosaic.Ansi.Style.make ~fg:(Option.value ~default:Mosaic.Ansi.Color.white theme.muted.fg) ()
  in
  let badge = review_badge ~theme ~review ?selected target in
  box ~flex_direction:Column ~padding:(padding_xy 1 0) ~flex_grow:2.
    ~background:theme.Theme.background
    ~min_size:{ width = px 0; height = px 0 }
    [
      box ~flex_direction:Row ~justify_content:Space_between
        ~size:{ width = pct 100; height = px 1 }
        ([
           text ~style:title_style ~truncate:true ~flex_grow:1.
             ~min_size:{ width = px 0; height = px 0 }
             (compact_path ~limit:60 (title target));
         ]
        @ (match badge with
          | None -> []
          | Some (style, label) ->
              [
                text ~style ~truncate:true ~flex_shrink:0.
                  ~size:{ width = px (String.length label + 1); height = px 1 }
                  label;
              ])
        @ [
            text ~style:theme.muted ~truncate:true ~flex_shrink:0.
              ~size:{ width = px 8; height = px 1 }
              (viewer_label target layout);
          ]);
      content ~theme ~target ~layout ~show_line_numbers ~wrap ?selected ();
    ]
