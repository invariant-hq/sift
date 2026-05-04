type t = Pending | Approved | Seconded

let rank = function Pending -> 0 | Approved -> 1 | Seconded -> 2
let is_approved = function Pending -> false | Approved | Seconded -> true
let is_seconded = function Pending | Approved -> false | Seconded -> true
let equal a b = Int.equal (rank a) (rank b)
let compare a b = Int.compare (rank a) (rank b)

let pp ppf = function
  | Pending -> Format.pp_print_string ppf "pending"
  | Approved -> Format.pp_print_string ppf "approved"
  | Seconded -> Format.pp_print_string ppf "seconded"
