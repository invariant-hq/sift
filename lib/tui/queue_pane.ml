open Mosaic

let default_width = 36
let focus_id = "sift.queue"

let title_style (theme : Theme.t) =
  Mosaic.Ansi.Style.make ~fg:theme.focus ~bold:true ()

let style_fg ~default (style : Mosaic.Ansi.Style.t) =
  Option.value ~default style.fg

let compact_text ?(limit = 28) text =
  let text = String.trim text in
  let len = String.length text in
  if limit <= 0 then ""
  else if len <= limit then text
  else if limit <= 3 then String.sub text 0 limit
  else String.sub text 0 (limit - 3) ^ "..."

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

let plural count singular plural =
  Printf.sprintf "%d %s" count (if count = 1 then singular else plural)

let string_of_approval approval =
  Format.asprintf "%a" Sift_review.Approval.pp approval

let string_of_handle handle = Format.asprintf "%a" Sift_crs.Handle.pp handle

let string_of_cr_priority priority =
  Format.asprintf "%a" Sift_crs.Priority.pp priority

let status_char = function
  | Sift_diff.File.Added -> "A"
  | Deleted -> "D"
  | Modified -> "M"
  | Renamed -> "Rn"
  | Copied -> "Cp"

let kind_slot kind =
  if String.length kind >= 2 then String.sub kind 0 2 else kind ^ " "

let state_char = function
  | None -> " "
  | Some Sift_review.Mark.Reviewed -> "R"
  | Some Unreviewed -> "!"

let state_slot mark = state_char mark

let hunk_range hunk =
  Printf.sprintf "-%d,%d +%d,%d" hunk.Sift_review.Scope.old_start hunk.old_count
    hunk.new_start hunk.new_count

let row_counts ~unreviewed_count ~cr_count =
  let review =
    if unreviewed_count = 0 then "done"
    else plural unreviewed_count "left" "left"
  in
  if cr_count = 0 then review else review ^ "  " ^ plural cr_count "CR" "CRs"

let queue_label ?(width = default_width) ?(indent = 0) ~state ~kind ~label
    ~meta () =
  let prefix = String.make indent ' ' in
  let label_width = max 8 (width - indent - String.length meta - 8) in
  let label = compact_path ~limit:label_width label in
  Printf.sprintf "%s%s %-2s %-*s  %s" prefix state (kind_slot kind)
    label_width label meta

let compact_queue_label ?(width = 32) ?(indent = 0) ~state ~kind ~label ?meta ()
    =
  let prefix = String.make indent ' ' in
  match meta with
  | None ->
      Printf.sprintf "%s%s %-2s %s" prefix state (kind_slot kind)
        (compact_path ~limit:(max 8 (width - indent - 5)) label)
  | Some meta ->
      let label_width = max 8 (width - indent - String.length meta - 8) in
      Printf.sprintf "%s%s %-2s %-*s  %s" prefix state (kind_slot kind)
        label_width
        (compact_path ~limit:label_width label)
        meta

let cr_summary item =
  match Sift_crs.Item.comment item with
  | Error error -> Format.asprintf "%a" Sift_crs.Error.pp error
  | Ok comment ->
      Format.asprintf "%a %s" Sift_crs.Comment.pp_header comment
        (compact_text ~limit:36 (Sift_crs.Comment.body comment))

let cr_badge comment =
  match Sift_crs.Comment.status comment with CR -> "CR" | XCR -> "XCR"

let cr_detail comment =
  let body = Sift_crs.Comment.body comment |> String.trim in
  let body = if String.equal body "" then "no body" else body in
  match Sift_crs.Comment.priority comment with
  | Now -> body
  | (Soon | Someday) as priority -> string_of_cr_priority priority ^ "  " ^ body

let cr_line item = Sift_crs.Span.start_line (Sift_crs.Item.span item)
let cr_anchor item = Printf.sprintf "line %d" (cr_line item)

let cr_queue_label ?(width = default_width) ?(indent = 2) ~item () =
  match Sift_crs.Item.comment item with
  | Error error ->
      let detail = Format.asprintf "%a" Sift_crs.Error.pp error in
      queue_label ~width ~indent ~state:"!" ~kind:"CR" ~label:(cr_anchor item)
        ~meta:(compact_text ~limit:26 detail)
        ()
  | Ok comment ->
      let reporter =
        compact_text ~limit:8
          (string_of_handle (Sift_crs.Comment.reporter comment))
      in
      let detail = compact_text ~limit:28 (cr_detail comment) in
      queue_label ~width ~indent ~state:" " ~kind:(cr_badge comment)
        ~label:(cr_anchor item)
        ~meta:(reporter ^ "  " ^ detail)
        ()

let compact_cr_queue_label ?(width = 32) ?(indent = 2) ~item () =
  let prefix = String.make indent ' ' in
  match Sift_crs.Item.comment item with
  | Error error ->
      let detail = Format.asprintf "%a" Sift_crs.Error.pp error in
      Printf.sprintf "%s!CR %s" prefix
        (compact_text ~limit:(max 8 (width - indent - 4)) detail)
  | Ok comment ->
      let reporter =
        compact_text ~limit:8
          (string_of_handle (Sift_crs.Comment.reporter comment))
      in
      let detail_width = max 8 (width - indent - String.length reporter - 6) in
      Printf.sprintf "%s%-3s %-8s %s" prefix (cr_badge comment)
        reporter
        (compact_text ~limit:detail_width (cr_detail comment))

let verdict_notice_label = function
  | Some notice when notice.Refresh_notice.verdict_reset -> Some "verdict reset"
  | Some notice when notice.stale_verdict -> Some "stale verdict"
  | Some _ | None -> None

let row_label ?refresh_notice ?(width = default_width) ?(compact = false) =
  function
  | Review_queue.Feature { mark; approval; remaining; _ } ->
      let progress =
        if remaining = 0 then "done" else plural remaining "left" "left"
      in
      let meta =
        match verdict_notice_label refresh_notice with
        | None -> progress ^ "  " ^ string_of_approval approval
        | Some verdict ->
            progress ^ "  " ^ string_of_approval approval ^ "  " ^ verdict
      in
      if compact then
        compact_queue_label ~width ~state:(state_slot mark) ~kind:"F"
          ~label:"feature" ~meta:progress ()
      else
        queue_label ~width ~state:(state_slot mark) ~kind:"F" ~label:"feature"
          ~meta ()
  | File { path; file; mark; cr_count; unreviewed_count; _ } ->
      let meta = row_counts ~unreviewed_count ~cr_count in
      if compact then
        compact_queue_label ~width ~state:(state_slot mark)
          ~kind:(status_char (Sift_diff.File.status file))
          ~label:path ~meta ()
      else
        queue_label ~width ~state:(state_slot mark)
          ~kind:(status_char (Sift_diff.File.status file))
          ~label:path ~meta
          ()
  | Hunk { hunk; mark; cr_count; unreviewed_count; _ } ->
      let label = hunk_range hunk in
      let meta = row_counts ~unreviewed_count ~cr_count in
      if compact then
        compact_queue_label ~width ~indent:2 ~state:(state_slot mark) ~kind:"H"
          ~label ~meta ()
      else
        queue_label ~width ~indent:2 ~state:(state_slot mark) ~kind:"H" ~label
          ~meta
          ()
  | Cr { item; nesting; _ } ->
      let indent =
        match nesting with Review_queue.File_level -> 2 | Hunk_level -> 4
      in
      if compact then compact_cr_queue_label ~width ~indent ~item ()
      else cr_queue_label ~width ~indent ~item ()

let row_description = function
  | Review_queue.Feature { remaining; _ } ->
      if remaining = 0 then Some "complete"
      else Some (plural remaining "unit left" "units left")
  | File _ | Hunk _ -> None
  | Cr { item; _ } -> Some (cr_summary item)

let select_colors theme =
  let selected_bg = theme.Theme.selection in
  let selected_fg =
    style_fg ~default:(Mosaic.Ansi.Color.of_rgb 244 250 252) theme.selected
  in
  let text_color = style_fg ~default:Mosaic.Ansi.Color.white theme.normal in
  let description_color =
    style_fg ~default:(Mosaic.Ansi.Color.grayscale ~level:14) theme.muted
  in
  (selected_bg, selected_fg, text_color, description_color)

let view ~theme ~rows ~selected_index ~refresh_notice ~width ~compact ~focused
    ~wrap_navigation ~on_key ~on_select ~on_activate =
  let selected_bg, selected_fg, text_color, description_color =
    select_colors theme
  in
  let selected_bg =
    if focused then selected_bg else Mosaic.Ansi.Color.of_rgba 74 104 120 72
  in
  let items =
    List.map
      (fun row ->
        {
          Mosaic.Select.label = row_label ?refresh_notice ~width ~compact row;
          description = row_description row;
        })
      rows
  in
  box ~flex_direction:Column ~background:theme.panel
    ~padding:(padding_lrtb 1 1 0 1)
    ~size:{ width = px width; height = pct 100 }
    ~flex_shrink:0.
    ~min_size:{ width = px 0; height = px 0 }
    [
      text ~style:(title_style theme) "outstanding";
      select
        ~id:focus_id ~autofocus:true
        ~selected_index:(Option.value ~default:0 selected_index)
        ~size:{ width = pct 100; height = pct 100 }
        ~min_size:{ width = px 0; height = px 0 }
        ~show_description:false ~show_scroll_indicator:true
        ~wrap_selection:wrap_navigation ~background:theme.panel
        ~focused_background:theme.panel ~selected_background:selected_bg
        ~selected_text_color:selected_fg ~text_color ~description_color
        ~on_change:(fun index -> Some (on_select index))
        ~on_activate:(fun index -> Some (on_activate index))
        ~on_key
        items;
    ]
