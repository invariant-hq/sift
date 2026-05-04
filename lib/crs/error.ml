type kind =
  | Invalid_handle of string
  | Invalid_status of string
  | Invalid_priority of string
  | Invalid_header of string
  | Invalid_span of string
  | Invalid_anchor of string
  | Stale_item

type t = { kind : kind; span : Span.t option }

let make kind = { kind; span = None }
let with_span span t = { t with span = Some span }
let kind t = t.kind
let span t = t.span

let equal_kind a b =
  match (a, b) with
  | Invalid_handle a, Invalid_handle b
  | Invalid_status a, Invalid_status b
  | Invalid_priority a, Invalid_priority b
  | Invalid_header a, Invalid_header b
  | Invalid_span a, Invalid_span b
  | Invalid_anchor a, Invalid_anchor b ->
      String.equal a b
  | Stale_item, Stale_item -> true
  | _ -> false

let rank_kind = function
  | Invalid_handle _ -> 0
  | Invalid_status _ -> 1
  | Invalid_priority _ -> 2
  | Invalid_header _ -> 3
  | Invalid_span _ -> 4
  | Invalid_anchor _ -> 5
  | Stale_item -> 6

let compare_kind a b =
  let c = Int.compare (rank_kind a) (rank_kind b) in
  if c <> 0 then c
  else
    match (a, b) with
    | Invalid_handle a, Invalid_handle b
    | Invalid_status a, Invalid_status b
    | Invalid_priority a, Invalid_priority b
    | Invalid_header a, Invalid_header b
    | Invalid_span a, Invalid_span b
    | Invalid_anchor a, Invalid_anchor b ->
        String.compare a b
    | Stale_item, Stale_item -> 0
    | _ -> 0

let equal a b =
  equal_kind a.kind b.kind
  &&
  match (a.span, b.span) with
  | None, None -> true
  | Some a, Some b -> Span.equal a b
  | _ -> false

let compare_option compare a b =
  match (a, b) with
  | None, None -> 0
  | None, Some _ -> -1
  | Some _, None -> 1
  | Some a, Some b -> compare a b

let compare a b =
  let c = compare_kind a.kind b.kind in
  if c <> 0 then c else compare_option Span.compare a.span b.span

let pp_kind ppf = function
  | Invalid_handle s -> Format.fprintf ppf "invalid handle %S" s
  | Invalid_status s -> Format.fprintf ppf "invalid status %S" s
  | Invalid_priority s -> Format.fprintf ppf "invalid priority %S" s
  | Invalid_header s -> Format.fprintf ppf "invalid CR header: %s" s
  | Invalid_span s -> Format.fprintf ppf "invalid source span: %s" s
  | Invalid_anchor s -> Format.fprintf ppf "invalid source anchor: %s" s
  | Stale_item -> Format.pp_print_string ppf "stale CR item"

let pp ppf t =
  match t.span with
  | None -> pp_kind ppf t.kind
  | Some span -> Format.fprintf ppf "%a at %a" pp_kind t.kind Span.pp span
