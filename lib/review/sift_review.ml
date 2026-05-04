module Scope = Scope
module Mark = Mark
module Approval = Approval
module Cursor = Cursor
module Summary = Summary
module Error = Error

type t = {
  feature : Sift_feature.t;
  cr_items : Sift_crs.Item.t list;
  marks : Mark.t list;
  approval : Approval.t;
  cursor : Cursor.t;
}

type review_unit = {
  scope : Scope.t;
  content_digest : Sift_crs.Digest.t option;
}

let rec list_equal equal a b =
  match (a, b) with
  | [], [] -> true
  | x :: xs, y :: ys -> equal x y && list_equal equal xs ys
  | [], _ :: _ | _ :: _, [] -> false

let rec list_compare compare a b =
  match (a, b) with
  | [], [] -> 0
  | [], _ :: _ -> -1
  | _ :: _, [] -> 1
  | x :: xs, y :: ys -> (
      match compare x y with 0 -> list_compare compare xs ys | n -> n)

let hunk_scope ~path hunk = Scope.of_hunk ~path hunk

let changed_line_scope ~path row =
  match Sift_diff.Line.kind row.Sift_diff.Hunk.line with
  | Sift_diff.Line.Context -> None
  | Sift_diff.Line.Removed -> (
      match row.old_line with
      | None -> None
      | Some line -> Some (Scope.old_line ~path ~line))
  | Sift_diff.Line.Added -> (
      match row.new_line with
      | None -> None
      | Some line -> Some (Scope.new_line ~path ~line))

let navigation_scopes feature =
  let scopes = ref [ Scope.feature ] in
  let add scope = scopes := scope :: !scopes in
  List.iter
    (fun file ->
      let path = Sift_diff.File.path file in
      add (Scope.file path);
      match Sift_diff.File.content file with
      | Binary -> ()
      | Text hunks ->
          List.iter
            (fun hunk ->
              add (hunk_scope ~path hunk);
              List.iter
                (fun row ->
                  match changed_line_scope ~path row with
                  | None -> ()
                  | Some scope -> add scope)
                (Sift_diff.Hunk.rows hunk))
            hunks)
    (Sift_feature.files feature);
  List.rev !scopes

let review_units feature =
  let units = ref [] in
  let add scope = units := scope :: !units in
  List.iter
    (fun file ->
      let path = Sift_diff.File.path file in
      match Sift_diff.File.content file with
      | Binary -> add (Scope.file path)
      | Text hunks ->
          List.iter
            (fun hunk ->
              List.iter
                (fun row ->
                  match changed_line_scope ~path row with
                  | None -> ()
                  | Some scope -> add scope)
                (Sift_diff.Hunk.rows hunk))
            hunks)
    (Sift_feature.files feature);
  List.rev !units

let cursor_targets t =
  let cr_targets =
    let rec loop i items acc =
      match items with
      | [] -> List.rev acc
      | _ :: rest -> loop (i + 1) rest (Cursor.cr i :: acc)
    in
    loop 0 t.cr_items []
  in
  List.map Cursor.scope (navigation_scopes t.feature) @ cr_targets

let scope_is_valid feature scope =
  List.exists (Scope.equal scope) (navigation_scopes feature)

let cursor_is_valid t cursor =
  match Cursor.target cursor with
  | Scope scope -> scope_is_valid t.feature scope
  | Cr i -> i >= 0 && i < List.length t.cr_items

let sort_marks marks = List.sort Mark.compare marks

let v ~feature ~cr_items =
  { feature; cr_items; marks = []; approval = Pending; cursor = Cursor.feature }

let feature t = t.feature
let cr_items t = t.cr_items
let cr_count t = List.length t.cr_items
let cr_item t i = if i < 0 then None else List.nth_opt t.cr_items i

let find_cr_items t ~digest =
  List.filter
    (fun item -> Sift_crs.Digest.equal (Sift_crs.Item.digest item) digest)
    t.cr_items

let marks t = t.marks

let mark t scope =
  List.find_opt (fun mark -> Scope.equal (Mark.scope mark) scope) t.marks

let digest_string s =
  let digest = Stdlib.Digest.string s |> Stdlib.Digest.to_hex in
  match Sift_crs.Digest.of_string digest with
  | Some digest -> digest
  | None -> assert false

let line_content_digest line =
  let prefix = Sift_diff.Line.prefix (Sift_diff.Line.kind line) in
  digest_string (String.make 1 prefix ^ Sift_diff.Line.text line)

let specificity scope =
  match Scope.view scope with
  | Feature -> 0
  | File _ -> 1
  | Hunk _ -> 2
  | Line _ -> 3

let more_specific a b =
  match
    Int.compare (specificity (Mark.scope a)) (specificity (Mark.scope b))
  with
  | 0 -> Mark.compare a b > 0
  | n -> n > 0

let effective_mark t scope =
  let rec loop best = function
    | [] -> best
    | mark :: rest ->
        if Scope.contains (Mark.scope mark) scope then
          match best with
          | None -> loop (Some mark) rest
          | Some best_mark ->
              if more_specific mark best_mark then loop (Some mark) rest
              else loop best rest
        else loop best rest
  in
  loop None t.marks

let review_units_with_content feature =
  let units = ref [] in
  let add scope content_digest = units := { scope; content_digest } :: !units in
  List.iter
    (fun file ->
      let path = Sift_diff.File.path file in
      match Sift_diff.File.content file with
      | Binary -> add (Scope.file path) None
      | Text hunks ->
          List.iter
            (fun hunk ->
              List.iter
                (fun row ->
                  match changed_line_scope ~path row with
                  | None -> ()
                  | Some scope ->
                      add scope (Some (line_content_digest row.line)))
                (Sift_diff.Hunk.rows hunk))
            hunks)
    (Sift_feature.files feature);
  List.rev !units

let content_digest_for_scope units scope =
  List.find_map
    (fun unit ->
      if Scope.equal scope unit.scope then unit.content_digest else None)
    units

let reviewed_units t feature =
  let add_if_reviewed units unit =
    match effective_mark t unit.scope with
    | Some mark when Mark.is_reviewed mark -> unit :: units
    | Some _ | None -> units
  in
  List.fold_left add_if_reviewed [] (review_units_with_content feature)

let feature_content_equal a b =
  Sift_feature.Revision.equal (Sift_feature.base a) (Sift_feature.base b)
  && Sift_feature.Revision.equal (Sift_feature.tip a) (Sift_feature.tip b)
  && Sift_diff.equal (Sift_feature.diff a) (Sift_feature.diff b)

let unit_content_matches units unit =
  match unit.content_digest with
  | None -> false
  | Some digest ->
      Option.equal Sift_crs.Digest.equal (Some digest)
        (content_digest_for_scope units unit.scope)

let refresh t ~feature ~cr_items =
  let feature_unchanged = feature_content_equal t.feature feature in
  let marks =
    if feature_unchanged then t.marks
    else
      let current_units = review_units_with_content feature in
      reviewed_units t t.feature
      |> List.filter (unit_content_matches current_units)
      |> List.map (fun unit -> Mark.reviewed unit.scope)
      |> sort_marks
  in
  let approval = if feature_unchanged then t.approval else Approval.Pending in
  let t = { t with feature; cr_items; marks; approval } in
  if cursor_is_valid t t.cursor then t else { t with cursor = Cursor.feature }

let approval t = t.approval
let cursor t = t.cursor

let summary t =
  let units = review_units t.feature in
  let total = List.length units in
  let reviewed =
    List.fold_left
      (fun count scope ->
        match effective_mark t scope with
        | Some mark when Mark.is_reviewed mark -> count + 1
        | Some _ | None -> count)
      0 units
  in
  let cr_items = List.length t.cr_items in
  let valid_cr_items =
    List.fold_left
      (fun count item ->
        if Sift_crs.Item.is_valid item then count + 1 else count)
      0 t.cr_items
  in
  Summary.v ~total ~reviewed ~cr_items ~valid_cr_items ~approval:t.approval

let progress t = Summary.progress (summary t)

let set_mark t mark =
  let scope = Mark.scope mark in
  if not (scope_is_valid t.feature scope) then Error (Error.Invalid_scope scope)
  else
    let marks =
      mark
      :: List.filter
           (fun existing -> not (Scope.equal (Mark.scope existing) scope))
           t.marks
    in
    Ok { t with marks = sort_marks marks }

let mark_reviewed t scope = set_mark t (Mark.reviewed scope)
let mark_unreviewed t scope = set_mark t (Mark.unreviewed scope)

let clear_mark t scope =
  {
    t with
    marks =
      List.filter
        (fun existing -> not (Scope.equal (Mark.scope existing) scope))
        t.marks;
  }

let is_reviewed t scope =
  match effective_mark t scope with
  | Some mark -> Mark.is_reviewed mark
  | None -> false

let set_approval t approval = { t with approval }

let set_cursor t cursor =
  if cursor_is_valid t cursor then Ok { t with cursor }
  else Error (Error.Invalid_cursor cursor)

let index_of_cursor cursor targets =
  let rec loop i = function
    | [] -> None
    | target :: rest ->
        if Cursor.equal cursor target then Some i else loop (i + 1) rest
  in
  loop 0 targets

let nth_cursor targets i =
  match List.nth_opt targets i with
  | Some cursor -> cursor
  | None -> Cursor.feature

let move_cursor ?(wrap = false) t move =
  let targets = cursor_targets t in
  match targets with
  | [] -> t
  | _ :: _ ->
      let last = List.length targets - 1 in
      let current =
        Option.value ~default:0 (index_of_cursor t.cursor targets)
      in
      let next =
        match move with
        | Cursor.First -> 0
        | Cursor.Last -> last
        | Cursor.Previous ->
            if current = 0 then if wrap then last else current else current - 1
        | Cursor.Next ->
            if current = last then if wrap then 0 else current else current + 1
      in
      { t with cursor = nth_cursor targets next }

let next ?wrap t = move_cursor ?wrap t Cursor.Next
let previous ?wrap t = move_cursor ?wrap t Cursor.Previous
let is_complete t = Summary.is_complete (summary t)

let equal a b =
  Sift_feature.equal a.feature b.feature
  && list_equal Sift_crs.Item.equal a.cr_items b.cr_items
  && list_equal Mark.equal a.marks b.marks
  && Approval.equal a.approval b.approval
  && Cursor.equal a.cursor b.cursor

let compare a b =
  match Sift_feature.compare a.feature b.feature with
  | 0 -> (
      match list_compare Sift_crs.Item.compare a.cr_items b.cr_items with
      | 0 -> (
          match list_compare Mark.compare a.marks b.marks with
          | 0 -> (
              match Approval.compare a.approval b.approval with
              | 0 -> Cursor.compare a.cursor b.cursor
              | n -> n)
          | n -> n)
      | n -> n)
  | n -> n

let pp ppf t =
  Format.fprintf ppf "@[<hov 2>review %a %a@]" Sift_feature.pp t.feature
    Summary.pp (summary t)
