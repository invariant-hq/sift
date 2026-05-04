type t = { header : Header.t; body : string }

let make ~header ~body = { header; body }
let header t = t.header
let body t = t.body
let status t = Header.status t.header
let priority t = Header.priority t.header
let reporter t = Header.reporter t.header
let recipient t = Header.recipient t.header
let digest t = Digest.create (Format.asprintf "%a:%s" Header.pp t.header t.body)
let equal a b = Header.equal a.header b.header && String.equal a.body b.body

let compare a b =
  let c = Header.compare a.header b.header in
  if c <> 0 then c else String.compare a.body b.body

let pp_header ppf t = Format.fprintf ppf "%a:" Header.pp t.header

let pp ppf t =
  pp_header ppf t;
  if not (String.equal t.body "") then Format.fprintf ppf " %s" t.body
