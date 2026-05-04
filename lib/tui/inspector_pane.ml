open Mosaic

type target =
  | Feature of Sift_feature.t
  | File of Sift_diff.File.t
  | Hunk of Sift_review.Scope.hunk
  | Line of
      Sift_review.Scope.side * Sift_review.Scope.path * Sift_review.Scope.line
  | Cr of int * Sift_crs.Item.t

let default_width = 44

let title_style (theme : Theme.t) =
  Mosaic.Ansi.Style.make ~fg:theme.focus ~bold:true ()

let string_of_approval approval =
  Format.asprintf "%a" Sift_review.Approval.pp approval

let string_of_handle handle = Format.asprintf "%a" Sift_crs.Handle.pp handle
let string_of_cr_status status = Format.asprintf "%a" Sift_crs.Status.pp status

let string_of_cr_priority priority =
  Format.asprintf "%a" Sift_crs.Priority.pp priority

let status_char = function
  | Sift_diff.File.Added -> "A"
  | Deleted -> "D"
  | Modified -> "M"
  | Renamed -> "Rn"
  | Copied -> "Cp"

let feature_identity feature =
  match Sift_feature.title feature with
  | Some title -> title
  | None -> (
      let tip = Sift_feature.Revision.to_string (Sift_feature.tip feature) in
      match tip with "WORKTREE" -> "worktree" | _ -> "feature")

let revision_range feature =
  let compact_revision revision =
    let text = Sift_feature.Revision.to_string revision in
    if String.length text <= 12 then text else String.sub text 0 10
  in
  compact_revision (Sift_feature.base feature)
  ^ ".."
  ^ compact_revision (Sift_feature.tip feature)

let section theme title children =
  box ~flex_direction:Column ~gap:(gap 0)
    ~size:{ width = pct 100; height = auto }
    (text ~style:(title_style theme) title :: children)

let field theme label value =
  box ~flex_direction:Row ~justify_content:Space_between
    ~size:{ width = pct 100; height = auto }
    [ text ~style:theme.Theme.muted label; text ~style:theme.normal value ]

let field_styled theme label style value =
  box ~flex_direction:Row ~justify_content:Space_between
    ~size:{ width = pct 100; height = auto }
    [ text ~style:theme.Theme.muted label; text ~style value ]

let review_field theme review scope =
  if Sift_review.is_reviewed review scope then
    field_styled theme "review" theme.Theme.reviewed "R reviewed"
  else field_styled theme "review" theme.unreviewed "! unreviewed"

let action theme ~key label =
  box ~flex_direction:Row ~gap:(gap_xy 2 0)
    ~size:{ width = pct 100; height = px 1 }
    [
      text ~style:theme.Theme.muted ~truncate:true ~flex_shrink:0.
        ~size:{ width = px 5; height = px 1 }
        key;
      text ~style:theme.normal ~truncate:true ~flex_grow:1.
        ~min_size:{ width = px 0; height = px 0 }
        label;
    ]

let actions theme items =
  List.map (fun (key, label) -> action theme ~key label) items

let cr_count_for_path review path =
  List.fold_left
    (fun count item ->
      if String.equal (Sift_crs.Item.path item) path then count + 1 else count)
    0
    (Sift_review.cr_items review)

let file_hunk_count file = List.length (Sift_diff.File.hunks file)

let file_line_counts file =
  let add_row (added, removed) (row : Sift_diff.Hunk.row) =
    match Sift_diff.Line.kind row.line with
    | Sift_diff.Line.Added -> (added + 1, removed)
    | Removed -> (added, removed + 1)
    | Context -> (added, removed)
  in
  List.fold_left
    (fun counts hunk ->
      List.fold_left add_row counts (Sift_diff.Hunk.rows hunk))
    (0, 0)
    (Sift_diff.File.hunks file)

let content ~theme ~review = function
  | None -> [ section theme "Scope" [ text ~style:theme.muted "No selection" ] ]
  | Some (Feature feature) ->
      let summary = Sift_review.summary review in
      [
        section theme "Scope"
          [ text ~style:theme.normal ~wrap:`Word (feature_identity feature) ];
        section theme "Review"
          [
            review_field theme review Sift_review.Scope.feature;
            field theme "reviewed"
              (Printf.sprintf "%.0f%%" (Sift_review.progress review *. 100.));
            field theme "left"
              (string_of_int (Sift_review.Summary.remaining summary));
            field theme "approval"
              (string_of_approval (Sift_review.approval review));
          ];
        section theme "Range"
          [ text ~style:theme.muted ~wrap:`Word (revision_range feature) ];
      ]
  | Some (File file) ->
      let path = Sift_diff.File.path file in
      let scope = Sift_review.Scope.file path in
      let added, removed = file_line_counts file in
      let content =
        match Sift_diff.File.content file with
        | Binary -> "binary"
        | Text _ -> "text"
      in
      [
        section theme "Scope"
          [
            text ~style:theme.normal ~wrap:`Word path;
            review_field theme review scope;
            field theme "status" (status_char (Sift_diff.File.status file));
            field theme "content" content;
          ];
        section theme "Change"
          [
            field theme "hunks" (string_of_int (file_hunk_count file));
            field theme "lines" (Printf.sprintf "+%d -%d" added removed);
            field theme "CRs" (string_of_int (cr_count_for_path review path));
          ];
        section theme "Actions"
          (actions theme [ ("space", "mark reviewed"); ("c", "comment") ]);
      ]
  | Some (Hunk hunk) ->
      let scope =
        Sift_review.Scope.hunk ~path:hunk.path ~old_start:hunk.old_start
          ~old_count:hunk.old_count ~new_start:hunk.new_start
          ~new_count:hunk.new_count
      in
      [
        section theme "Scope"
          [
            text ~style:theme.normal ~wrap:`Word hunk.path;
            review_field theme review scope;
            field theme "old"
              (Printf.sprintf "-%d,%d" hunk.old_start hunk.old_count);
            field theme "new"
              (Printf.sprintf "+%d,%d" hunk.new_start hunk.new_count);
          ];
        section theme "Actions"
          (actions theme [ ("space", "mark reviewed"); ("c", "comment") ]);
      ]
  | Some (Line (side, path, line)) ->
      let side =
        match side with Sift_review.Scope.Old -> "old" | New -> "new"
      in
      let scope =
        match side with
        | "old" -> Sift_review.Scope.old_line ~path ~line
        | _ -> Sift_review.Scope.new_line ~path ~line
      in
      [
        section theme "Scope"
          [
            text ~style:theme.normal ~wrap:`Word path;
            field theme "line" (string_of_int line);
            field theme "side" side;
          ];
        section theme "Review"
          [ review_field theme review scope ];
        section theme "Actions"
          (actions theme [ ("space", "mark reviewed"); ("c", "comment") ]);
      ]
  | Some (Cr (index, item)) ->
      let path = Sift_crs.Item.path item in
      let line = Sift_crs.Span.start_line (Sift_crs.Item.span item) in
      let review_scope = Sift_review.Scope.new_line ~path ~line in
      let scope =
        section theme "Scope"
          [
            text ~style:theme.normal ~wrap:`Word path;
            review_field theme review review_scope;
            field theme "span"
              (Format.asprintf "%a" Sift_crs.Span.pp (Sift_crs.Item.span item));
          ]
      in
      let request =
        match Sift_crs.Item.comment item with
        | Error error ->
            section theme "Change request"
              [
                field theme "id" (Printf.sprintf "#%d" index);
                field theme "status" "invalid";
                text ~style:theme.error ~wrap:`Word
                  (Format.asprintf "%a" Sift_crs.Error.pp error);
              ]
        | Ok comment ->
            let recipient =
              match Sift_crs.Comment.recipient comment with
              | None -> "-"
              | Some recipient -> string_of_handle recipient
            in
            let body = Sift_crs.Comment.body comment in
            let body =
              if String.equal (String.trim body) "" then "No comment body."
              else body
            in
            section theme "Change request"
              [
                field theme "id" (Printf.sprintf "#%d" index);
                field theme "status"
                  (string_of_cr_status (Sift_crs.Comment.status comment));
                field theme "priority"
                  (string_of_cr_priority (Sift_crs.Comment.priority comment));
                field theme "reporter"
                  (string_of_handle (Sift_crs.Comment.reporter comment));
                field theme "recipient" recipient;
                text ~style:theme.normal ~wrap:`Word body;
              ]
      in
      [
        scope;
        request;
        section theme "Actions"
          (actions theme [ ("e", "edit"); ("R", "resolve"); ("d", "remove") ]);
      ]

let view ~(theme : Theme.t) ~review ~target ~width =
  box ~flex_direction:Column ~gap:(gap 1) ~background:theme.panel
    ~padding:(padding_lrtb 1 1 0 1)
    ~size:{ width = px width; height = pct 100 }
    ~flex_shrink:0.
    ~min_size:{ width = px 0; height = px 0 }
    [
      scroll_box ~scroll_y:true ~scroll_x:false ~background:theme.panel
        ~size:{ width = pct 100; height = pct 100 }
        [
          box ~flex_direction:Column ~gap:(gap 1)
            ~size:{ width = pct 100; height = auto }
            (content ~theme ~review target);
        ];
    ]
