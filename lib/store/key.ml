type namespace = string

type t = {
  namespace : namespace option;
  base : Sift_feature.Revision.t;
  tip : Sift_feature.Revision.t;
}

let namespace_is_valid = function
  | None -> true
  | Some namespace -> not (String.equal namespace "")

let v ?namespace ~base ~tip () =
  if namespace_is_valid namespace then { namespace; base; tip }
  else invalid_arg "Sift_store.Key.v: empty namespace"

let of_feature ?namespace feature =
  v ?namespace
    ~base:(Sift_feature.base feature)
    ~tip:(Sift_feature.tip feature) ()

let namespace t = t.namespace
let base t = t.base
let tip t = t.tip

let equal a b =
  Option.equal String.equal a.namespace b.namespace
  && Sift_feature.Revision.equal a.base b.base
  && Sift_feature.Revision.equal a.tip b.tip

let compare a b =
  match Option.compare String.compare a.namespace b.namespace with
  | 0 -> (
      match Sift_feature.Revision.compare a.base b.base with
      | 0 -> Sift_feature.Revision.compare a.tip b.tip
      | n -> n)
  | n -> n

let to_string t =
  let base = Sift_feature.Revision.to_string t.base in
  let tip = Sift_feature.Revision.to_string t.tip in
  match t.namespace with
  | None -> base ^ ".." ^ tip
  | Some namespace -> namespace ^ ":" ^ base ^ ".." ^ tip

let pp ppf t = Format.pp_print_string ppf (to_string t)
