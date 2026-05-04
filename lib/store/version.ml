type t = int

let current = 1
let of_int n = if n > 0 then Ok n else Error (Error.Invalid_version n)

let v n =
  match of_int n with
  | Ok t -> t
  | Error error -> Format.kasprintf invalid_arg "%a" Error.pp error

let to_int t = t
let equal = Int.equal
let compare = Int.compare
let pp = Format.pp_print_int
