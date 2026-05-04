module Version = Version
module Key = Key
module Record = Record
module Codec = Codec
module Error = Error
module Fs = Fs

type reviewed_unit = {
  mark : Record.mark;
  content_digest : Sift_crs.Digest.t option;
}

type t = {
  version : Version.t;
  key : Key.t;
  title : string option;
  content_digest : Sift_crs.Digest.t option;
  approval : Record.approval;
  marks : Record.mark list;
  reviewed_units : reviewed_unit list;
  cr_records : Record.cr_record list;
  cursor : Record.cursor option;
}

let rec list_equal equal a b =
  match (a, b) with
  | [], [] -> true
  | x :: xs, y :: ys -> equal x y && list_equal equal xs ys
  | [], _ :: _ | _ :: _, [] -> false

let rec list_compare compare a b =
  match (a, b) with
  | [], [] -> 0
  | [], _ :: _ -> -1
  | _ :: _, [] -> 1
  | x :: xs, y :: ys -> (
      match compare x y with 0 -> list_compare compare xs ys | n -> n)

let title_is_valid = function
  | None -> true
  | Some title -> not (String.equal title "")

let check_title title =
  if not (title_is_valid title) then
    invalid_arg "Sift_store.with_title: empty title"

let has_duplicate compare items =
  let sorted = List.sort compare items in
  let rec loop = function
    | first :: second :: rest ->
        Int.equal (compare first second) 0 || loop (second :: rest)
    | [] | [ _ ] -> false
  in
  loop sorted

let normalize_marks name marks =
  let marks = List.sort Record.compare_mark_identity marks in
  if has_duplicate Record.compare_mark_identity marks then
    invalid_arg ("Sift_store." ^ name ^ ": duplicate mark");
  marks

let cr_identity_compare a b =
  match Sift_crs.Digest.compare (Record.cr_digest a) (Record.cr_digest b) with
  | 0 ->
      Option.compare Record.compare_scope (Record.cr_scope a)
        (Record.cr_scope b)
  | n -> n

let normalize_cr_records_by_identity crs =
  let crs = List.sort cr_identity_compare crs in
  if has_duplicate cr_identity_compare crs then
    invalid_arg "Sift_store.with_cr_records: duplicate CR identity";
  crs

let empty ?(version = Version.current) ?title key =
  check_title title;
  {
    version;
    key;
    title;
    content_digest = None;
    approval = Pending;
    marks = [];
    reviewed_units = [];
    cr_records = [];
    cursor = None;
  }

let of_feature ?version ?namespace feature =
  empty ?version
    ?title:(Sift_feature.title feature)
    (Key.of_feature ?namespace feature)

let version t = t.version
let key t = t.key
let title t = t.title
let approval t = t.approval
let marks t = t.marks
let cr_records t = t.cr_records
let cursor t = t.cursor
let with_version t version = { t with version }

let with_title t title =
  check_title title;
  { t with title }

let with_approval t approval = { t with approval }
let with_marks t marks = { t with marks = normalize_marks "with_marks" marks }

let normalize_reviewed_units units =
  let compare_identity a b = Record.compare_mark_identity a.mark b.mark in
  let units = List.sort compare_identity units in
  if has_duplicate compare_identity units then
    invalid_arg "Sift_store.with_reviewed_units: duplicate reviewed unit";
  units

let with_reviewed_units t units =
  { t with reviewed_units = normalize_reviewed_units units }

let put_mark t mark =
  let marks =
    mark
    :: List.filter
         (fun existing ->
           Int.equal (Record.compare_mark_identity mark existing) 0 |> not)
         t.marks
  in
  with_marks t marks

let remove_mark t scope =
  {
    t with
    marks =
      List.filter
        (fun mark -> not (Record.equal_scope scope (Record.mark_scope mark)))
        t.marks;
  }

let with_cr_records t crs =
  { t with cr_records = normalize_cr_records_by_identity crs }

let put_cr_record t cr =
  let crs =
    cr
    :: List.filter
         (fun existing -> Int.equal (cr_identity_compare cr existing) 0 |> not)
         t.cr_records
  in
  with_cr_records t crs

let remove_cr_record t ~digest ~scope =
  let keep cr =
    not
      (Sift_crs.Digest.equal (Record.cr_digest cr) digest
      && Option.equal Record.equal_scope (Record.cr_scope cr) scope)
  in
  { t with cr_records = List.filter keep t.cr_records }

let with_cursor t cursor = { t with cursor }

let store_side_of_review = function
  | Sift_review.Scope.Old -> Record.Old
  | Sift_review.Scope.New -> Record.New

let review_side_of_store = function
  | Record.Old -> Sift_review.Scope.Old
  | Record.New -> Sift_review.Scope.New

let store_scope_of_review scope =
  match Sift_review.Scope.view scope with
  | Feature -> Record.feature
  | File path -> Record.file ~path
  | Hunk hunk ->
      Record.hunk ~path:hunk.path ~old_start:hunk.old_start
        ~old_count:hunk.old_count ~new_start:hunk.new_start
        ~new_count:hunk.new_count
  | Line (side, path, line) -> (
      let side = store_side_of_review side in
      match side with
      | Record.Old -> Record.old_line ~path ~line
      | Record.New -> Record.new_line ~path ~line)

let review_scope_of_store scope =
  match Record.scope_view scope with
  | Feature -> Sift_review.Scope.feature
  | File path -> Sift_review.Scope.file path
  | Hunk hunk ->
      Sift_review.Scope.hunk ~path:hunk.path ~old_start:hunk.old_start
        ~old_count:hunk.old_count ~new_start:hunk.new_start
        ~new_count:hunk.new_count
  | Line (side, path, line) -> (
      let side = review_side_of_store side in
      match side with
      | Sift_review.Scope.Old -> Sift_review.Scope.old_line ~path ~line
      | Sift_review.Scope.New -> Sift_review.Scope.new_line ~path ~line)

let store_approval_of_review = function
  | Sift_review.Approval.Pending -> Record.Pending
  | Sift_review.Approval.Approved -> Record.Approved
  | Sift_review.Approval.Seconded -> Record.Seconded

let review_approval_of_store = function
  | Record.Pending -> Sift_review.Approval.Pending
  | Record.Approved -> Sift_review.Approval.Approved
  | Record.Seconded -> Sift_review.Approval.Seconded

let store_mark_state_of_review = function
  | Sift_review.Mark.Reviewed -> Record.Reviewed
  | Sift_review.Mark.Unreviewed -> Record.Unreviewed

let review_mark_state_of_store = function
  | Record.Reviewed -> Sift_review.Mark.Reviewed
  | Record.Unreviewed -> Sift_review.Mark.Unreviewed

let store_mark_of_review mark =
  Record.mark
    ~scope:(store_scope_of_review (Sift_review.Mark.scope mark))
    ~state:(store_mark_state_of_review (Sift_review.Mark.state mark))

let review_mark_of_store mark =
  Sift_review.Mark.make
    (review_scope_of_store (Record.mark_scope mark))
    (review_mark_state_of_store (Record.mark_state mark))

let store_cursor_of_review cursor =
  match Sift_review.Cursor.target cursor with
  | Scope scope -> Record.cursor (Scope (store_scope_of_review scope))
  | Cr index -> Record.cursor (Cr index)

let review_cursor_of_store cursor =
  match Record.cursor_target cursor with
  | Scope scope -> Sift_review.Cursor.scope (review_scope_of_store scope)
  | Cr index -> Sift_review.Cursor.cr index

let digest_string s =
  let digest = Stdlib.Digest.string s |> Stdlib.Digest.to_hex in
  match Sift_crs.Digest.of_string digest with
  | Some digest -> digest
  | None -> assert false

let feature_content_digest feature =
  let base = Sift_feature.Revision.to_string (Sift_feature.base feature) in
  let tip = Sift_feature.Revision.to_string (Sift_feature.tip feature) in
  let diff = Format.asprintf "%a" Sift_diff.pp (Sift_feature.diff feature) in
  digest_string (String.concat "\000" [ base; tip; diff ])

let line_content_digest line =
  let prefix = Sift_diff.Line.prefix (Sift_diff.Line.kind line) in
  digest_string (String.make 1 prefix ^ Sift_diff.Line.text line)

let changed_line_scope ~path row =
  match Sift_diff.Line.kind row.Sift_diff.Hunk.line with
  | Sift_diff.Line.Context -> None
  | Sift_diff.Line.Removed -> (
      match row.old_line with
      | None -> None
      | Some line -> Some (Sift_review.Scope.old_line ~path ~line))
  | Sift_diff.Line.Added -> (
      match row.new_line with
      | None -> None
      | Some line -> Some (Sift_review.Scope.new_line ~path ~line))

let review_units feature =
  let units = ref [] in
  let add scope content_digest = units := (scope, content_digest) :: !units in
  List.iter
    (fun file ->
      let path = Sift_diff.File.path file in
      match Sift_diff.File.content file with
      | Binary -> add (Sift_review.Scope.file path) None
      | Text hunks ->
          List.iter
            (fun hunk ->
              List.iter
                (fun row ->
                  match changed_line_scope ~path row with
                  | None -> ()
                  | Some scope ->
                      add scope (Some (line_content_digest row.line)))
                (Sift_diff.Hunk.rows hunk))
            hunks)
    (Sift_feature.files feature);
  List.rev !units

let reviewed_units_of_review review =
  let add_if_reviewed units (scope, content_digest) =
    match Sift_review.effective_mark review scope with
    | Some mark when Sift_review.Mark.is_reviewed mark ->
        let mark = store_mark_of_review (Sift_review.Mark.reviewed scope) in
        { mark; content_digest } :: units
    | Some _ | None -> units
  in
  List.fold_left add_if_reviewed [] (review_units (Sift_review.feature review))

let content_digest_for_scope feature scope =
  List.find_map
    (fun (unit_scope, content_digest) ->
      if Sift_review.Scope.equal scope unit_scope then content_digest else None)
    (review_units feature)

let of_review ?namespace review =
  let feature = Sift_review.feature review in
  of_feature ?namespace feature |> fun store ->
  { store with content_digest = Some (feature_content_digest feature) }
  |> fun store ->
  with_approval store (store_approval_of_review (Sift_review.approval review))
  |> fun store ->
  with_marks store (List.map store_mark_of_review (Sift_review.marks review))
  |> fun store ->
  with_reviewed_units store (reviewed_units_of_review review) |> fun store ->
  with_cursor store (Some (store_cursor_of_review (Sift_review.cursor review)))

let apply_mark review mark =
  match Sift_review.set_mark review (review_mark_of_store mark) with
  | Ok review -> review
  | Error _ -> review

let apply_cursor review cursor =
  match Sift_review.set_cursor review (review_cursor_of_store cursor) with
  | Ok review -> review
  | Error _ -> review

let apply_reviewed_unit review (unit : reviewed_unit) =
  match unit.content_digest with
  | None -> review
  | Some stored_digest ->
      let scope = review_scope_of_store (Record.mark_scope unit.mark) in
      let current_digest =
        content_digest_for_scope (Sift_review.feature review) scope
      in
      if Option.equal Sift_crs.Digest.equal (Some stored_digest) current_digest
      then apply_mark review unit.mark
      else review

let apply_to_review t review =
  let content_matches =
    match t.content_digest with
    | None -> false
    | Some digest ->
        Sift_crs.Digest.equal digest
          (feature_content_digest (Sift_review.feature review))
  in
  let review =
    if content_matches then List.fold_left apply_mark review t.marks
    else List.fold_left apply_reviewed_unit review t.reviewed_units
  in
  let review =
    if content_matches then
      Sift_review.set_approval review (review_approval_of_store t.approval)
    else review
  in
  match t.cursor with
  | None -> review
  | Some cursor -> apply_cursor review cursor

let field name value = (name, value)
let string name value = field name (Codec.String value)
let int name value = field name (Codec.Int value)
let option encode = function None -> Codec.Null | Some value -> encode value
let encode_version version = Codec.Int (Version.to_int version)

let encode_key key =
  let fields =
    [
      string "base" (Sift_feature.Revision.to_string (Key.base key));
      string "tip" (Sift_feature.Revision.to_string (Key.tip key));
      field "namespace" (option (fun s -> Codec.String s) (Key.namespace key));
    ]
  in
  Codec.Fields fields

let encode_side = function
  | Record.Old -> Codec.String "old"
  | Record.New -> Codec.String "new"

let encode_approval = function
  | Record.Pending -> Codec.String "pending"
  | Record.Approved -> Codec.String "approved"
  | Record.Seconded -> Codec.String "seconded"

let encode_mark_state = function
  | Record.Reviewed -> Codec.String "reviewed"
  | Record.Unreviewed -> Codec.String "unreviewed"

let encode_hunk hunk =
  Codec.Fields
    [
      string "path" hunk.Record.path;
      int "old_start" hunk.old_start;
      int "old_count" hunk.old_count;
      int "new_start" hunk.new_start;
      int "new_count" hunk.new_count;
    ]

let encode_scope scope =
  match Record.scope_view scope with
  | Feature -> Codec.Fields [ string "kind" "feature" ]
  | File path -> Codec.Fields [ string "kind" "file"; string "path" path ]
  | Hunk hunk ->
      Codec.Fields [ string "kind" "hunk"; field "hunk" (encode_hunk hunk) ]
  | Line (side, path, line) ->
      Codec.Fields
        [
          string "kind" "line";
          field "side" (encode_side side);
          string "path" path;
          int "line" line;
        ]

let encode_mark mark =
  Codec.Fields
    [
      field "scope" (encode_scope (Record.mark_scope mark));
      field "state" (encode_mark_state (Record.mark_state mark));
    ]

let encode_digest digest = Codec.String (Sift_crs.Digest.to_string digest)

let encode_reviewed_unit unit =
  Codec.Fields
    [
      field "mark" (encode_mark unit.mark);
      field "content_digest" (option encode_digest unit.content_digest);
    ]

let encode_cr_state = function
  | Record.Open -> Codec.String "open"
  | Record.Addressed -> Codec.String "addressed"
  | Record.Accepted -> Codec.String "accepted"

let encode_cr_record cr =
  Codec.Fields
    [
      string "digest" (Sift_crs.Digest.to_string (Record.cr_digest cr));
      field "scope" (option encode_scope (Record.cr_scope cr));
      field "state" (encode_cr_state (Record.cr_state cr));
    ]

let encode_cursor_target = function
  | Record.Scope scope ->
      Codec.Fields [ string "kind" "scope"; field "scope" (encode_scope scope) ]
  | Record.Cr i -> Codec.Fields [ string "kind" "cr"; int "index" i ]

let encode_cursor cursor = encode_cursor_target (Record.cursor_target cursor)

let encode t =
  Codec.Fields
    [
      field "version" (encode_version t.version);
      field "key" (encode_key t.key);
      field "title" (option (fun s -> Codec.String s) t.title);
      field "content_digest" (option encode_digest t.content_digest);
      field "approval" (encode_approval t.approval);
      field "marks" (Codec.List (List.map encode_mark t.marks));
      field "reviewed_units"
        (Codec.List (List.map encode_reviewed_unit t.reviewed_units));
      field "cr_records" (Codec.List (List.map encode_cr_record t.cr_records));
      field "cursor" (option encode_cursor t.cursor);
    ]

let decode_error msg = Error (Error.Decode msg)

let fields = function
  | Codec.Fields fields ->
      let names = List.map fst fields in
      if has_duplicate String.compare names then decode_error "duplicate field"
      else Ok fields
  | _ -> decode_error "expected fields"

let find_field fields name =
  match List.assoc_opt name fields with
  | Some value -> Ok value
  | None -> decode_error ("missing field " ^ name)

let decode_string = function
  | Codec.String s -> Ok s
  | _ -> decode_error "expected string"

let decode_int = function
  | Codec.Int n -> Ok n
  | _ -> decode_error "expected int"

let decode_option decode = function
  | Codec.Null -> Ok None
  | value -> (
      match decode value with
      | Ok value -> Ok (Some value)
      | Error error -> Error error)

let decode_list decode = function
  | Codec.List values ->
      let rec loop acc = function
        | [] -> Ok (List.rev acc)
        | value :: rest -> (
            match decode value with
            | Error error -> Error error
            | Ok value -> loop (value :: acc) rest)
      in
      loop [] values
  | _ -> decode_error "expected list"

let required fields name decode =
  match find_field fields name with
  | Error error -> Error error
  | Ok value -> decode value

let optional fields name decode default =
  match List.assoc_opt name fields with
  | None -> Ok default
  | Some value -> decode value

let decode_version value =
  match decode_int value with
  | Error error -> Error error
  | Ok n -> Version.of_int n

let decode_revision s =
  try Ok (Sift_feature.Revision.v s)
  with Invalid_argument msg -> Error (Error.Invalid_key msg)

let decode_key value =
  match fields value with
  | Error error -> Error error
  | Ok fields -> (
      match
        ( required fields "base" decode_string,
          required fields "tip" decode_string,
          required fields "namespace" (decode_option decode_string) )
      with
      | Error error, _, _ | _, Error error, _ | _, _, Error error -> Error error
      | Ok base, Ok tip, Ok namespace -> (
          if Option.equal String.equal namespace (Some "") then
            Error (Error.Invalid_key "")
          else
            match (decode_revision base, decode_revision tip) with
            | Error error, _ | _, Error error -> Error error
            | Ok base, Ok tip -> Ok (Key.v ?namespace ~base ~tip ())))

let decode_side = function
  | Codec.String "old" -> Ok Record.Old
  | Codec.String "new" -> Ok Record.New
  | _ -> decode_error "expected side"

let decode_approval = function
  | Codec.String "pending" -> Ok Record.Pending
  | Codec.String "approved" -> Ok Record.Approved
  | Codec.String "seconded" -> Ok Record.Seconded
  | _ -> decode_error "expected approval"

let decode_mark_state = function
  | Codec.String "reviewed" -> Ok Record.Reviewed
  | Codec.String "unreviewed" -> Ok Record.Unreviewed
  | _ -> decode_error "expected mark state"

let range_error start count =
  let last = if count = 0 then start else start + count - 1 in
  Error (Error.Invalid_range { first = start; last })

let decode_hunk value =
  match fields value with
  | Error error -> Error error
  | Ok fields -> (
      match
        ( required fields "path" decode_string,
          required fields "old_start" decode_int,
          required fields "old_count" decode_int,
          required fields "new_start" decode_int,
          required fields "new_count" decode_int )
      with
      | Error error, _, _, _, _
      | _, Error error, _, _, _
      | _, _, Error error, _, _
      | _, _, _, Error error, _
      | _, _, _, _, Error error ->
          Error error
      | Ok path, Ok old_start, Ok old_count, Ok new_start, Ok new_count ->
          if String.equal path "" || not (Filename.is_relative path) then
            Error (Error.Invalid_path path)
          else if old_count < 0 || old_start < 0 then
            range_error old_start old_count
          else if new_count < 0 || new_start < 0 then
            range_error new_start new_count
          else if
            (old_count = 0 && old_start <> 0) || (old_count > 0 && old_start = 0)
          then range_error old_start old_count
          else if
            (new_count = 0 && new_start <> 0) || (new_count > 0 && new_start = 0)
          then range_error new_start new_count
          else
            Ok (Record.hunk ~path ~old_start ~old_count ~new_start ~new_count))

let decode_scope value =
  match fields value with
  | Error error -> Error error
  | Ok fields -> (
      match required fields "kind" decode_string with
      | Error error -> Error error
      | Ok "feature" -> Ok Record.feature
      | Ok "file" -> (
          match required fields "path" decode_string with
          | Error error -> Error error
          | Ok path ->
              if String.equal path "" || not (Filename.is_relative path) then
                Error (Error.Invalid_path path)
              else Ok (Record.file ~path))
      | Ok "hunk" -> required fields "hunk" decode_hunk
      | Ok "line" -> (
          match
            ( required fields "side" decode_side,
              required fields "path" decode_string,
              required fields "line" decode_int )
          with
          | Error error, _, _ | _, Error error, _ | _, _, Error error ->
              Error error
          | Ok side, Ok path, Ok line ->
              if String.equal path "" || not (Filename.is_relative path) then
                Error (Error.Invalid_path path)
              else if line < 1 then
                Error (Error.Invalid_range { first = line; last = line })
              else
                Ok
                  (match side with
                  | Old -> Record.old_line ~path ~line
                  | New -> Record.new_line ~path ~line))
      | Ok _ -> decode_error "unknown scope kind")

let decode_mark value =
  match fields value with
  | Error error -> Error error
  | Ok fields -> (
      match
        ( required fields "scope" decode_scope,
          required fields "state" decode_mark_state )
      with
      | Error error, _ | _, Error error -> Error error
      | Ok scope, Ok state -> Ok (Record.mark ~scope ~state))

let decode_digest = function
  | Codec.String digest -> (
      match Sift_crs.Digest.of_string digest with
      | Some digest -> Ok digest
      | None -> Error (Error.Decode "invalid digest"))
  | _ -> decode_error "expected digest"

let decode_reviewed_unit value =
  match fields value with
  | Error error -> Error error
  | Ok fields -> (
      match
        ( required fields "mark" decode_mark,
          required fields "content_digest" (decode_option decode_digest) )
      with
      | Error error, _ | _, Error error -> Error error
      | Ok mark, Ok content_digest -> Ok { mark; content_digest })

let decode_cr_state = function
  | Codec.String "open" -> Ok Record.Open
  | Codec.String "addressed" -> Ok Record.Addressed
  | Codec.String "accepted" -> Ok Record.Accepted
  | _ -> decode_error "expected CR state"

let decode_cr_record value =
  match fields value with
  | Error error -> Error error
  | Ok fields -> (
      match
        ( required fields "digest" decode_string,
          required fields "scope" (decode_option decode_scope),
          required fields "state" decode_cr_state )
      with
      | Error error, _, _ | _, Error error, _ | _, _, Error error -> Error error
      | Ok digest, Ok scope, Ok state -> (
          match Sift_crs.Digest.of_string digest with
          | None -> Error (Error.Decode "invalid CR digest")
          | Some digest -> Ok (Record.cr_record ?scope ~digest ~state ())))

let decode_cursor value =
  match fields value with
  | Error error -> Error error
  | Ok fields -> (
      match required fields "kind" decode_string with
      | Error error -> Error error
      | Ok "scope" -> (
          match required fields "scope" decode_scope with
          | Error error -> Error error
          | Ok scope -> Ok (Record.cursor (Record.Scope scope)))
      | Ok "cr" -> (
          match required fields "index" decode_int with
          | Error error -> Error error
          | Ok index ->
              if index < 0 then Error (Error.Decode "negative CR cursor")
              else Ok (Record.cursor (Record.Cr index)))
      | Ok _ -> decode_error "unknown cursor kind")

let decode value =
  match fields value with
  | Error error -> Error error
  | Ok fields -> (
      match
        ( required fields "version" decode_version,
          required fields "key" decode_key,
          required fields "title" (decode_option decode_string),
          optional fields "content_digest" (decode_option decode_digest) None,
          required fields "approval" decode_approval,
          required fields "marks" (decode_list decode_mark),
          optional fields "reviewed_units" (decode_list decode_reviewed_unit) [],
          required fields "cr_records" (decode_list decode_cr_record),
          required fields "cursor" (decode_option decode_cursor) )
      with
      | Error error, _, _, _, _, _, _, _, _
      | _, Error error, _, _, _, _, _, _, _
      | _, _, Error error, _, _, _, _, _, _
      | _, _, _, Error error, _, _, _, _, _
      | _, _, _, _, Error error, _, _, _, _
      | _, _, _, _, _, Error error, _, _, _
      | _, _, _, _, _, _, Error error, _, _
      | _, _, _, _, _, _, _, Error error, _
      | _, _, _, _, _, _, _, _, Error error ->
          Error error
      | ( Ok version,
          Ok key,
          Ok title,
          Ok content_digest,
          Ok approval,
          Ok marks,
          Ok reviewed_units,
          Ok crs,
          Ok cursor ) ->
          if Option.equal String.equal title (Some "") then
            Error (Error.Decode "empty title")
          else if has_duplicate Record.compare_mark_identity marks then
            Error Error.Duplicate_mark
          else if
            has_duplicate
              (fun a b -> Record.compare_mark_identity a.mark b.mark)
              reviewed_units
          then Error Error.Duplicate_mark
          else if has_duplicate cr_identity_compare crs then
            Error Error.Duplicate_cr
          else
            Ok
              {
                version;
                key;
                title;
                content_digest;
                approval;
                marks = List.sort Record.compare_mark_identity marks;
                reviewed_units =
                  List.sort
                    (fun a b -> Record.compare_mark_identity a.mark b.mark)
                    reviewed_units;
                cr_records = List.sort cr_identity_compare crs;
                cursor;
              })

let codec = Codec.make ~encode ~decode

let equal a b =
  Version.equal a.version b.version
  && Key.equal a.key b.key
  && Option.equal String.equal a.title b.title
  && Option.equal Sift_crs.Digest.equal a.content_digest b.content_digest
  && Record.equal_approval a.approval b.approval
  && list_equal Record.equal_mark a.marks b.marks
  && list_equal
       (fun a b ->
         Record.equal_mark a.mark b.mark
         && Option.equal Sift_crs.Digest.equal a.content_digest b.content_digest)
       a.reviewed_units b.reviewed_units
  && list_equal Record.equal_cr_record a.cr_records b.cr_records
  && Option.equal Record.equal_cursor a.cursor b.cursor

let compare a b =
  match Key.compare a.key b.key with
  | 0 -> (
      match Version.compare a.version b.version with
      | 0 -> (
          match Option.compare String.compare a.title b.title with
          | 0 -> (
              match
                Option.compare Sift_crs.Digest.compare a.content_digest
                  b.content_digest
              with
              | 0 -> (
                  match Record.compare_approval a.approval b.approval with
                  | 0 -> (
                      match
                        list_compare Record.compare_mark a.marks b.marks
                      with
                      | 0 -> (
                          match
                            list_compare
                              (fun a b ->
                                match Record.compare_mark a.mark b.mark with
                                | 0 ->
                                    Option.compare Sift_crs.Digest.compare
                                      a.content_digest b.content_digest
                                | n -> n)
                              a.reviewed_units b.reviewed_units
                          with
                          | 0 -> (
                              match
                                list_compare Record.compare_cr_record
                                  a.cr_records b.cr_records
                              with
                              | 0 ->
                                  Option.compare Record.compare_cursor a.cursor
                                    b.cursor
                              | n -> n)
                          | n -> n)
                      | n -> n)
                  | n -> n)
              | n -> n)
          | n -> n)
      | n -> n)
  | n -> n

let pp ppf t =
  Format.fprintf ppf "@[<hov 2>store %a v%a %d marks %d CRs@]" Key.pp t.key
    Version.pp t.version (List.length t.marks) (List.length t.cr_records)
