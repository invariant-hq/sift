type t = Now | Soon | Someday

let equal a b =
  match (a, b) with
  | Now, Now | Soon, Soon | Someday, Someday -> true
  | _ -> false

let compare a b =
  match (a, b) with
  | Now, Now | Soon, Soon | Someday, Someday -> 0
  | Now, _ -> -1
  | _, Now -> 1
  | Soon, Someday -> -1
  | Someday, Soon -> 1

let of_suffix = function
  | "soon" -> Some Soon
  | "someday" -> Some Someday
  | _ -> None

let suffix = function Now -> "" | Soon -> "soon" | Someday -> "someday"
let to_string = function Now -> "now" | Soon -> "soon" | Someday -> "someday"
let pp ppf t = Format.pp_print_string ppf (to_string t)
