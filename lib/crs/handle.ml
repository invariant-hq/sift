type t = string

let is_char = function
  | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '-' | '_' | '.' | '[' | ']' -> true
  | _ -> false

let of_string s =
  let len = String.length s in
  if len = 0 then Error (Error.make (Error.Invalid_handle s))
  else
    let rec loop i =
      if i = len then Ok s
      else if is_char s.[i] then loop (i + 1)
      else Error (Error.make (Error.Invalid_handle s))
    in
    loop 0

let v s =
  match of_string s with
  | Ok t -> t
  | Error _ -> invalid_arg ("Sift_crs.Handle.v: " ^ s)

let equal = String.equal
let compare = String.compare
let to_string t = t
let pp ppf t = Format.pp_print_string ppf t
