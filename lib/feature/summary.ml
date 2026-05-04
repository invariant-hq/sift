type t = {
  files : int;
  text_files : int;
  binary_files : int;
  hunks : int;
  added_lines : int;
  removed_lines : int;
}

let zero =
  {
    files = 0;
    text_files = 0;
    binary_files = 0;
    hunks = 0;
    added_lines = 0;
    removed_lines = 0;
  }

let count_line (added_lines, removed_lines) line =
  match Sift_diff.Line.kind line with
  | Context -> (added_lines, removed_lines)
  | Added -> (added_lines + 1, removed_lines)
  | Removed -> (added_lines, removed_lines + 1)

let count_hunk (hunks, added_lines, removed_lines) hunk =
  let added_lines, removed_lines =
    List.fold_left count_line
      (added_lines, removed_lines)
      (Sift_diff.Hunk.lines hunk)
  in
  (hunks + 1, added_lines, removed_lines)

let count_file t file =
  match Sift_diff.File.content file with
  | Binary -> { t with files = t.files + 1; binary_files = t.binary_files + 1 }
  | Text hunks ->
      let hunks, added_lines, removed_lines =
        List.fold_left count_hunk
          (t.hunks, t.added_lines, t.removed_lines)
          hunks
      in
      {
        files = t.files + 1;
        text_files = t.text_files + 1;
        binary_files = t.binary_files;
        hunks;
        added_lines;
        removed_lines;
      }

let of_diff diff = List.fold_left count_file zero (Sift_diff.files diff)
let files t = t.files
let text_files t = t.text_files
let binary_files t = t.binary_files
let hunks t = t.hunks
let added_lines t = t.added_lines
let removed_lines t = t.removed_lines

let equal a b =
  Int.equal a.files b.files
  && Int.equal a.text_files b.text_files
  && Int.equal a.binary_files b.binary_files
  && Int.equal a.hunks b.hunks
  && Int.equal a.added_lines b.added_lines
  && Int.equal a.removed_lines b.removed_lines

let compare a b =
  match Int.compare a.files b.files with
  | 0 -> (
      match Int.compare a.text_files b.text_files with
      | 0 -> (
          match Int.compare a.binary_files b.binary_files with
          | 0 -> (
              match Int.compare a.hunks b.hunks with
              | 0 -> (
                  match Int.compare a.added_lines b.added_lines with
                  | 0 -> Int.compare a.removed_lines b.removed_lines
                  | n -> n)
              | n -> n)
          | n -> n)
      | n -> n)
  | n -> n

let pp ppf t =
  Format.fprintf ppf "%d files (%d text, %d binary), %d hunks, +%d/-%d" t.files
    t.text_files t.binary_files t.hunks t.added_lines t.removed_lines
