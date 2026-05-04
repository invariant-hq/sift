type t = {
  total : int;
  reviewed : int;
  cr_items : int;
  valid_cr_items : int;
  approval : Approval.t;
}

let v ~total ~reviewed ~cr_items ~valid_cr_items ~approval =
  { total; reviewed; cr_items; valid_cr_items; approval }

let total t = t.total
let reviewed t = t.reviewed
let remaining t = t.total - t.reviewed
let progress t = if t.total = 0 then 1.0 else float t.reviewed /. float t.total
let is_complete t = remaining t = 0
let cr_items t = t.cr_items
let valid_cr_items t = t.valid_cr_items
let invalid_cr_items t = t.cr_items - t.valid_cr_items
let approval t = t.approval

let equal a b =
  Int.equal a.total b.total
  && Int.equal a.reviewed b.reviewed
  && Int.equal a.cr_items b.cr_items
  && Int.equal a.valid_cr_items b.valid_cr_items
  && Approval.equal a.approval b.approval

let compare a b =
  match Int.compare a.total b.total with
  | 0 -> (
      match Int.compare a.reviewed b.reviewed with
      | 0 -> (
          match Int.compare a.cr_items b.cr_items with
          | 0 -> (
              match Int.compare a.valid_cr_items b.valid_cr_items with
              | 0 -> Approval.compare a.approval b.approval
              | n -> n)
          | n -> n)
      | n -> n)
  | n -> n

let pp ppf t =
  Format.fprintf ppf "%d/%d reviewed, %d/%d valid CRs, %a" t.reviewed t.total
    t.valid_cr_items t.cr_items Approval.pp t.approval
