type path = string
type line = int
type side = Old | New

type hunk = {
  path : path;
  old_start : line;
  old_count : int;
  new_start : line;
  new_count : int;
}

type view = Feature | File of path | Hunk of hunk | Line of side * path * line
type t = view

let invalid msg = invalid_arg ("Sift_review.Scope." ^ msg)
let feature = Feature
let check_path path = if String.equal path "" then invalid "path: empty path"

let check_line name line =
  if line < 1 then invalid (name ^ ": line must be positive")

let check_range ~first ~count =
  if count < 0 then invalid "hunk: negative count";
  if first < 0 then invalid "hunk: negative start line";
  if count = 0 then (
    if first <> 0 then invalid "hunk: empty range must start at zero")
  else if first = 0 then invalid "hunk: non-empty range must start above zero"

let file path =
  check_path path;
  File path

let hunk ~path ~old_start ~old_count ~new_start ~new_count =
  check_path path;
  check_range ~first:old_start ~count:old_count;
  check_range ~first:new_start ~count:new_count;
  Hunk { path; old_start; old_count; new_start; new_count }

let of_hunk ~path diff_hunk =
  hunk ~path
    ~old_start:(Sift_diff.Hunk.old_start diff_hunk)
    ~old_count:(Sift_diff.Hunk.old_count diff_hunk)
    ~new_start:(Sift_diff.Hunk.new_start diff_hunk)
    ~new_count:(Sift_diff.Hunk.new_count diff_hunk)

let old_line ~path ~line =
  check_path path;
  check_line "old_line" line;
  Line (Old, path, line)

let new_line ~path ~line =
  check_path path;
  check_line "new_line" line;
  Line (New, path, line)

let view t = t

let path = function
  | Feature -> None
  | File path -> Some path
  | Hunk hunk -> Some hunk.path
  | Line (_, path, _) -> Some path

let line_in_range line start count =
  count > 0 && line >= start && line < start + count

let contains outer inner =
  match (outer, inner) with
  | Feature, _ -> true
  | File outer, File inner -> String.equal outer inner
  | File outer, Hunk hunk -> String.equal outer hunk.path
  | File outer, Line (_, path, _) -> String.equal outer path
  | Hunk outer, Hunk inner ->
      String.equal outer.path inner.path
      && Int.equal outer.old_start inner.old_start
      && Int.equal outer.old_count inner.old_count
      && Int.equal outer.new_start inner.new_start
      && Int.equal outer.new_count inner.new_count
  | Hunk hunk, Line (Old, path, line) ->
      String.equal hunk.path path
      && line_in_range line hunk.old_start hunk.old_count
  | Hunk hunk, Line (New, path, line) ->
      String.equal hunk.path path
      && line_in_range line hunk.new_start hunk.new_count
  | Line (side_a, path_a, line_a), Line (side_b, path_b, line_b) ->
      side_a = side_b && String.equal path_a path_b && Int.equal line_a line_b
  | (File _ | Hunk _ | Line _), Feature
  | Hunk _, File _
  | Line _, (File _ | Hunk _) ->
      false

let rank_side = function Old -> 0 | New -> 1
let equal_side a b = Int.equal (rank_side a) (rank_side b)
let compare_side a b = Int.compare (rank_side a) (rank_side b)
let rank = function Feature -> 0 | File _ -> 1 | Hunk _ -> 2 | Line _ -> 3

let compare_hunk a b =
  match String.compare a.path b.path with
  | 0 -> (
      match Int.compare a.old_start b.old_start with
      | 0 -> (
          match Int.compare a.old_count b.old_count with
          | 0 -> (
              match Int.compare a.new_start b.new_start with
              | 0 -> Int.compare a.new_count b.new_count
              | n -> n)
          | n -> n)
      | n -> n)
  | n -> n

let compare a b =
  match Int.compare (rank a) (rank b) with
  | 0 -> (
      match (a, b) with
      | Feature, Feature -> 0
      | File a, File b -> String.compare a b
      | Hunk a, Hunk b -> compare_hunk a b
      | Line (side_a, path_a, line_a), Line (side_b, path_b, line_b) -> (
          match String.compare path_a path_b with
          | 0 -> (
              match Int.compare line_a line_b with
              | 0 -> compare_side side_a side_b
              | n -> n)
          | n -> n)
      | (Feature | File _ | Hunk _ | Line _), _ -> 0)
  | n -> n

let equal a b = Int.equal (compare a b) 0

let pp_side ppf = function
  | Old -> Format.pp_print_string ppf "old"
  | New -> Format.pp_print_string ppf "new"

let pp_hunk ppf hunk =
  Format.fprintf ppf "%s:-%d,%d+%d,%d" hunk.path hunk.old_start hunk.old_count
    hunk.new_start hunk.new_count

let pp ppf = function
  | Feature -> Format.pp_print_string ppf "feature"
  | File path -> Format.fprintf ppf "file:%s" path
  | Hunk hunk -> Format.fprintf ppf "hunk:%a" pp_hunk hunk
  | Line (side, path, line) ->
      Format.fprintf ppf "%a:%s:%d" pp_side side path line
