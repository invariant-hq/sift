type kind =
  | Invalid_hunk of string
  | Invalid_file of string
  | Invalid_unified_diff of string
  | Invalid_context of int

type t = { kind : kind; line : int option }

let make kind = { kind; line = None }

let with_line line t =
  if line < 1 then invalid_arg "Sift_diff.Error.with_line";
  { t with line = Some line }

let kind t = t.kind
let line t = t.line

let equal_kind a b =
  match (a, b) with
  | Invalid_hunk a, Invalid_hunk b -> String.equal a b
  | Invalid_file a, Invalid_file b -> String.equal a b
  | Invalid_unified_diff a, Invalid_unified_diff b -> String.equal a b
  | Invalid_context a, Invalid_context b -> Int.equal a b
  | ( ( Invalid_hunk _ | Invalid_file _ | Invalid_unified_diff _
      | Invalid_context _ ),
      _ ) ->
      false

let rank_kind = function
  | Invalid_hunk _ -> 0
  | Invalid_file _ -> 1
  | Invalid_unified_diff _ -> 2
  | Invalid_context _ -> 3

let compare_kind a b =
  match Int.compare (rank_kind a) (rank_kind b) with
  | 0 -> (
      match (a, b) with
      | Invalid_hunk a, Invalid_hunk b -> String.compare a b
      | Invalid_file a, Invalid_file b -> String.compare a b
      | Invalid_unified_diff a, Invalid_unified_diff b -> String.compare a b
      | Invalid_context a, Invalid_context b -> Int.compare a b
      | ( ( Invalid_hunk _ | Invalid_file _ | Invalid_unified_diff _
          | Invalid_context _ ),
          _ ) ->
          0)
  | n -> n

let equal a b = equal_kind a.kind b.kind
let compare a b = compare_kind a.kind b.kind

let pp_kind ppf = function
  | Invalid_hunk msg -> Format.fprintf ppf "invalid hunk: %s" msg
  | Invalid_file msg -> Format.fprintf ppf "invalid file diff: %s" msg
  | Invalid_unified_diff msg ->
      Format.fprintf ppf "invalid unified diff: %s" msg
  | Invalid_context n -> Format.fprintf ppf "invalid context: %d" n

let pp ppf t =
  match t.line with
  | None -> pp_kind ppf t.kind
  | Some line -> Format.fprintf ppf "line %d: %a" line pp_kind t.kind
