type t =
  | Invalid_version of int
  | Invalid_key of string
  | Invalid_path of string
  | Invalid_range of { first : int; last : int }
  | Duplicate_mark
  | Duplicate_cr
  | Decode of string
  | Io of string

let message = function
  | Invalid_version n -> Format.asprintf "invalid store version %d" n
  | Invalid_key key -> Format.asprintf "invalid store key %S" key
  | Invalid_path path -> Format.asprintf "invalid path %S" path
  | Invalid_range { first; last } ->
      Format.asprintf "invalid range %d..%d" first last
  | Duplicate_mark -> "duplicate mark"
  | Duplicate_cr -> "duplicate CR record"
  | Decode msg -> "decode error: " ^ msg
  | Io msg -> "io error: " ^ msg

let equal a b =
  match (a, b) with
  | Invalid_version a, Invalid_version b -> Int.equal a b
  | Invalid_key a, Invalid_key b -> String.equal a b
  | Invalid_path a, Invalid_path b -> String.equal a b
  | Invalid_range a, Invalid_range b ->
      Int.equal a.first b.first && Int.equal a.last b.last
  | Duplicate_mark, Duplicate_mark -> true
  | Duplicate_cr, Duplicate_cr -> true
  | Decode a, Decode b -> String.equal a b
  | Io a, Io b -> String.equal a b
  | ( ( Invalid_version _ | Invalid_key _ | Invalid_path _ | Invalid_range _
      | Duplicate_mark | Duplicate_cr | Decode _ | Io _ ),
      _ ) ->
      false

let rank = function
  | Invalid_version _ -> 0
  | Invalid_key _ -> 1
  | Invalid_path _ -> 2
  | Invalid_range _ -> 3
  | Duplicate_mark -> 4
  | Duplicate_cr -> 5
  | Decode _ -> 6
  | Io _ -> 7

let compare a b =
  match Int.compare (rank a) (rank b) with
  | 0 -> (
      match (a, b) with
      | Invalid_version a, Invalid_version b -> Int.compare a b
      | Invalid_key a, Invalid_key b -> String.compare a b
      | Invalid_path a, Invalid_path b -> String.compare a b
      | Invalid_range a, Invalid_range b -> (
          match Int.compare a.first b.first with
          | 0 -> Int.compare a.last b.last
          | n -> n)
      | Duplicate_mark, Duplicate_mark -> 0
      | Duplicate_cr, Duplicate_cr -> 0
      | Decode a, Decode b -> String.compare a b
      | Io a, Io b -> String.compare a b
      | ( ( Invalid_version _ | Invalid_key _ | Invalid_path _ | Invalid_range _
          | Duplicate_mark | Duplicate_cr | Decode _ | Io _ ),
          _ ) ->
          0)
  | n -> n

let pp ppf t = Format.pp_print_string ppf (message t)
