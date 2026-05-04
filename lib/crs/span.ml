type t = {
  start_offset : int;
  stop_offset : int;
  start_line : int;
  start_col : int;
  stop_line : int;
  stop_col : int;
}

let valid ~start_offset ~stop_offset ~start_line ~start_col ~stop_line ~stop_col
    =
  start_offset >= 0
  && stop_offset >= start_offset
  && start_line >= 1 && stop_line >= 1 && start_col >= 0 && stop_col >= 0
  &&
  if stop_line = start_line then stop_col >= start_col
  else stop_line > start_line

let make ~start_offset ~stop_offset ~start_line ~start_col ~stop_line ~stop_col
    () =
  if
    valid ~start_offset ~stop_offset ~start_line ~start_col ~stop_line ~stop_col
  then
    Some
      { start_offset; stop_offset; start_line; start_col; stop_line; stop_col }
  else None

let v ~start_offset ~stop_offset ~start_line ~start_col ~stop_line ~stop_col ()
    =
  match
    make ~start_offset ~stop_offset ~start_line ~start_col ~stop_line ~stop_col
      ()
  with
  | Some t -> t
  | None -> invalid_arg "Sift_crs.Span.v"

let start_offset t = t.start_offset
let stop_offset t = t.stop_offset
let start_line t = t.start_line
let start_col t = t.start_col
let stop_line t = t.stop_line
let stop_col t = t.stop_col

let equal a b =
  a.start_offset = b.start_offset
  && a.stop_offset = b.stop_offset
  && a.start_line = b.start_line
  && a.start_col = b.start_col && a.stop_line = b.stop_line
  && a.stop_col = b.stop_col

let compare a b =
  let c = Int.compare a.start_offset b.start_offset in
  if c <> 0 then c
  else
    let c = Int.compare a.stop_offset b.stop_offset in
    if c <> 0 then c
    else
      let c = Int.compare a.start_line b.start_line in
      if c <> 0 then c
      else
        let c = Int.compare a.start_col b.start_col in
        if c <> 0 then c
        else
          let c = Int.compare a.stop_line b.stop_line in
          if c <> 0 then c else Int.compare a.stop_col b.stop_col

let pp ppf t =
  Format.fprintf ppf "%d:%d-%d:%d" t.start_line t.start_col t.stop_line
    t.stop_col
