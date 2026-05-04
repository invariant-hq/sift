type t = {
  path : string;
  syntax : Syntax.t;
  span : Span.t;
  raw : string;
  comment : (Comment.t, Error.t) result;
}

let make ~path ~syntax ~span ~raw comment = { path; syntax; span; raw; comment }
let path t = t.path
let syntax t = t.syntax
let span t = t.span
let raw t = t.raw
let comment t = t.comment

let digest t =
  match t.comment with
  | Ok comment -> Comment.digest comment
  | Error _ -> Digest.create t.raw

let is_valid t = match t.comment with Ok _ -> true | Error _ -> false

let equal_result a b =
  match (a, b) with
  | Ok a, Ok b -> Comment.equal a b
  | Error a, Error b -> Error.equal a b
  | _ -> false

let compare_result a b =
  match (a, b) with
  | Ok a, Ok b -> Comment.compare a b
  | Ok _, Error _ -> -1
  | Error _, Ok _ -> 1
  | Error a, Error b -> Error.compare a b

let equal a b =
  String.equal a.path b.path
  && Syntax.equal a.syntax b.syntax
  && Span.equal a.span b.span && String.equal a.raw b.raw
  && equal_result a.comment b.comment

let compare a b =
  let c = String.compare a.path b.path in
  if c <> 0 then c
  else
    let c = Span.compare a.span b.span in
    if c <> 0 then c
    else
      let c = Syntax.compare a.syntax b.syntax in
      if c <> 0 then c
      else
        let c = String.compare a.raw b.raw in
        if c <> 0 then c else compare_result a.comment b.comment

let pp ppf t = Format.fprintf ppf "%s:%a" t.path Span.pp t.span
