type op = Equal of string | Insert of string | Delete of string
type indexed_op = { op : op; old_before : int; new_before : int }

let split_lines s =
  let len = String.length s in
  let rec loop acc start i =
    if i = len then
      if start = len then List.rev acc
      else List.rev (String.sub s start (len - start) :: acc)
    else if Char.equal s.[i] '\n' then
      let line = String.sub s start (i - start) in
      loop (line :: acc) (i + 1) (i + 1)
    else loop acc start (i + 1)
  in
  loop [] 0 0

let lcs_table old_lines new_lines =
  let old = Array.of_list old_lines in
  let new_ = Array.of_list new_lines in
  let old_len = Array.length old in
  let new_len = Array.length new_ in
  let table = Array.make_matrix (old_len + 1) (new_len + 1) 0 in
  for i = old_len - 1 downto 0 do
    for j = new_len - 1 downto 0 do
      if String.equal old.(i) new_.(j) then
        table.(i).(j) <- table.(i + 1).(j + 1) + 1
      else table.(i).(j) <- max table.(i + 1).(j) table.(i).(j + 1)
    done
  done;
  (old, new_, table)

let edit_script old_lines new_lines =
  let old, new_, table = lcs_table old_lines new_lines in
  let old_len = Array.length old in
  let new_len = Array.length new_ in
  let rec loop acc i j =
    if i = old_len && j = new_len then List.rev acc
    else if i = old_len then loop (Insert new_.(j) :: acc) i (j + 1)
    else if j = new_len then loop (Delete old.(i) :: acc) (i + 1) j
    else if String.equal old.(i) new_.(j) then
      loop (Equal old.(i) :: acc) (i + 1) (j + 1)
    else if table.(i + 1).(j) >= table.(i).(j + 1) then
      loop (Delete old.(i) :: acc) (i + 1) j
    else loop (Insert new_.(j) :: acc) i (j + 1)
  in
  loop [] 0 0

let indexed_ops ops =
  let old_line = ref 1 in
  let new_line = ref 1 in
  let index op =
    let indexed = { op; old_before = !old_line; new_before = !new_line } in
    (match op with
    | Equal _ ->
        incr old_line;
        incr new_line
    | Delete _ -> incr old_line
    | Insert _ -> incr new_line);
    indexed
  in
  Array.of_list (List.map index ops)

let is_change = function Equal _ -> false | Insert _ | Delete _ -> true

let change_windows ~context ops =
  let len = Array.length ops in
  let rec skip_equal i =
    if i >= len || is_change ops.(i).op then i else skip_equal (i + 1)
  in
  let include_context_left i =
    let rec loop remaining pos =
      if remaining = 0 || pos = 0 || is_change ops.(pos - 1).op then pos
      else loop (remaining - 1) (pos - 1)
    in
    loop context i
  in
  let include_context_right i =
    let rec loop remaining pos =
      if remaining = 0 || pos + 1 >= len || is_change ops.(pos + 1).op then pos
      else loop (remaining - 1) (pos + 1)
    in
    loop context i
  in
  let rec collect acc i =
    let i = skip_equal i in
    if i >= len then List.rev acc
    else
      let first = i in
      let rec run_end j =
        if j + 1 < len && is_change ops.(j + 1).op then run_end (j + 1) else j
      in
      let last = run_end i in
      collect
        ((include_context_left first, include_context_right last) :: acc)
        (last + 1)
  in
  let rec merge acc = function
    | [] -> List.rev acc
    | (start, stop) :: rest -> (
        match acc with
        | (prev_start, prev_stop) :: acc_rest when start <= prev_stop + 1 ->
            merge ((prev_start, max prev_stop stop) :: acc_rest) rest
        | _ -> merge ((start, stop) :: acc) rest)
  in
  merge [] (collect [] 0)

let line_of_op = function
  | Equal text -> Line.make Context ~text
  | Insert text -> Line.make Added ~text
  | Delete text -> Line.make Removed ~text

let hunk_of_window ops (start, stop) =
  let lines = ref [] in
  let old_start = ref None in
  let new_start = ref None in
  let old_count = ref 0 in
  let new_count = ref 0 in
  for i = start to stop do
    let indexed = ops.(i) in
    lines := line_of_op indexed.op :: !lines;
    match indexed.op with
    | Equal _ ->
        if Option.is_none !old_start then old_start := Some indexed.old_before;
        if Option.is_none !new_start then new_start := Some indexed.new_before;
        incr old_count;
        incr new_count
    | Delete _ ->
        if Option.is_none !old_start then old_start := Some indexed.old_before;
        incr old_count
    | Insert _ ->
        if Option.is_none !new_start then new_start := Some indexed.new_before;
        incr new_count
  done;
  let first = ops.(start) in
  let old_start =
    match !old_start with Some line -> line | None -> first.old_before - 1
  in
  let new_start =
    match !new_start with Some line -> line | None -> first.new_before - 1
  in
  Hunk.v ~old_start ~old_count:!old_count ~new_start ~new_count:!new_count
    (List.rev !lines)

let hunks ?(context = 3) ~old_text ~new_text () =
  if context < 0 then invalid_arg "Sift_diff.Compute.hunks";
  if String.equal old_text new_text then []
  else
    let old_lines = split_lines old_text in
    let new_lines = split_lines new_text in
    let ops = indexed_ops (edit_script old_lines new_lines) in
    List.map (hunk_of_window ops) (change_windows ~context ops)

let file ?context ?old_path ?new_path ~old_text ~new_text () =
  let hunks = hunks ?context ~old_text ~new_text () in
  let status =
    match (old_path, new_path) with
    | Some old_path, Some new_path ->
        if String.equal old_path new_path then
          if List.is_empty hunks then None else Some File.Modified
        else Some File.Renamed
    | None, Some _ -> Some File.Added
    | Some _, None -> Some File.Deleted
    | None, None -> if List.is_empty hunks then None else Some File.Modified
  in
  match status with
  | None -> None
  | Some status -> Some (File.v ?old_path ?new_path ~status (Text hunks))
