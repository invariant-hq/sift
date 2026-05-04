module Revision = Revision
module Summary = Summary

type t = {
  title : string option;
  base : Revision.t;
  tip : Revision.t;
  diff : Sift_diff.t;
}

let title_is_valid = function
  | None -> true
  | Some title -> not (String.equal title "")

let make ?title ~base ~tip ~diff () =
  if title_is_valid title then Ok { title; base; tip; diff }
  else Error Error.Invalid_title

let v ?title ~base ~tip ~diff () =
  match make ?title ~base ~tip ~diff () with
  | Ok t -> t
  | Error e -> Format.kasprintf invalid_arg "%a" Error.pp e

let title t = t.title
let base t = t.base
let tip t = t.tip
let diff t = t.diff
let summary t = Summary.of_diff t.diff
let files t = Sift_diff.files t.diff

let find_file t ~path =
  List.find_opt
    (fun file -> String.equal (Sift_diff.File.path file) path)
    (files t)

let equal a b =
  Option.equal String.equal a.title b.title
  && Revision.equal a.base b.base
  && Revision.equal a.tip b.tip
  && Sift_diff.equal a.diff b.diff

let compare a b =
  match Option.compare String.compare a.title b.title with
  | 0 -> (
      match Revision.compare a.base b.base with
      | 0 -> (
          match Revision.compare a.tip b.tip with
          | 0 -> Sift_diff.compare a.diff b.diff
          | n -> n)
      | n -> n)
  | n -> n

let pp_title ppf = function
  | None -> ()
  | Some title -> Format.fprintf ppf " %S" title

let pp ppf t =
  Format.fprintf ppf "@[<hov 2>feature%a %a..%a (%a)@]" pp_title t.title
    Revision.pp t.base Revision.pp t.tip Summary.pp (summary t)
