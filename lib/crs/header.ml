type t = {
  status : Status.t;
  priority : Priority.t;
  reporter : Handle.t;
  recipient : Handle.t option;
}

let make ?(status = Status.CR) ?(priority = Priority.Now) ~reporter ?recipient
    () =
  { status; priority; reporter; recipient }

let status t = t.status
let priority t = t.priority
let reporter t = t.reporter
let recipient t = t.recipient

let equal_option equal a b =
  match (a, b) with
  | None, None -> true
  | Some a, Some b -> equal a b
  | _ -> false

let compare_option compare a b =
  match (a, b) with
  | None, None -> 0
  | None, Some _ -> -1
  | Some _, None -> 1
  | Some a, Some b -> compare a b

let equal a b =
  Status.equal a.status b.status
  && Priority.equal a.priority b.priority
  && Handle.equal a.reporter b.reporter
  && equal_option Handle.equal a.recipient b.recipient

let compare a b =
  let c = Status.compare a.status b.status in
  if c <> 0 then c
  else
    let c = Priority.compare a.priority b.priority in
    if c <> 0 then c
    else
      let c = Handle.compare a.reporter b.reporter in
      if c <> 0 then c
      else compare_option Handle.compare a.recipient b.recipient

let pp ppf t =
  Format.fprintf ppf "%a" Status.pp t.status;
  (match Priority.suffix t.priority with
  | "" -> ()
  | suffix -> Format.fprintf ppf "-%s" suffix);
  Format.fprintf ppf " %a" Handle.pp t.reporter;
  match t.recipient with
  | None -> ()
  | Some recipient -> Format.fprintf ppf " for %a" Handle.pp recipient
