type t = CR | XCR

let equal a b = match (a, b) with CR, CR | XCR, XCR -> true | _ -> false

let compare a b =
  match (a, b) with CR, CR | XCR, XCR -> 0 | CR, XCR -> -1 | XCR, CR -> 1

let of_string = function "CR" -> Some CR | "XCR" -> Some XCR | _ -> None
let to_string = function CR -> "CR" | XCR -> "XCR"
let pp ppf t = Format.pp_print_string ppf (to_string t)
