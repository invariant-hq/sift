type kind = Context | Added | Removed
type t = { kind : kind; text : string }

let make kind ~text = { kind; text }
let kind t = t.kind
let text t = t.text
let is_change t = match t.kind with Context -> false | Added | Removed -> true
let rank_kind = function Context -> 0 | Added -> 1 | Removed -> 2
let equal_kind a b = Int.equal (rank_kind a) (rank_kind b)
let compare_kind a b = Int.compare (rank_kind a) (rank_kind b)
let equal a b = equal_kind a.kind b.kind && String.equal a.text b.text

let compare a b =
  match compare_kind a.kind b.kind with
  | 0 -> String.compare a.text b.text
  | n -> n

let prefix = function Context -> ' ' | Added -> '+' | Removed -> '-'
let pp ppf t = Format.fprintf ppf "%c%s" (prefix t.kind) t.text
