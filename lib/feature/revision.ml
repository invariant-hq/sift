type t = string

let of_string s =
  if String.equal s "" then Error Error.(Invalid_revision s) else Ok s

let v s =
  match of_string s with
  | Ok t -> t
  | Error e -> Format.kasprintf invalid_arg "%a" Error.pp e

let equal = String.equal
let compare = String.compare
let to_string t = t
let pp = Format.pp_print_string
