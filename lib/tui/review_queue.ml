type cr_nesting = File_level | Hunk_level

type row =
  | Feature of {
      selected : bool;
      mark : Sift_review.Mark.state option;
      approval : Sift_review.Approval.t;
      remaining : int;
    }
  | File of {
      index : int;
      file : Sift_diff.File.t;
      path : string;
      selected : bool;
      mark : Sift_review.Mark.state option;
      cr_count : int;
      unreviewed_count : int;
    }
  | Hunk of {
      path : string;
      scope : Sift_review.Scope.t;
      hunk : Sift_review.Scope.hunk;
      selected : bool;
      mark : Sift_review.Mark.state option;
      cr_count : int;
      unreviewed_count : int;
    }
  | Cr of {
      index : int;
      item : Sift_crs.Item.t;
      selected : bool;
      valid : bool;
      nesting : cr_nesting;
    }

let files review = Sift_feature.files (Sift_review.feature review)

let mark_state review scope =
  match Sift_review.effective_mark review scope with
  | None -> None
  | Some mark -> Some (Sift_review.Mark.state mark)

let is_selected cursor scope =
  Sift_review.Cursor.equal cursor (Sift_review.Cursor.scope scope)

let selected_scope_is_inside cursor scope =
  match Sift_review.Cursor.selected_scope cursor with
  | None -> false
  | Some selected -> Sift_review.Scope.contains scope selected

let is_cr_selected cursor index =
  Sift_review.Cursor.equal cursor (Sift_review.Cursor.cr index)

let cursor_path review cursor =
  match Sift_review.Cursor.target cursor with
  | Scope scope -> Sift_review.Scope.path scope
  | Cr index -> (
      match Sift_review.cr_item review index with
      | None -> None
      | Some item -> Some (Sift_crs.Item.path item))

let changed_line_scope ~path row =
  match Sift_diff.Line.kind row.Sift_diff.Hunk.line with
  | Sift_diff.Line.Context -> None
  | Sift_diff.Line.Removed -> (
      match row.old_line with
      | None -> None
      | Some line -> Some (Sift_review.Scope.old_line ~path ~line))
  | Sift_diff.Line.Added -> (
      match row.new_line with
      | None -> None
      | Some line -> Some (Sift_review.Scope.new_line ~path ~line))

let hunk_review_units ~path hunk =
  List.filter_map
    (fun row -> changed_line_scope ~path row)
    (Sift_diff.Hunk.rows hunk)

let file_review_units file =
  let path = Sift_diff.File.path file in
  match Sift_diff.File.content file with
  | Binary -> [ Sift_review.Scope.file path ]
  | Text hunks ->
      List.concat (List.map (fun hunk -> hunk_review_units ~path hunk) hunks)

let unreviewed_count review scopes =
  List.fold_left
    (fun count scope ->
      if Sift_review.is_reviewed review scope then count else count + 1)
    0 scopes

let line_in_range line start count =
  count > 0 && line >= start && line < start + count

let cr_in_hunk hunk item =
  let span = Sift_crs.Item.span item in
  String.equal (Sift_crs.Item.path item) hunk.Sift_review.Scope.path
  && line_in_range (Sift_crs.Span.start_line span) hunk.new_start hunk.new_count

let cr_count_for_path review path =
  List.fold_left
    (fun count item ->
      if String.equal (Sift_crs.Item.path item) path then count + 1 else count)
    0
    (Sift_review.cr_items review)

let cr_count_for_hunk review hunk =
  List.fold_left
    (fun count item -> if cr_in_hunk hunk item then count + 1 else count)
    0
    (Sift_review.cr_items review)

let feature_row review cursor =
  let scope = Sift_review.Scope.feature in
  Feature
    {
      selected = is_selected cursor scope;
      mark = mark_state review scope;
      approval = Sift_review.approval review;
      remaining = Sift_review.Summary.remaining (Sift_review.summary review);
    }

let file_row review cursor index file =
  let path = Sift_diff.File.path file in
  let scope = Sift_review.Scope.file path in
  File
    {
      index;
      file;
      path;
      selected = is_selected cursor scope;
      mark = mark_state review scope;
      cr_count = cr_count_for_path review path;
      unreviewed_count = unreviewed_count review (file_review_units file);
    }

let hunk_row review cursor ~path hunk =
  let scope = Sift_review.Scope.of_hunk ~path hunk in
  match Sift_review.Scope.view scope with
  | Sift_review.Scope.Hunk hunk_scope ->
      Hunk
        {
          path;
          scope;
          hunk = hunk_scope;
          selected = selected_scope_is_inside cursor scope;
          mark = mark_state review scope;
          cr_count = cr_count_for_hunk review hunk_scope;
          unreviewed_count =
            unreviewed_count review (hunk_review_units ~path hunk);
        }
  | Sift_review.Scope.Feature | Sift_review.Scope.File _
  | Sift_review.Scope.Line _ ->
      assert false

let hunk_rows review cursor file =
  let path = Sift_diff.File.path file in
  match Sift_diff.File.content file with
  | Binary -> []
  | Text hunks -> List.map (hunk_row review cursor ~path) hunks

let cr_row cursor ~nesting index item =
  Cr
    {
      index;
      item;
      selected = is_cr_selected cursor index;
      valid = Sift_crs.Item.is_valid item;
      nesting;
    }

let cr_rows_where review cursor ~nesting predicate =
  let rec loop index acc = function
    | [] -> List.rev acc
    | item :: rest ->
        let acc =
          if predicate item then cr_row cursor ~nesting index item :: acc
          else acc
        in
        loop (index + 1) acc rest
  in
  loop 0 [] (Sift_review.cr_items review)

let cr_rows_for_hunk review cursor hunk =
  cr_rows_where review cursor ~nesting:Hunk_level (cr_in_hunk hunk)

let cr_rows_for_path review cursor ~path ~hunks =
  cr_rows_where review cursor ~nesting:File_level (fun item ->
      String.equal (Sift_crs.Item.path item) path
      && not (List.exists (fun hunk -> cr_in_hunk hunk item) hunks))

let hunk_rows_with_crs review cursor file =
  let path = Sift_diff.File.path file in
  match Sift_diff.File.content file with
  | Binary -> []
  | Text hunks ->
      List.concat
        (List.map
           (fun hunk ->
             let row = hunk_row review cursor ~path hunk in
             match row with
             | Hunk { hunk = hunk_scope; _ } ->
                 row :: cr_rows_for_hunk review cursor hunk_scope
             | Feature _ | File _ | Cr _ -> assert false)
           hunks)

let rows ~review ~cursor () =
  let files = files review in
  let expanded_path = cursor_path review cursor in
  let feature = [ feature_row review cursor ] in
  let file_rows =
    List.mapi
      (fun index file ->
        let row = file_row review cursor index file in
        let path = Sift_diff.File.path file in
        match expanded_path with
        | Some expanded_path when String.equal path expanded_path ->
            let hunk_rows = hunk_rows review cursor file in
            let hunk_scopes =
              List.filter_map
                (function Hunk { hunk; _ } -> Some hunk | _ -> None)
                hunk_rows
            in
            row
            :: (hunk_rows_with_crs review cursor file
               @ cr_rows_for_path review cursor ~path ~hunks:hunk_scopes)
        | Some _ | None -> [ row ])
      files
    |> List.concat
  in
  feature @ file_rows

let cursor = function
  | Feature _ -> Sift_review.Cursor.scope Sift_review.Scope.feature
  | File { path; _ } -> Sift_review.Cursor.scope (Sift_review.Scope.file path)
  | Hunk { scope; _ } -> Sift_review.Cursor.scope scope
  | Cr { index; _ } -> Sift_review.Cursor.cr index
