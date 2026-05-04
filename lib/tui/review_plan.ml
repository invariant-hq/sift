let priority = function
  | Review_queue.Cr { valid = false; _ } -> Some 0
  | Hunk { unreviewed_count; _ } when unreviewed_count > 0 -> Some 1
  | File { unreviewed_count; _ } when unreviewed_count > 0 -> Some 2
  | Cr { valid = true; _ } -> Some 3
  | Feature { remaining; _ } when remaining > 0 -> Some 4
  | Feature _ | File _ | Hunk _ -> None

let first_outstanding ~review =
  let cursor = Sift_review.cursor review in
  let rows = Review_queue.rows ~review ~cursor () in
  let best =
    List.fold_left
      (fun best row ->
        match priority row with
        | None -> best
        | Some row_priority -> (
            match best with
            | None -> Some (row_priority, row)
            | Some (best_priority, _) when row_priority < best_priority ->
                Some (row_priority, row)
            | Some _ -> best))
      None rows
  in
  match best with
  | None -> None
  | Some (_, row) -> Some (Review_queue.cursor row)

let outstanding_indices rows =
  rows
  |> List.mapi (fun index row -> (index, row))
  |> List.filter_map (fun (index, row) ->
      match priority row with None -> None | Some _ -> Some index)
