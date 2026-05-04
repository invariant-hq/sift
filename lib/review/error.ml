type t = Invalid_scope of Scope.t | Invalid_cursor of Cursor.t

let equal a b =
  match (a, b) with
  | Invalid_scope a, Invalid_scope b -> Scope.equal a b
  | Invalid_cursor a, Invalid_cursor b -> Cursor.equal a b
  | (Invalid_scope _ | Invalid_cursor _), _ -> false

let compare a b =
  match (a, b) with
  | Invalid_scope a, Invalid_scope b -> Scope.compare a b
  | Invalid_scope _, Invalid_cursor _ -> -1
  | Invalid_cursor _, Invalid_scope _ -> 1
  | Invalid_cursor a, Invalid_cursor b -> Cursor.compare a b

let pp ppf = function
  | Invalid_scope scope -> Format.fprintf ppf "invalid scope %a" Scope.pp scope
  | Invalid_cursor cursor ->
      Format.fprintf ppf "invalid cursor %a" Cursor.pp cursor
