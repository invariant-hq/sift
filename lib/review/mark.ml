type state = Reviewed | Unreviewed
type t = { scope : Scope.t; state : state }

let make scope state = { scope; state }
let reviewed scope = make scope Reviewed
let unreviewed scope = make scope Unreviewed
let scope t = t.scope
let state t = t.state
let is_reviewed t = match t.state with Reviewed -> true | Unreviewed -> false

let is_unreviewed t =
  match t.state with Reviewed -> false | Unreviewed -> true

let rank_state = function Reviewed -> 0 | Unreviewed -> 1
let equal_state a b = Int.equal (rank_state a) (rank_state b)
let compare_state a b = Int.compare (rank_state a) (rank_state b)
let equal a b = Scope.equal a.scope b.scope && equal_state a.state b.state

let compare a b =
  match Scope.compare a.scope b.scope with
  | 0 -> compare_state a.state b.state
  | n -> n

let pp_state ppf = function
  | Reviewed -> Format.pp_print_string ppf "reviewed"
  | Unreviewed -> Format.pp_print_string ppf "unreviewed"

let pp ppf t = Format.fprintf ppf "%a:%a" Scope.pp t.scope pp_state t.state
