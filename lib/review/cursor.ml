type cr_index = int
type target = Scope of Scope.t | Cr of cr_index
type move = First | Previous | Next | Last
type t = target

let feature = Scope Scope.feature
let scope scope = Scope scope

let cr i =
  if i < 0 then invalid_arg "Sift_review.Cursor.cr: negative index";
  Cr i

let target t = t
let selected_scope = function Scope scope -> Some scope | Cr _ -> None
let selected_cr = function Scope _ -> None | Cr i -> Some i

let compare_target a b =
  match (a, b) with
  | Scope a, Scope b -> Scope.compare a b
  | Scope _, Cr _ -> -1
  | Cr _, Scope _ -> 1
  | Cr a, Cr b -> Int.compare a b

let compare = compare_target
let equal a b = Int.equal (compare a b) 0

let pp ppf = function
  | Scope scope -> Scope.pp ppf scope
  | Cr i -> Format.fprintf ppf "cr:%d" i
