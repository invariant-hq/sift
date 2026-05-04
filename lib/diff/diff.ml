type t = File.t list

let empty = []
let make files = files
let files t = t
let file_count = List.length
let is_empty = List.is_empty

let rec equal a b =
  match (a, b) with
  | [], [] -> true
  | x :: xs, y :: ys -> File.equal x y && equal xs ys
  | [], _ :: _ | _ :: _, [] -> false

let rec compare a b =
  match (a, b) with
  | [], [] -> 0
  | [], _ :: _ -> -1
  | _ :: _, [] -> 1
  | x :: xs, y :: ys -> (
      match File.compare x y with 0 -> compare xs ys | n -> n)

let pp ppf t =
  let rec loop = function
    | [] -> ()
    | [ file ] -> File.pp ppf file
    | file :: files ->
        Format.fprintf ppf "%a@\n" File.pp file;
        loop files
  in
  loop t
