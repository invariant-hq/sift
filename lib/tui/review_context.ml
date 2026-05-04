type line = { side : Sift_review.Scope.side; number : Sift_review.Scope.line }
type cr = { index : int; item : Sift_crs.Item.t }

type t = {
  review : Sift_review.t;
  cursor : Sift_review.Cursor.t;
  scope : Sift_review.Scope.t option;
  cr : cr option;
  file : Sift_diff.File.t option;
  path : string option;
  line : line option;
}

let files review = Sift_feature.files (Sift_review.feature review)

let file_at review index =
  if index < 0 then None else List.nth_opt (files review) index

let cr_at review index =
  if index < 0 then None
  else
    match Sift_review.cr_item review index with
    | None -> None
    | Some item -> Some { index; item }

let file_by_path review path =
  List.find_opt
    (fun file -> String.equal (Sift_diff.File.path file) path)
    (files review)

let path_of_scope scope = Option.bind scope Sift_review.Scope.path

let path_of_cr = function
  | None -> None
  | Some cr -> Some (Sift_crs.Item.path cr.item)

let path_of_file = function
  | None -> None
  | Some file -> Some (Sift_diff.File.path file)

let first_some a b = match a with Some _ -> a | None -> b

let line_of_scope scope =
  match Option.map Sift_review.Scope.view scope with
  | Some (Sift_review.Scope.Line (side, _, number)) -> Some { side; number }
  | Some
      ( Sift_review.Scope.Feature | Sift_review.Scope.File _
      | Sift_review.Scope.Hunk _ )
  | None ->
      None

let line_of_cr = function
  | None -> None
  | Some cr ->
      let span = Sift_crs.Item.span cr.item in
      Some
        { side = Sift_review.Scope.New; number = Sift_crs.Span.start_line span }

let v ~review ~selected_file ~selected_cr:_ =
  let cursor = Sift_review.cursor review in
  let scope = Sift_review.Cursor.selected_scope cursor in
  let cr =
    match Sift_review.Cursor.selected_cr cursor with
    | Some index -> cr_at review index
    | None -> None
  in
  let selected_file = Option.bind selected_file (file_at review) in
  let path =
    path_of_scope scope |> fun path ->
    first_some path (path_of_cr cr) |> fun path ->
    first_some path (path_of_file selected_file)
  in
  let file =
    match path with
    | Some path -> (
        match file_by_path review path with
        | Some _ as file -> file
        | None -> selected_file)
    | None -> selected_file
  in
  let line =
    match line_of_scope scope with
    | Some _ as line -> line
    | None -> line_of_cr cr
  in
  { review; cursor; scope; cr; file; path; line }

let review t = t.review
let cursor t = t.cursor
let scope t = t.scope
let cr t = t.cr
let file t = t.file
let path t = t.path
let line t = t.line
