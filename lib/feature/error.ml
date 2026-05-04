type t = Invalid_revision of string | Invalid_title

let equal a b =
  match (a, b) with
  | Invalid_revision a, Invalid_revision b -> String.equal a b
  | Invalid_title, Invalid_title -> true
  | (Invalid_revision _ | Invalid_title), _ -> false

let rank = function Invalid_revision _ -> 0 | Invalid_title -> 1

let compare a b =
  match Int.compare (rank a) (rank b) with
  | 0 -> (
      match (a, b) with
      | Invalid_revision a, Invalid_revision b -> String.compare a b
      | Invalid_title, Invalid_title -> 0
      | (Invalid_revision _ | Invalid_title), _ -> 0)
  | n -> n

let pp ppf = function
  | Invalid_revision revision ->
      Format.fprintf ppf "invalid revision %S" revision
  | Invalid_title -> Format.pp_print_string ppf "invalid title"
