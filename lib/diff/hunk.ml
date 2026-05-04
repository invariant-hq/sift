type t = {
  old_start : int;
  old_count : int;
  new_start : int;
  new_count : int;
  lines : Line.t list;
}

type row = { old_line : int option; new_line : int option; line : Line.t }

let invalid msg = Error.make (Invalid_hunk msg)

let range_is_valid ~start ~count =
  count >= 0 && if count = 0 then start >= 0 else start >= 1

let line_counts lines =
  let old_count = ref 0 in
  let new_count = ref 0 in
  List.iter
    (fun line ->
      match Line.kind line with
      | Context ->
          incr old_count;
          incr new_count
      | Added -> incr new_count
      | Removed -> incr old_count)
    lines;
  (!old_count, !new_count)

let make ~old_start ~old_count ~new_start ~new_count lines =
  if not (range_is_valid ~start:old_start ~count:old_count) then
    Error (invalid "invalid old range")
  else if not (range_is_valid ~start:new_start ~count:new_count) then
    Error (invalid "invalid new range")
  else if List.is_empty lines then Error (invalid "hunk has no lines")
  else
    let actual_old_count, actual_new_count = line_counts lines in
    if actual_old_count <> old_count then
      Error (invalid "old range count does not match hunk lines")
    else if actual_new_count <> new_count then
      Error (invalid "new range count does not match hunk lines")
    else Ok { old_start; old_count; new_start; new_count; lines }

let v ~old_start ~old_count ~new_start ~new_count lines =
  match make ~old_start ~old_count ~new_start ~new_count lines with
  | Ok t -> t
  | Error e -> Format.kasprintf invalid_arg "%a" Error.pp e

let old_start t = t.old_start
let old_count t = t.old_count
let new_start t = t.new_start
let new_count t = t.new_count
let lines t = t.lines

let rows t =
  let old_line = ref t.old_start in
  let new_line = ref t.new_start in
  let next r = incr r in
  let row line =
    match Line.kind line with
    | Context ->
        let row =
          { old_line = Some !old_line; new_line = Some !new_line; line }
        in
        next old_line;
        next new_line;
        row
    | Removed ->
        let row = { old_line = Some !old_line; new_line = None; line } in
        next old_line;
        row
    | Added ->
        let row = { old_line = None; new_line = Some !new_line; line } in
        next new_line;
        row
  in
  List.map row t.lines

let rec equal_lines a b =
  match (a, b) with
  | [], [] -> true
  | x :: xs, y :: ys -> Line.equal x y && equal_lines xs ys
  | [], _ :: _ | _ :: _, [] -> false

let equal a b =
  Int.equal a.old_start b.old_start
  && Int.equal a.old_count b.old_count
  && Int.equal a.new_start b.new_start
  && Int.equal a.new_count b.new_count
  && equal_lines a.lines b.lines

let rec compare_lines a b =
  match (a, b) with
  | [], [] -> 0
  | [], _ :: _ -> -1
  | _ :: _, [] -> 1
  | x :: xs, y :: ys -> (
      match Line.compare x y with 0 -> compare_lines xs ys | n -> n)

let compare a b =
  match Int.compare a.old_start b.old_start with
  | 0 -> (
      match Int.compare a.old_count b.old_count with
      | 0 -> (
          match Int.compare a.new_start b.new_start with
          | 0 -> (
              match Int.compare a.new_count b.new_count with
              | 0 -> compare_lines a.lines b.lines
              | n -> n)
          | n -> n)
      | n -> n)
  | n -> n

let pp_range ppf start count =
  if count = 1 then Format.fprintf ppf "%d" start
  else Format.fprintf ppf "%d,%d" start count

let pp ppf t =
  Format.fprintf ppf "@@@@ -%a +%a @@@@"
    (fun ppf () -> pp_range ppf t.old_start t.old_count)
    ()
    (fun ppf () -> pp_range ppf t.new_start t.new_count)
    ();
  List.iter (fun line -> Format.fprintf ppf "@\n%a" Line.pp line) t.lines
