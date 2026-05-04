type t = string

let normalize s =
  let len = String.length s in
  let buf = Buffer.create len in
  let pending_space = ref false in
  let rec loop i =
    if i = len then ()
    else
      match s.[i] with
      | ' ' | '\t' | '\n' | '\r' ->
          pending_space := Buffer.length buf > 0;
          loop (i + 1)
      | c ->
          if !pending_space then Buffer.add_char buf ' ';
          pending_space := false;
          Buffer.add_char buf c;
          loop (i + 1)
  in
  loop 0;
  Buffer.contents buf

let create s = Stdlib.Digest.to_hex (Stdlib.Digest.string (normalize s))
let is_lower_hex = function '0' .. '9' | 'a' .. 'f' -> true | _ -> false

let of_string s =
  if String.length s = 32 && String.for_all is_lower_hex s then Some s else None

let equal = String.equal
let compare = String.compare
let to_string t = t
let pp ppf t = Format.pp_print_string ppf t
