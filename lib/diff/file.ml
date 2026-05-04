type status = Added | Deleted | Modified | Renamed | Copied
type text = Hunk.t list
type content = Text of text | Binary

type t = {
  old_path : string option;
  new_path : string option;
  status : status;
  content : content;
}

let invalid msg = Error.make (Invalid_file msg)

let paths_are_valid old_path new_path status =
  match (status, old_path, new_path) with
  | Added, None, Some _ -> true
  | Deleted, Some _, None -> true
  | (Modified | Renamed | Copied), Some _, Some _ -> true
  | Added, _, _ | Deleted, _, _ | Modified, _, _ | Renamed, _, _ | Copied, _, _
    ->
      false

let range_end start count = if count = 0 then start else start + count - 1

let hunks_overlap prev next =
  let old_overlap =
    Hunk.old_count prev > 0
    && Hunk.old_count next > 0
    && Hunk.old_start next
       <= range_end (Hunk.old_start prev) (Hunk.old_count prev)
  in
  let new_overlap =
    Hunk.new_count prev > 0
    && Hunk.new_count next > 0
    && Hunk.new_start next
       <= range_end (Hunk.new_start prev) (Hunk.new_count prev)
  in
  old_overlap || new_overlap

let text_is_valid = function
  | [] -> true
  | first :: rest ->
      let rec loop prev = function
        | [] -> true
        | hunk :: rest -> (not (hunks_overlap prev hunk)) && loop hunk rest
      in
      loop first rest

let make ?old_path ?new_path ~status content =
  if Option.is_none old_path && Option.is_none new_path then
    Error (invalid "at least one path is required")
  else if not (paths_are_valid old_path new_path status) then
    Error (invalid "status is inconsistent with file paths")
  else
    match content with
    | Binary -> Ok { old_path; new_path; status; content }
    | Text hunks ->
        if text_is_valid hunks then Ok { old_path; new_path; status; content }
        else Error (invalid "text hunks overlap")

let v ?old_path ?new_path ~status content =
  match make ?old_path ?new_path ~status content with
  | Ok t -> t
  | Error e -> Format.kasprintf invalid_arg "%a" Error.pp e

let old_path t = t.old_path
let new_path t = t.new_path

let path t =
  match t.new_path with Some path -> path | None -> Option.get t.old_path

let status t = t.status
let content t = t.content
let hunks t = match t.content with Text hunks -> hunks | Binary -> []
let is_text t = match t.content with Text _ -> true | Binary -> false
let is_binary t = match t.content with Text _ -> false | Binary -> true

let is_empty t =
  match t.content with Text [] -> true | Text (_ :: _) | Binary -> false

let rank_status = function
  | Added -> 0
  | Deleted -> 1
  | Modified -> 2
  | Renamed -> 3
  | Copied -> 4

let equal_status a b = Int.equal (rank_status a) (rank_status b)
let compare_status a b = Int.compare (rank_status a) (rank_status b)

let rec equal_hunks a b =
  match (a, b) with
  | [], [] -> true
  | x :: xs, y :: ys -> Hunk.equal x y && equal_hunks xs ys
  | [], _ :: _ | _ :: _, [] -> false

let equal_content a b =
  match (a, b) with
  | Binary, Binary -> true
  | Text a, Text b -> equal_hunks a b
  | (Binary | Text _), _ -> false

let equal a b =
  Option.equal String.equal a.old_path b.old_path
  && Option.equal String.equal a.new_path b.new_path
  && equal_status a.status b.status
  && equal_content a.content b.content

let rec compare_hunks a b =
  match (a, b) with
  | [], [] -> 0
  | [], _ :: _ -> -1
  | _ :: _, [] -> 1
  | x :: xs, y :: ys -> (
      match Hunk.compare x y with 0 -> compare_hunks xs ys | n -> n)

let compare_content a b =
  match (a, b) with
  | Binary, Binary -> 0
  | Binary, Text _ -> -1
  | Text _, Binary -> 1
  | Text a, Text b -> compare_hunks a b

let compare a b =
  match String.compare (path a) (path b) with
  | 0 -> (
      match Option.compare String.compare a.old_path b.old_path with
      | 0 -> (
          match Option.compare String.compare a.new_path b.new_path with
          | 0 -> (
              match compare_status a.status b.status with
              | 0 -> compare_content a.content b.content
              | n -> n)
          | n -> n)
      | n -> n)
  | n -> n

let prefixed prefix = function
  | None -> "/dev/null"
  | Some path -> prefix ^ path

let status_line = function
  | Added -> Some "new file mode 100644"
  | Deleted -> Some "deleted file mode 100644"
  | Modified -> None
  | Renamed -> None
  | Copied -> None

let pp_git_header ppf t =
  let old_display =
    match t.old_path with Some path -> "a/" ^ path | None -> "a/" ^ path t
  in
  let new_display =
    match t.new_path with Some path -> "b/" ^ path | None -> "b/" ^ path t
  in
  Format.fprintf ppf "diff --git %s %s" old_display new_display;
  (match status_line t.status with
  | None -> ()
  | Some line -> Format.fprintf ppf "@\n%s" line);
  match (t.status, t.old_path, t.new_path) with
  | Renamed, Some old_path, Some new_path ->
      Format.fprintf ppf "@\nrename from %s@\nrename to %s" old_path new_path
  | Copied, Some old_path, Some new_path ->
      Format.fprintf ppf "@\ncopy from %s@\ncopy to %s" old_path new_path
  | Added, _, _ | Deleted, _, _ | Modified, _, _ | Renamed, _, _ | Copied, _, _
    ->
      ()

let pp_file_headers ppf t =
  Format.fprintf ppf "@\n--- %s@\n+++ %s" (prefixed "a/" t.old_path)
    (prefixed "b/" t.new_path)

let pp ppf t =
  pp_git_header ppf t;
  match t.content with
  | Binary ->
      Format.fprintf ppf "@\nBinary files %s and %s differ"
        (prefixed "a/" t.old_path) (prefixed "b/" t.new_path)
  | Text hunks ->
      if not (List.is_empty hunks) then (
        pp_file_headers ppf t;
        List.iter (fun hunk -> Format.fprintf ppf "@\n%a" Hunk.pp hunk) hunks)
      else ()
