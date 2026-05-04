module String_map = Map.Make (String)

type t = {
  new_review_units : int;
  removed_review_units : int;
  new_crs : int;
  removed_crs : int;
  verdict_reset : bool;
  stale_verdict : bool;
}

let add key bag =
  let count = Option.value ~default:0 (String_map.find_opt key bag) in
  String_map.add key (count + 1) bag

let delta_count ~old_ ~new_ =
  String_map.fold
    (fun key new_count count ->
      let old_count = Option.value ~default:0 (String_map.find_opt key old_) in
      if new_count > old_count then count + new_count - old_count else count)
    new_ 0

let kind_key = function
  | Sift_diff.Line.Context -> " "
  | Sift_diff.Line.Added -> "+"
  | Sift_diff.Line.Removed -> "-"

let digest s = Stdlib.Digest.to_hex (Stdlib.Digest.string s)

let hunk_digest hunk =
  let buffer = Buffer.create 128 in
  List.iter
    (fun line ->
      Buffer.add_string buffer (kind_key (Sift_diff.Line.kind line));
      Buffer.add_char buffer '\000';
      Buffer.add_string buffer (Sift_diff.Line.text line);
      Buffer.add_char buffer '\000')
    (Sift_diff.Hunk.lines hunk);
  digest (Buffer.contents buffer)

let row_text row = Sift_diff.Line.text row.Sift_diff.Hunk.line

let context_before rows index =
  let rec loop i =
    if i < 0 then None
    else
      let row = List.nth rows i in
      match Sift_diff.Line.kind row.Sift_diff.Hunk.line with
      | Sift_diff.Line.Context -> Some (row_text row)
      | Sift_diff.Line.Added | Sift_diff.Line.Removed -> loop (i - 1)
  in
  loop (index - 1)

let context_after rows index =
  let length = List.length rows in
  let rec loop i =
    if i >= length then None
    else
      let row = List.nth rows i in
      match Sift_diff.Line.kind row.Sift_diff.Hunk.line with
      | Sift_diff.Line.Context -> Some (row_text row)
      | Sift_diff.Line.Added | Sift_diff.Line.Removed -> loop (i + 1)
  in
  loop (index + 1)

let side_key = function
  | Sift_review.Scope.Old -> "old"
  | Sift_review.Scope.New -> "new"

let line_cursor ~path side line =
  let scope =
    match side with
    | Sift_review.Scope.Old -> Sift_review.Scope.old_line ~path ~line
    | Sift_review.Scope.New -> Sift_review.Scope.new_line ~path ~line
  in
  Sift_review.Cursor.scope scope

let changed_line_key ~path rows index row =
  match Sift_diff.Line.kind row.Sift_diff.Hunk.line with
  | Sift_diff.Line.Context -> None
  | Sift_diff.Line.Removed -> (
      match row.old_line with
      | None -> None
      | Some line ->
          let before = Option.value ~default:"" (context_before rows index) in
          let after = Option.value ~default:"" (context_after rows index) in
          Some
            (Printf.sprintf "line%c%s%c%s%c%d%c%s%c%s%c%s" '\000' path '\000'
               (side_key Sift_review.Scope.Old)
               '\000' line '\000'
               (Sift_diff.Line.text row.Sift_diff.Hunk.line)
               '\000' before '\000' after))
  | Sift_diff.Line.Added -> (
      match row.new_line with
      | None -> None
      | Some line ->
          let before = Option.value ~default:"" (context_before rows index) in
          let after = Option.value ~default:"" (context_after rows index) in
          Some
            (Printf.sprintf "line%c%s%c%s%c%d%c%s%c%s%c%s" '\000' path '\000'
               (side_key Sift_review.Scope.New)
               '\000' line '\000'
               (Sift_diff.Line.text row.Sift_diff.Hunk.line)
               '\000' before '\000' after))

let changed_line_unit ~path rows index row =
  match changed_line_key ~path rows index row with
  | None -> None
  | Some key -> (
      match Sift_diff.Line.kind row.Sift_diff.Hunk.line with
      | Sift_diff.Line.Context -> None
      | Sift_diff.Line.Removed ->
          Option.map
            (fun line -> (key, line_cursor ~path Sift_review.Scope.Old line))
            row.old_line
      | Sift_diff.Line.Added ->
          Option.map
            (fun line -> (key, line_cursor ~path Sift_review.Scope.New line))
            row.new_line)

let hunk_key ~path hunk =
  let lines = Sift_diff.Hunk.lines hunk in
  if lines = [] then
    Printf.sprintf "hunk%c%s%c%d%c%d%c%d%c%d" '\000' path '\000'
      (Sift_diff.Hunk.old_start hunk)
      '\000'
      (Sift_diff.Hunk.old_count hunk)
      '\000'
      (Sift_diff.Hunk.new_start hunk)
      '\000'
      (Sift_diff.Hunk.new_count hunk)
  else
    Printf.sprintf "hunk-content%c%s%c%s" '\000' path '\000' (hunk_digest hunk)

let hunk_unit ~path hunk =
  ( hunk_key ~path hunk,
    Sift_review.Cursor.scope (Sift_review.Scope.of_hunk ~path hunk) )

let hunk_units ~path hunk =
  let rows = Sift_diff.Hunk.rows hunk in
  hunk_unit ~path hunk
  :: List.filter_map
       (fun (index, row) -> changed_line_unit ~path rows index row)
       (List.mapi (fun index row -> (index, row)) rows)

let file_units file =
  let path = Sift_diff.File.path file in
  let file_unit =
    ("file\000" ^ path, Sift_review.Cursor.scope (Sift_review.Scope.file path))
  in
  match Sift_diff.File.content file with
  | Binary -> [ file_unit ]
  | Text hunks ->
      file_unit
      :: List.concat (List.map (fun hunk -> hunk_units ~path hunk) hunks)

let review_units review =
  List.concat_map file_units (Sift_feature.files (Sift_review.feature review))

let add_hunk_units ~path bag hunk =
  let key = hunk_key ~path hunk in
  let bag = add key bag in
  let rows = Sift_diff.Hunk.rows hunk in
  List.fold_left
    (fun bag (index, row) ->
      match changed_line_key ~path rows index row with
      | None -> bag
      | Some key -> add key bag)
    bag
    (List.mapi (fun index row -> (index, row)) rows)

let review_unit_bag review =
  List.fold_left
    (fun bag file ->
      let path = Sift_diff.File.path file in
      let bag = add ("file\000" ^ path) bag in
      match Sift_diff.File.content file with
      | Binary -> bag
      | Text hunks -> List.fold_left (add_hunk_units ~path) bag hunks)
    String_map.empty
    (Sift_feature.files (Sift_review.feature review))

let cr_key item =
  let span = Sift_crs.Item.span item in
  Printf.sprintf "cr%c%s%c%s%c%d%c%d%c%d%c%d" '\000' (Sift_crs.Item.path item)
    '\000'
    (Sift_crs.Digest.to_string (Sift_crs.Item.digest item))
    '\000'
    (Sift_crs.Span.start_line span)
    '\000'
    (Sift_crs.Span.start_col span)
    '\000'
    (Sift_crs.Span.stop_line span)
    '\000'
    (Sift_crs.Span.stop_col span)

let cr_bag review =
  List.fold_left
    (fun bag item -> add (cr_key item) bag)
    String_map.empty
    (Sift_review.cr_items review)

let decrement key bag =
  match String_map.find_opt key bag with
  | None | Some 0 -> (false, bag)
  | Some 1 -> (true, String_map.remove key bag)
  | Some count -> (true, String_map.add key (count - 1) bag)

let first_new_cursor ~before ~after =
  let before_units = review_unit_bag before in
  let rec loop seen = function
    | [] -> None
    | (key, cursor) :: rest ->
        let existed, seen = decrement key seen in
        if existed then loop seen rest else Some cursor
  in
  loop before_units (review_units after)

let feature_content_equal a b =
  Sift_feature.Revision.equal (Sift_feature.base a) (Sift_feature.base b)
  && Sift_feature.Revision.equal (Sift_feature.tip a) (Sift_feature.tip b)
  && Sift_diff.equal (Sift_feature.diff a) (Sift_feature.diff b)

let derive ~before ~after =
  let before_units = review_unit_bag before in
  let after_units = review_unit_bag after in
  let before_crs = cr_bag before in
  let after_crs = cr_bag after in
  let stale_verdict =
    (not
       (feature_content_equal
          (Sift_review.feature before)
          (Sift_review.feature after)))
    && Sift_review.Approval.is_approved (Sift_review.approval before)
  in
  let verdict_reset =
    stale_verdict
    && Sift_review.Approval.equal
         (Sift_review.approval after)
         Sift_review.Approval.Pending
  in
  {
    new_review_units = delta_count ~old_:before_units ~new_:after_units;
    removed_review_units = delta_count ~old_:after_units ~new_:before_units;
    new_crs = delta_count ~old_:before_crs ~new_:after_crs;
    removed_crs = delta_count ~old_:after_crs ~new_:before_crs;
    verdict_reset;
    stale_verdict;
  }

let is_empty t =
  t.new_review_units = 0 && t.removed_review_units = 0 && t.new_crs = 0
  && t.removed_crs = 0 && (not t.verdict_reset) && not t.stale_verdict

let pp ppf t =
  Format.fprintf ppf "refreshed: +%d/-%d units, +%d/-%d CRs" t.new_review_units
    t.removed_review_units t.new_crs t.removed_crs;
  if t.verdict_reset then Format.pp_print_string ppf ", verdict reset"
  else if t.stale_verdict then Format.pp_print_string ppf ", stale verdict"
