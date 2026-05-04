type value =
  | Null
  | Bool of bool
  | Int of int
  | String of string
  | List of value list
  | Fields of (string * value) list

type 'a t = { encode : 'a -> value; decode : value -> ('a, Error.t) result }

let make ~encode ~decode = { encode; decode }
let encode t v = t.encode v
let decode t value = t.decode value
