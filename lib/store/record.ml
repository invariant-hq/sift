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

type approval = Pending | Approved | Seconded
type mark_state = Reviewed | Unreviewed

type scope_view =
  | Feature
  | File of path
  | Hunk of hunk
  | Line of side * path * line

type scope = scope_view
type mark = { scope : scope; state : mark_state }
type cr_state = Open | Addressed | Accepted

type cr_record = {
  digest : Sift_crs.Digest.t;
  scope : scope option;
  state : cr_state;
}

type cr_index = int
type cursor_target = Scope of scope | Cr of cr_index
type cursor = cursor_target

let invalid name msg = invalid_arg ("Sift_store.Record." ^ name ^ ": " ^ msg)

let check_path name path =
  if String.equal path "" then invalid name "empty path";
  if not (Filename.is_relative path) then invalid name "absolute path"

let check_line name line = if line < 1 then invalid name "line must be positive"

let check_range name ~first ~count =
  if count < 0 then invalid name "negative count";
  if first < 0 then invalid name "negative start line";
  if count = 0 then (
    if first <> 0 then invalid name "empty range must start at zero")
  else if first = 0 then invalid name "non-empty range must start above zero"

let feature = Feature

let file ~path =
  check_path "file" path;
  File path

let hunk ~path ~old_start ~old_count ~new_start ~new_count =
  check_path "hunk" path;
  check_range "hunk" ~first:old_start ~count:old_count;
  check_range "hunk" ~first:new_start ~count:new_count;
  Hunk { path; old_start; old_count; new_start; new_count }

let old_line ~path ~line =
  check_path "old_line" path;
  check_line "old_line" line;
  Line (Old, path, line)

let new_line ~path ~line =
  check_path "new_line" path;
  check_line "new_line" line;
  Line (New, path, line)

let cr_record ?scope ~digest ~state () = { digest; scope; state }

let cursor = function
  | Cr i when i < 0 -> invalid "cursor" "negative CR index"
  | target -> target

let mark ~scope ~state = { scope; state }
let scope_view scope = scope

let scope_path = function
  | Feature -> None
  | File path -> Some path
  | Hunk hunk -> Some hunk.path
  | Line (_, path, _) -> Some path

let cr_digest cr = cr.digest
let cr_scope cr = cr.scope
let cr_state cr = cr.state
let mark_scope (mark : mark) = mark.scope
let mark_state (mark : mark) = mark.state
let cursor_target cursor = cursor
let cursor_scope = function Scope scope -> Some scope | Cr _ -> None
let cursor_cr = function Scope _ -> None | Cr i -> Some i
let rank_side = function Old -> 0 | New -> 1
let equal_side a b = Int.equal (rank_side a) (rank_side b)
let compare_side a b = Int.compare (rank_side a) (rank_side b)
let rank_approval = function Pending -> 0 | Approved -> 1 | Seconded -> 2
let equal_approval a b = Int.equal (rank_approval a) (rank_approval b)
let compare_approval a b = Int.compare (rank_approval a) (rank_approval b)
let rank_mark_state = function Reviewed -> 0 | Unreviewed -> 1
let equal_mark_state a b = Int.equal (rank_mark_state a) (rank_mark_state b)
let compare_mark_state a b = Int.compare (rank_mark_state a) (rank_mark_state b)

let rank_scope = function
  | Feature -> 0
  | File _ -> 1
  | Hunk _ -> 2
  | Line _ -> 3

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

let compare_scope a b =
  match Int.compare (rank_scope a) (rank_scope b) with
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

let equal_scope a b = Int.equal (compare_scope a b) 0
let compare_mark_identity (a : mark) (b : mark) = compare_scope a.scope b.scope

let equal_mark (a : mark) (b : mark) =
  equal_scope a.scope b.scope && equal_mark_state a.state b.state

let compare_mark (a : mark) (b : mark) =
  match compare_mark_identity a b with
  | 0 -> compare_mark_state a.state b.state
  | n -> n

let rank_cr_state = function Open -> 0 | Addressed -> 1 | Accepted -> 2
let equal_cr_state a b = Int.equal (rank_cr_state a) (rank_cr_state b)
let compare_cr_state a b = Int.compare (rank_cr_state a) (rank_cr_state b)

let equal_cr_identity a b =
  Sift_crs.Digest.equal a.digest b.digest
  && Option.equal equal_scope a.scope b.scope

let compare_cr_identity a b =
  match Sift_crs.Digest.compare a.digest b.digest with
  | 0 -> Option.compare compare_scope a.scope b.scope
  | n -> n

let equal_cr_record a b =
  equal_cr_identity a b && equal_cr_state a.state b.state

let compare_cr_record a b =
  match compare_cr_identity a b with
  | 0 -> compare_cr_state a.state b.state
  | n -> n

let equal_cursor_target a b =
  match (a, b) with
  | Scope a, Scope b -> equal_scope a b
  | Cr a, Cr b -> Int.equal a b
  | (Scope _ | Cr _), _ -> false

let compare_cursor_target a b =
  match (a, b) with
  | Scope a, Scope b -> compare_scope a b
  | Scope _, Cr _ -> -1
  | Cr _, Scope _ -> 1
  | Cr a, Cr b -> Int.compare a b

let equal_cursor a b = equal_cursor_target a b
let compare_cursor a b = compare_cursor_target a b

let pp_side ppf = function
  | Old -> Format.pp_print_string ppf "old"
  | New -> Format.pp_print_string ppf "new"

let pp_mark_state ppf = function
  | Reviewed -> Format.pp_print_string ppf "reviewed"
  | Unreviewed -> Format.pp_print_string ppf "unreviewed"

let pp_scope ppf = function
  | Feature -> Format.pp_print_string ppf "feature"
  | File path -> Format.fprintf ppf "file:%s" path
  | Hunk hunk ->
      Format.fprintf ppf "hunk:%s:-%d,%d+%d,%d" hunk.path hunk.old_start
        hunk.old_count hunk.new_start hunk.new_count
  | Line (side, path, line) ->
      Format.fprintf ppf "%a:%s:%d" pp_side side path line

let pp_cr_state ppf = function
  | Open -> Format.pp_print_string ppf "open"
  | Addressed -> Format.pp_print_string ppf "addressed"
  | Accepted -> Format.pp_print_string ppf "accepted"

let pp_mark ppf (mark : mark) =
  Format.fprintf ppf "%a:%a" pp_scope mark.scope pp_mark_state mark.state

let pp_cr_record ppf cr =
  match cr.scope with
  | None ->
      Format.fprintf ppf "%a:%a" Sift_crs.Digest.pp cr.digest pp_cr_state
        cr.state
  | Some scope ->
      Format.fprintf ppf "%a@%a:%a" Sift_crs.Digest.pp cr.digest pp_scope scope
        pp_cr_state cr.state

let pp_cursor ppf = function
  | Scope scope -> pp_scope ppf scope
  | Cr i -> Format.fprintf ppf "cr:%d" i
