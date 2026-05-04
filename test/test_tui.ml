open Windtrap
module T = Sift_tui
module R = Sift_review
module C = Sift_crs
module D = Sift_diff
module F = Sift_feature

module Render_harness = struct
  module Renderer = Mosaic_ui.Renderer
  module Renderable = Mosaic_ui.Renderable
  module Reconciler = Mosaic.Reconciler
  module Vnode = Mosaic_ui.Vnode
  module Grid = Matrix.Grid
  module Screen = Matrix.Screen

  type viewport = { width : int; height : int }
  type output = { viewport : viewport; text : string; lines : string list }
  type app = { renderer : Renderer.t; messages : T.msg list ref }

  let viewport ~width ~height = { width; height }

  let rstrip s =
    let i = ref (String.length s - 1) in
    while !i >= 0 && Char.equal s.[!i] ' ' do
      decr i
    done;
    if !i < 0 then "" else String.sub s 0 (!i + 1)

  let grid_to_text grid =
    let width = Grid.width grid in
    let height = Grid.height grid in
    let line = Buffer.create width in
    let text = Buffer.create (width * height) in
    for y = 0 to height - 1 do
      Buffer.clear line;
      for x = 0 to width - 1 do
        let index = (y * width) + x in
        if not (Grid.is_continuation grid index) then
          let cell = Grid.get_text grid index in
          Buffer.add_string line (if String.equal cell "" then " " else cell)
      done;
      Buffer.add_string text (rstrip (Buffer.contents line));
      if y + 1 < height then Buffer.add_char text '\n'
    done;
    Buffer.contents text

  let set_viewport renderer { width; height } =
    let root = Renderer.root renderer in
    let style =
      Renderable.style root
      |> Toffee.Style.set_width
           (Toffee.Style.Dimension.length (Float.of_int width))
      |> Toffee.Style.set_height
           (Toffee.Style.Dimension.length (Float.of_int height))
    in
    Renderable.set_style root style

  let render_view viewport view =
    let renderer = Renderer.create () in
    set_viewport renderer viewport;
    let reconciler = Reconciler.create ~container:(Renderer.root renderer) in
    Reconciler.render reconciler (Vnode.map ignore view);
    ignore
      (Renderer.render_frame_until_settled renderer ~width:viewport.width
         ~height:viewport.height ~delta:0.
        : Renderer.settle_result);
    let text = grid_to_text (Screen.next_grid (Renderer.screen renderer)) in
    let lines = String.split_on_char '\n' text in
    { viewport; text; lines }

  let render_model ~width ~height model =
    let viewport = viewport ~width ~height in
    render_view viewport (T.view model)

  let render_interactive_model ~width ~height model =
    let viewport = viewport ~width ~height in
    let renderer = Renderer.create () in
    set_viewport renderer viewport;
    let reconciler = Reconciler.create ~container:(Renderer.root renderer) in
    let messages = ref [] in
    let dispatch = function
      | None -> ()
      | Some message -> messages := !messages @ [ message ]
    in
    Reconciler.render reconciler (Vnode.map dispatch (T.view model));
    ignore
      (Renderer.render_frame_until_settled renderer ~width ~height ~delta:0.
        : Renderer.settle_result);
    ignore (Renderer.render renderer : string);
    ignore (reconciler : Reconciler.t);
    { renderer; messages }

  let mouse_down ~x ~y =
    Matrix.Input.Mouse.make ~x ~y ~modifiers:Matrix.Input.Modifier.none
      (Matrix.Input.Mouse.Down { button = Matrix.Input.Mouse.Left })

  let mouse_up ~x ~y =
    Matrix.Input.Mouse.make ~x ~y ~modifiers:Matrix.Input.Modifier.none
      (Matrix.Input.Mouse.Up { button = Some Matrix.Input.Mouse.Left })

  let click app ~x ~y =
    Renderer.dispatch_mouse app.renderer (mouse_down ~x ~y);
    Renderer.dispatch_mouse app.renderer (mouse_up ~x ~y)

  let key_char char =
    Matrix.Input.Key.make
      (Matrix.Input.Key.Char (Uchar.of_char char))

  let key ?(ctrl = false) ?(shift = false) kind =
    let modifier = { Matrix.Input.Modifier.none with ctrl; shift } in
    Matrix.Input.Key.make ~modifier kind

  let type_text app text =
    String.iter
      (fun char -> ignore (Renderer.dispatch_key app.renderer (key_char char)))
      text

  let submit app =
    ignore
      (Renderer.dispatch_key app.renderer
         (key ~ctrl:true Matrix.Input.Key.Enter))

  let enter app =
    ignore (Renderer.dispatch_key app.renderer (key Matrix.Input.Key.Enter))

  let shift_enter app =
    ignore
      (Renderer.dispatch_key app.renderer
         (key ~shift:true Matrix.Input.Key.Enter))

  let messages app = !(app.messages)
  let clear_messages app = app.messages := []

  let contains output needle =
    let needle_len = String.length needle in
    let text_len = String.length output.text in
    if needle_len = 0 then true
    else
      let rec loop index =
        index + needle_len <= text_len
        && (String.equal (String.sub output.text index needle_len) needle
           || loop (index + 1))
      in
      loop 0

  let assert_contains ~msg output needle = is_true ~msg (contains output needle)

  let assert_not_contains ~msg output needle =
    is_false ~msg (contains output needle)
end

let expect_ok ~msg pp = function
  | Ok x -> x
  | Error e -> failf "%s: expected Ok _, got %a" msg pp e

let expect_update_ok ~msg = function
  | model, command ->
      ignore (msg : string);
      let rec messages = function
        | Mosaic.Cmd.None | Quit | Set_title _ | Focus _ | Static_commit _
        | Static_clear ->
            []
        | Batch commands -> List.concat_map messages commands
        | Perform f ->
            let acc = ref [] in
            f (fun msg -> acc := msg :: !acc);
            List.rev !acc
      in
      (model, messages command)

let rec command_focuses id = function
  | Mosaic.Cmd.Focus focus_id -> String.equal id focus_id
  | Batch commands -> List.exists (command_focuses id) commands
  | None | Perform _ | Quit | Set_title _ | Static_commit _ | Static_clear ->
      false

let line kind text = D.Line.make kind ~text
let context text = line D.Line.Context text
let added text = line D.Line.Added text
let removed text = line D.Line.Removed text

let hunk ?(old_start = 1) ?(old_count = 1) ?(new_start = 1) ?(new_count = 1)
    lines =
  expect_ok ~msg:"hunk" D.Error.pp
    (D.Hunk.make ~old_start ~old_count ~new_start ~new_count lines)

let file ?old_path ?new_path ~status content =
  expect_ok ~msg:"file" D.Error.pp
    (D.File.make ?old_path ?new_path ~status content)

let revision = F.Revision.v

let feature files =
  F.v ~base:(revision "main") ~tip:(revision "tip") ~diff:(D.make files) ()

let titled_feature title files =
  F.v ~title ~base:(revision "main") ~tip:(revision "tip") ~diff:(D.make files)
    ()

let review ?(cr_items = []) files = R.v ~feature:(feature files) ~cr_items

let span ?(line = 1) () =
  C.Span.v ~start_offset:0 ~stop_offset:1 ~start_line:line ~start_col:0
    ~stop_line:line ~stop_col:1 ()

let handle s = expect_ok ~msg:("handle " ^ s) C.Error.pp (C.Handle.of_string s)

let comment ?status ?priority ?recipient ?(reporter = "alice") body =
  let recipient = Option.map handle recipient in
  let header =
    C.Header.make ?status ?priority ~reporter:(handle reporter) ?recipient ()
  in
  C.Comment.make ~header ~body

let cr_item ?status ?priority ?recipient ?reporter ?(body = "review this") ~path
    ~line raw =
  C.Item.make ~path ~syntax:C.Syntax.Ocaml_block ~span:(span ~line ()) ~raw
    (Ok (comment ?status ?priority ?recipient ?reporter body))

let invalid_cr_item ~path ~line raw =
  C.Item.make ~path ~syntax:C.Syntax.Ocaml_block ~span:(span ~line ()) ~raw
    (Error (C.Error.make (C.Error.Invalid_header "missing reporter")))

let text_file path hunks =
  file ~old_path:path ~new_path:path ~status:D.File.Modified (D.File.Text hunks)

let binary_file path =
  file ~old_path:path ~new_path:path ~status:D.File.Modified D.File.Binary

let source_with_anchor anchor_line anchor_text =
  String.concat "\n"
    (List.init 40 (fun index ->
         let line = index + 1 in
         if Int.equal line anchor_line then anchor_text
         else Printf.sprintf "let line_%02d = ()" line))
  ^ "\n"

let row_name = function
  | T.Queue.Feature _ -> "feature"
  | T.Queue.File { path; _ } -> "file:" ^ path
  | T.Queue.Hunk { path; hunk; _ } ->
      Printf.sprintf "hunk:%s:%d:%d" path hunk.old_start hunk.new_start
  | T.Queue.Cr { index; item; _ } ->
      Printf.sprintf "cr:%d:%s" index (C.Item.path item)

let selected_row rows =
  List.find_opt
    (function
      | T.Queue.Feature { selected; _ }
      | T.Queue.File { selected; _ }
      | T.Queue.Hunk { selected; _ }
      | T.Queue.Cr { selected; _ } ->
          selected)
    rows

let expect_row_names ~msg names rows =
  let actual = List.map row_name rows in
  equal ~msg (list string) names actual

let set_cursor cursor model =
  fst
    (expect_update_ok ~msg:"select cursor"
       (T.update (T.Select_cursor cursor) model))

let apply_messages ~msg model messages =
  List.fold_left
    (fun model message -> fst (expect_update_ok ~msg (T.update message model)))
    model messages

let apply_messages_with_events ~msg model messages =
  List.fold_left
    (fun (model, events) message ->
      let model, emitted = expect_update_ok ~msg (T.update message model) in
      (model, events @ emitted))
    (model, []) messages

let apply_messages_with_events_and_command ~msg model messages =
  List.fold_left
    (fun (model, command, events) message ->
      let next, next_command = T.update message model in
      let _, emitted = expect_update_ok ~msg (next, next_command) in
      (next, Mosaic.Cmd.batch [ command; next_command ], events @ emitted))
    (model, Mosaic.Cmd.none, []) messages

let expect_selected_scope ~msg expected model =
  match R.Cursor.selected_scope (T.cursor model) with
  | Some scope -> is_true ~msg (R.Scope.equal scope expected)
  | None -> failf "%s: expected scope cursor" msg

let expect_current_scope ~msg expected model =
  match T.current_scope model with
  | Some scope -> is_true ~msg (R.Scope.equal scope expected)
  | None -> failf "%s: expected current scope" msg

let click_until_current_scope model expected app ~x0 ~x1 ~y0 ~y1 =
  let clicked = ref None in
  let selected_model = ref model in
  for y = y0 to y1 do
    for x = x0 to x1 do
      if Option.is_none !clicked then begin
        Render_harness.clear_messages app;
        Render_harness.click app ~x ~y;
        let model =
          apply_messages ~msg:"apply diff click" model
            (Render_harness.messages app)
        in
        match T.current_scope model with
        | Some scope when R.Scope.equal scope expected ->
            clicked := Some (x, y);
            selected_model := model
        | Some _ | None -> ()
      end
    done
  done;
  Option.map (fun point -> (point, !selected_model)) !clicked

let resize_model ~width ~height model =
  fst
    (expect_update_ok ~msg:"resize" (T.update (T.Resize (width, height)) model))

let key_char ?(shift = false) char =
  let modifier =
    if shift then { Matrix.Input.Modifier.none with shift = true }
    else Matrix.Input.Modifier.none
  in
  Mosaic.Event.Key.of_input
    (Matrix.Input.Key.make ~modifier
       (Matrix.Input.Key.Char (Uchar.of_char char)))

let key kind = Mosaic.Event.Key.of_input (Matrix.Input.Key.make kind)

let expect_no_patch ~msg model =
  match T.current_patch model with
  | None -> ()
  | Some _ -> failf "%s: expected no patch" msg

let expect_refresh_notice ~msg expected model =
  match T.last_refresh_notice model with
  | None -> failf "%s: expected refresh notice" msg
  | Some notice ->
      equal ~msg string expected
        (Format.asprintf "%a" T.Refresh_notice.pp notice)

let diff_tests =
  [
    test "current patch follows the selected file scope" (fun () ->
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let path = "lib/core.ml" in
        let model = T.make (review [ text_file path [ hunk ] ]) in
        let model = set_cursor (R.Cursor.scope (R.Scope.file path)) model in
        match T.current_patch model with
        | None -> failf "expected a text patch"
        | Some patch ->
            is_false ~msg:"patch has rows" (Mosaic.Diff.Patch.is_empty patch));
    test "current patch is absent for binary files" (fun () ->
        let path = "assets/logo.bin" in
        let model = T.make (review [ binary_file path ]) in
        let model = set_cursor (R.Cursor.scope (R.Scope.file path)) model in
        expect_no_patch ~msg:"binary patch" model);
    test "current patch is absent for empty text diffs" (fun () ->
        let path = "lib/empty.ml" in
        let model = T.make (review [ text_file path [] ]) in
        let model = set_cursor (R.Cursor.scope (R.Scope.file path)) model in
        expect_no_patch ~msg:"empty patch" model);
    test "CR cursor maps the diff pane to the CR file" (fun () ->
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let cr_items =
          [ cr_item ~path:"lib/target.ml" ~line:1 "(* CR alice: review *)" ]
        in
        let model =
          T.make
            (review ~cr_items
               [
                 binary_file "assets/logo.bin";
                 text_file "lib/target.ml" [ hunk ];
               ])
        in
        let model = set_cursor (R.Cursor.cr 0) model in
        match T.current_patch model with
        | None -> failf "expected CR cursor to select the CR file patch"
        | Some patch ->
            is_false ~msg:"CR patch has rows" (Mosaic.Diff.Patch.is_empty patch));
    test "clicking a diff line selects its review scope" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let model =
          T.make (review [ text_file path [ hunk ] ])
          |> set_cursor (R.Cursor.scope (R.Scope.file path))
        in
        let app =
          Render_harness.render_interactive_model ~width:120 ~height:20 model
        in
        let expected = R.Scope.new_line ~path ~line:1 in
        let clicked =
          click_until_current_scope model expected app ~x0:37 ~x1:78 ~y0:3
            ~y1:8
        in
        let model =
          match clicked with
          | Some (_, model) -> model
          | None -> failf "expected diff click to select line scope"
        in
        expect_current_scope ~msg:"first diff click selects line" expected
          model);
    test "clicking an added-only file selects a line, not its hunk" (fun () ->
        let path = "lib/new.ml" in
        let hunk =
          hunk ~old_start:0 ~old_count:0 ~new_start:1 ~new_count:3
            [ added "let a = 1"; added "let b = 2"; added "let c = 3" ]
        in
        let hunk_scope = R.Scope.of_hunk ~path hunk in
        let model =
          T.make (review [ text_file path [ hunk ] ])
          |> set_cursor (R.Cursor.scope hunk_scope)
        in
        let app =
          Render_harness.render_interactive_model ~width:120 ~height:20 model
        in
        let expected = R.Scope.new_line ~path ~line:2 in
        let clicked =
          click_until_current_scope model expected app ~x0:37 ~x1:78 ~y0:3
            ~y1:9
        in
        let model =
          match clicked with
          | Some (_, model) -> model
          | None -> failf "expected added-file click to select a line scope"
        in
        expect_current_scope ~msg:"first added-file click selects line"
          expected model);
  ]

let two_file_review () =
  let hunk_a =
    hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
      [ removed "let a = 1"; added "let a = 2" ]
  in
  let hunk_b =
    hunk ~old_start:10 ~old_count:1 ~new_start:20 ~new_count:1
      [ removed "let b = 1"; added "let b = 2" ]
  in
  review [ text_file "lib/a.ml" [ hunk_a ]; text_file "lib/b.ml" [ hunk_b ] ]

let queue_tests =
  [
    test "queue collapses hunks until a file is current" (fun () ->
        let rows = T.queue_rows (T.make (two_file_review ())) in
        expect_row_names ~msg:"queue order"
          [ "feature"; "file:lib/a.ml"; "hunk:lib/a.ml:1:1"; "file:lib/b.ml" ]
          rows);
    test "feature row carries approval state" (fun () ->
        let review = R.set_approval (two_file_review ()) R.Approval.Seconded in
        match T.queue_rows (T.make review) with
        | T.Queue.Feature { approval; _ } :: _ ->
            is_true ~msg:"seconded approval"
              (R.Approval.equal approval R.Approval.Seconded)
        | _ -> failf "expected feature row");
    test "queue expands hunks for the current file" (fun () ->
        let model =
          T.make (two_file_review ())
          |> set_cursor (R.Cursor.scope (R.Scope.file "lib/b.ml"))
        in
        let rows = T.queue_rows model in
        expect_row_names ~msg:"queue order"
          [ "feature"; "file:lib/a.ml"; "file:lib/b.ml"; "hunk:lib/b.ml:10:20" ]
          rows);
    test "line cursor selects its containing hunk row" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:10 ~old_count:1 ~new_start:20 ~new_count:1
            [ removed "let x = old"; added "let x = new" ]
        in
        let review = review [ text_file path [ hunk ] ] in
        let cursor = R.Cursor.scope (R.Scope.new_line ~path ~line:20) in
        let rows = T.queue_rows (set_cursor cursor (T.make review)) in
        match selected_row rows with
        | Some (T.Queue.Hunk { path = selected_path; hunk; _ }) ->
            equal ~msg:"selected hunk path" string path selected_path;
            equal ~msg:"selected hunk new start" int 20 hunk.new_start
        | Some row -> failf "expected selected hunk row, got %s" (row_name row)
        | None -> failf "expected a selected queue row");
    test "queue hunk selection keeps the hunk scope" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:39 ~old_count:3 ~new_start:39 ~new_count:3
            [
              context "before";
              removed "let x = old";
              added "let x = new";
              context "after";
            ]
        in
        let expected = R.Scope.of_hunk ~path hunk in
        let model = T.make (review [ text_file path [ hunk ] ]) in
        let model, _events =
          expect_update_ok ~msg:"select queue hunk"
            (T.update (T.Select_queue 2) model)
        in
        expect_selected_scope ~msg:"queue hunk selection" expected model);
    test "queue rows summarize unreviewed units and CRs" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let review =
          review
            ~cr_items:[ cr_item ~path ~line:1 "(* CR alice: review *)" ]
            [ text_file path [ hunk ] ]
        in
        let review =
          expect_ok ~msg:"mark reviewed" R.Error.pp
            (R.mark_reviewed review (R.Scope.new_line ~path ~line:1))
        in
        let rows =
          T.queue_rows
            (set_cursor (R.Cursor.scope (R.Scope.file path)) (T.make review))
        in
        match rows with
        | _
          :: T.Queue.File { cr_count; unreviewed_count; _ }
          :: T.Queue.Hunk
               {
                 cr_count = hunk_cr_count;
                 unreviewed_count = hunk_unreviewed_count;
                 _;
               }
          :: _ ->
            equal ~msg:"file CR count" int 1 cr_count;
            equal ~msg:"file unreviewed count" int 1 unreviewed_count;
            equal ~msg:"hunk CR count" int 1 hunk_cr_count;
            equal ~msg:"hunk unreviewed count" int 1 hunk_unreviewed_count
        | _ -> failf "unexpected queue shape");
    test "queue shows CRs for the expanded file" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let review =
          review
            ~cr_items:[ cr_item ~path ~line:1 "(* CR alice: review *)" ]
            [ text_file path [ hunk ] ]
        in
        let rows =
          T.queue_rows
            (set_cursor (R.Cursor.scope (R.Scope.file path)) (T.make review))
        in
        expect_row_names ~msg:"queue order"
          [
            "feature";
            "file:lib/core.ml";
            "hunk:lib/core.ml:1:1";
            "cr:0:lib/core.ml";
          ]
          rows);
    test "queue nests CRs below their containing hunk" (fun () ->
        let path = "lib/core.ml" in
        let first =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let a = old"; added "let a = new" ]
        in
        let second =
          hunk ~old_start:10 ~old_count:1 ~new_start:10 ~new_count:1
            [ removed "let b = old"; added "let b = new" ]
        in
        let review =
          review
            ~cr_items:[ cr_item ~path ~line:1 "(* CR alice: review *)" ]
            [ text_file path [ first; second ] ]
        in
        let rows =
          T.queue_rows
            (set_cursor (R.Cursor.scope (R.Scope.file path)) (T.make review))
        in
        expect_row_names ~msg:"queue order"
          [
            "feature";
            "file:lib/core.ml";
            "hunk:lib/core.ml:1:1";
            "cr:0:lib/core.ml";
            "hunk:lib/core.ml:10:10";
          ]
          rows;
        match List.nth_opt rows 3 with
        | Some (T.Queue.Cr { nesting = T.Queue.Hunk_level; _ }) -> ()
        | Some row -> failf "expected nested CR row, got %s" (row_name row)
        | None -> failf "expected nested CR row");
    test "queue keeps unmatched file CRs below the file hunks" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let review =
          review
            ~cr_items:[ cr_item ~path ~line:30 "(* CR alice: review *)" ]
            [ text_file path [ hunk ] ]
        in
        let rows =
          T.queue_rows
            (set_cursor (R.Cursor.scope (R.Scope.file path)) (T.make review))
        in
        expect_row_names ~msg:"queue order"
          [
            "feature";
            "file:lib/core.ml";
            "hunk:lib/core.ml:1:1";
            "cr:0:lib/core.ml";
          ]
          rows;
        match List.nth_opt rows 3 with
        | Some (T.Queue.Cr { nesting = T.Queue.File_level; _ }) -> ()
        | Some row -> failf "expected file-level CR row, got %s" (row_name row)
        | None -> failf "expected file-level CR row");
    test "file-level CR rows render as file children with line anchors"
      (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let review =
          review
            ~cr_items:[ cr_item ~path ~line:30 "(* CR alice: review *)" ]
            [ text_file path [ hunk ] ]
        in
        let model =
          T.make review
          |> set_cursor (R.Cursor.scope (R.Scope.file path))
          |> resize_model ~width:140 ~height:36
        in
        let output = Render_harness.render_model ~width:140 ~height:36 model in
        Render_harness.assert_contains ~msg:"file row" output "lib/core.ml";
        Render_harness.assert_contains ~msg:"CR line anchor" output "CR line 30";
        Render_harness.assert_contains ~msg:"CR reporter" output "alice");
    test "cursor movement follows visible queue rows" (fun () ->
        let model = T.make (two_file_review ()) in
        is_true ~msg:"initial file cursor"
          (R.Cursor.equal (T.cursor model)
             (R.Cursor.scope (R.Scope.file "lib/a.ml")));
        let model, events =
          expect_update_ok ~msg:"move to expanded hunk"
            (T.update (T.Command (T.Move_cursor R.Cursor.Next)) model)
        in
        equal ~msg:"cursor move event count" int 1 (List.length events);
        (match events with
        | [ T.Review_changed review ] -> (
            match R.Cursor.selected_scope (R.cursor review) with
            | Some scope -> (
                match R.Scope.view scope with
                | R.Scope.Hunk hunk ->
                    equal ~msg:"event hunk path" string "lib/a.ml" hunk.path
                | _ -> failf "expected hunk cursor event")
            | None -> failf "expected scope cursor event")
        | _ -> failf "expected one review changed event");
        match R.Cursor.selected_scope (T.cursor model) with
        | Some scope -> (
            match R.Scope.view scope with
            | R.Scope.Hunk hunk ->
                equal ~msg:"hunk path" string "lib/a.ml" hunk.path
            | _ -> failf "expected hunk cursor")
        | None -> failf "expected scope cursor");
  ]

let comment_tests =
  [
    test "comment command opens a draft on the current scope" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let model =
          T.make (review [ text_file path [ hunk ] ])
          |> set_cursor (R.Cursor.scope (R.Scope.new_line ~path ~line:1))
        in
        let model, events =
          expect_update_ok ~msg:"add comment"
            (T.update (T.Command T.Add_comment) model)
        in
        equal ~msg:"no event before submit" int 0 (List.length events);
        match T.comment_composer model with
        | Some { T.scope; body } ->
            is_true ~msg:"draft scope"
              (R.Scope.equal scope (R.Scope.new_line ~path ~line:1));
            equal ~msg:"draft body" string "" body
        | None -> failf "expected open comment composer");
    test "comment submit emits a comment event" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let model =
          T.make (review [ text_file path [ hunk ] ])
          |> set_cursor (R.Cursor.scope (R.Scope.new_line ~path ~line:1))
        in
        let model, _ =
          expect_update_ok ~msg:"add comment"
            (T.update (T.Command T.Add_comment) model)
        in
        let app =
          Render_harness.render_interactive_model ~width:120 ~height:24 model
        in
        Render_harness.clear_messages app;
        Render_harness.type_text app " check this ";
        let model, _ =
          expect_update_ok ~msg:"type comment body"
            (List.fold_left
               (fun model message ->
                 fst (expect_update_ok ~msg:"composer input" (T.update message model)))
               model (Render_harness.messages app), Mosaic.Cmd.none)
        in
        let model, events =
          let app =
            Render_harness.render_interactive_model ~width:120 ~height:24 model
          in
          Render_harness.clear_messages app;
          Render_harness.submit app;
          apply_messages_with_events ~msg:"submit comment" model
            (Render_harness.messages app)
        in
        equal ~msg:"composer closed" (option string) None
          (Option.map (fun draft -> draft.T.body) (T.comment_composer model));
        match events with
        | [ T.Comment_submitted { scope; body } ] ->
            is_true ~msg:"submitted scope"
              (R.Scope.equal scope (R.Scope.new_line ~path ~line:1));
            equal ~msg:"submitted body" string "check this" body
        | _ -> failf "expected one comment submitted event");
    test "comment enter submits a comment event" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let model =
          T.make (review [ text_file path [ hunk ] ])
          |> set_cursor (R.Cursor.scope (R.Scope.new_line ~path ~line:1))
        in
        let model, _ =
          expect_update_ok ~msg:"add comment"
            (T.update (T.Command T.Add_comment) model)
        in
        let app =
          Render_harness.render_interactive_model ~width:120 ~height:24 model
        in
        Render_harness.clear_messages app;
        Render_harness.type_text app "ship it";
        let model =
          apply_messages ~msg:"type comment body" model
            (Render_harness.messages app)
        in
        let app =
          Render_harness.render_interactive_model ~width:120 ~height:24 model
        in
        Render_harness.clear_messages app;
        Render_harness.enter app;
        let _model, events =
          apply_messages_with_events ~msg:"submit comment with enter" model
            (Render_harness.messages app)
        in
        match events with
        | [ T.Comment_submitted { body; _ } ] ->
            equal ~msg:"submitted body" string "ship it" body
        | _ -> failf "expected one comment submitted event");
    test "comment shift enter inserts a newline" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let model =
          T.make (review [ text_file path [ hunk ] ])
          |> set_cursor (R.Cursor.scope (R.Scope.new_line ~path ~line:1))
        in
        let model, _ =
          expect_update_ok ~msg:"add comment"
            (T.update (T.Command T.Add_comment) model)
        in
        let app =
          Render_harness.render_interactive_model ~width:120 ~height:24 model
        in
        Render_harness.clear_messages app;
        Render_harness.type_text app "first";
        Render_harness.shift_enter app;
        Render_harness.type_text app "second";
        let model =
          apply_messages ~msg:"type multiline comment" model
            (Render_harness.messages app)
        in
        match T.comment_composer model with
        | Some { T.body; _ } ->
            equal ~msg:"draft body" string "first\nsecond" body
        | None -> failf "expected open comment composer");
    test "comment submit restores diff focus" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let model =
          T.make (review [ text_file path [ hunk ] ])
          |> set_cursor (R.Cursor.scope (R.Scope.new_line ~path ~line:1))
        in
        let model =
          fst
            (expect_update_ok ~msg:"activate diff" (T.update T.Activate_diff model))
        in
        let model =
          fst
            (expect_update_ok ~msg:"add comment"
               (T.update (T.Command T.Add_comment) model))
        in
        let app =
          Render_harness.render_interactive_model ~width:120 ~height:24 model
        in
        Render_harness.clear_messages app;
        Render_harness.type_text app " check this ";
        let model =
          apply_messages ~msg:"type comment body" model
            (Render_harness.messages app)
        in
        let app =
          Render_harness.render_interactive_model ~width:120 ~height:24 model
        in
        Render_harness.clear_messages app;
        Render_harness.submit app;
        let _model, command, events =
          apply_messages_with_events_and_command ~msg:"submit comment" model
            (Render_harness.messages app)
        in
        is_true ~msg:"submit restores diff focus"
          (command_focuses "sift.diff" command);
        match events with
        | [ T.Comment_submitted _ ] -> ()
        | _ -> failf "expected one comment submitted event");
    test "empty comment submit is rejected" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let model =
          T.make (review [ text_file path [ hunk ] ])
          |> set_cursor (R.Cursor.scope (R.Scope.new_line ~path ~line:1))
        in
        let model, _ =
          expect_update_ok ~msg:"add comment"
            (T.update (T.Command T.Add_comment) model)
        in
        let model, events =
          let app =
            Render_harness.render_interactive_model ~width:120 ~height:24 model
          in
          Render_harness.clear_messages app;
          Render_harness.submit app;
          apply_messages_with_events ~msg:"empty comment" model
            (Render_harness.messages app)
        in
        equal ~msg:"empty comment emits no messages" int 0 (List.length events);
        match T.last_error model with
        | Some error -> (
            match error with
            | T.Error.Empty_comment -> ()
            | error -> failf "expected Empty_comment, got %a" T.Error.pp error)
        | None -> failf "expected Empty_comment error");
    test "remove CR emits a runner event" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let model =
          T.make
            (review
               ~cr_items:[ cr_item ~path ~line:1 "(* CR alice: review *)" ]
               [ text_file path [ hunk ] ])
          |> set_cursor (R.Cursor.cr 0)
        in
        let _model, events =
          expect_update_ok ~msg:"remove CR"
            (T.update (T.Command T.Remove_cr) model)
        in
        match events with
        | [ T.Cr_removed { index; item } ] ->
            equal ~msg:"removed index" int 0 index;
            equal ~msg:"removed path" string path (C.Item.path item)
        | _ -> failf "expected one CR removal event");
    test "remove CR works from a highlighted CR source line" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let model =
          T.make
            (review
               ~cr_items:[ cr_item ~path ~line:1 "(* CR alice: review *)" ]
               [ text_file path [ hunk ] ])
          |> set_cursor (R.Cursor.scope (R.Scope.new_line ~path ~line:1))
        in
        let _model, events =
          expect_update_ok ~msg:"remove CR from line"
            (T.update (T.Command T.Remove_cr) model)
        in
        match events with
        | [ T.Cr_removed { index; item } ] ->
            equal ~msg:"removed index" int 0 index;
            equal ~msg:"removed path" string path (C.Item.path item)
        | _ -> failf "expected one CR removal event");
    test "edit CR opens a draft and emits a runner event" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let model =
          T.make
            (review
               ~cr_items:
                 [
                   cr_item ~path ~line:1 ~body:"old body"
                     "(* CR alice: old body *)";
                 ]
               [ text_file path [ hunk ] ])
          |> set_cursor (R.Cursor.cr 0)
        in
        let model, events =
          expect_update_ok ~msg:"edit CR" (T.update (T.Command T.Edit_cr) model)
        in
        equal ~msg:"no event before edit submit" int 0 (List.length events);
        (match T.comment_composer model with
        | Some { T.body; _ } ->
            equal ~msg:"edit draft body" string "old body" body
        | None -> failf "expected edit composer");
        let app =
          Render_harness.render_interactive_model ~width:120 ~height:24 model
        in
        Render_harness.clear_messages app;
        Render_harness.type_text app " replacement";
        let model, _events =
          expect_update_ok ~msg:"type CR edit"
            (List.fold_left
               (fun model message ->
                 fst (expect_update_ok ~msg:"composer edit input" (T.update message model)))
               model (Render_harness.messages app), Mosaic.Cmd.none)
        in
        let _model, events =
          let app =
            Render_harness.render_interactive_model ~width:120 ~height:24 model
          in
          Render_harness.clear_messages app;
          Render_harness.submit app;
          apply_messages_with_events ~msg:"submit CR edit" model
            (Render_harness.messages app)
        in
        match events with
        | [ T.Cr_edited ({ index; item }, body) ] ->
            equal ~msg:"edited index" int 0 index;
            equal ~msg:"edited path" string path (C.Item.path item);
            equal ~msg:"edited body" string "old body replacement" body
        | _ -> failf "expected one CR edit event");
    test "resolve CR emits a runner event" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let model =
          T.make
            (review
               ~cr_items:[ cr_item ~path ~line:1 "(* CR alice: review *)" ]
               [ text_file path [ hunk ] ])
          |> set_cursor (R.Cursor.cr 0)
        in
        let _model, events =
          expect_update_ok ~msg:"resolve CR"
            (T.update (T.Command T.Resolve_cr) model)
        in
        match events with
        | [ T.Cr_resolved { index; item } ] ->
            equal ~msg:"resolved index" int 0 index;
            equal ~msg:"resolved path" string path (C.Item.path item)
        | _ -> failf "expected one CR resolve event");
    test "comment action keys map to add edit remove and resolve" (fun () ->
        let model = T.make (two_file_review ()) in
        let command char =
          match T.message_of_key model (key_char char) with
          | Some (T.Command command) -> command
          | Some _ -> failf "expected command for %c" char
          | None -> failf "expected key binding for %c" char
        in
        (match command 'c' with T.Add_comment -> () | _ -> failf "expected c");
        (match command 'e' with T.Edit_cr -> () | _ -> failf "expected e");
        (match command 'd' with T.Remove_cr -> () | _ -> failf "expected d");
        match T.message_of_key model (key_char ~shift:true 'R') with
        | Some (T.Command T.Resolve_cr) -> ()
        | Some _ | None -> failf "expected R");
    test "replace review and select chooses the CR cursor atomically" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let next_review =
          review
            ~cr_items:[ cr_item ~path ~line:1 "(* CR alice: review *)" ]
            [ text_file path [ hunk ] ]
        in
        let model, _events =
          expect_update_ok ~msg:"replace and select"
            (T.update
               (T.Replace_review_and_select (next_review, R.Cursor.cr 0))
               (T.make (review [ text_file path [ hunk ] ])))
        in
        is_true ~msg:"CR cursor"
          (R.Cursor.equal (T.cursor model) (R.Cursor.cr 0)));
  ]

let refresh_tests =
  [
    test "refresh jump key maps to first new review unit command" (fun () ->
        let model = T.make (two_file_review ()) in
        match T.message_of_key model (key_char 'm') with
        | Some (T.Command T.Jump_first_new_review_unit) -> ()
        | Some _ | None -> failf "expected m to jump to first new unit");
    test "punctuation action keys use produced characters" (fun () ->
        let model = T.make (two_file_review ()) in
        (match T.message_of_key model (key_char '?') with
        | Some (T.Command T.Show_command_palette) -> ()
        | Some _ | None -> failf "expected ? to show command palette");
        (match T.message_of_key model (key_char ~shift:true '/') with
        | Some (T.Command T.Show_command_palette) -> ()
        | Some _ | None -> failf "expected shift+/ to show command palette");
        (match T.message_of_key model (key_char ':') with
        | Some (T.Command T.Show_command_palette) -> ()
        | Some _ | None -> failf "expected : to show command palette");
        match T.message_of_key model (key_char ~shift:true ';') with
        | Some (T.Command T.Show_command_palette) -> ()
        | Some _ | None -> failf "expected shift+; to show command palette");
    test "replace review reports review unit and CR deltas" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let model = T.make (review [ text_file path [ hunk ] ]) in
        let refreshed =
          R.refresh (T.review model)
            ~feature:
              (feature
                 [ text_file path [ hunk ]; binary_file "assets/logo.bin" ])
            ~cr_items:[ cr_item ~path ~line:1 "(* CR alice: review *)" ]
        in
        let model, events =
          expect_update_ok ~msg:"replace review"
            (T.update (T.Replace_review refreshed) model)
        in
        equal ~msg:"replace event count" int 0 (List.length events);
        expect_refresh_notice ~msg:"refresh notice"
          "refreshed: +1/-0 units, +1/-0 CRs" model);
    test "replace review reports removed CRs without host-computed notice"
      (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let review =
          review
            ~cr_items:[ cr_item ~path ~line:1 "(* CR alice: review *)" ]
            [ text_file path [ hunk ] ]
        in
        let model = T.make review in
        let refreshed =
          R.refresh review ~feature:(R.feature review) ~cr_items:[]
        in
        let model, _events =
          expect_update_ok ~msg:"replace review"
            (T.update (T.Replace_review refreshed) model)
        in
        expect_refresh_notice ~msg:"removed CR notice"
          "refreshed: +0/-0 units, +0/-1 CRs" model);
    test "replace review ignores context rows when deriving deltas" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:10 ~old_count:3 ~new_start:10 ~new_count:3
            [
              context "let before = 0";
              removed "let x = 1";
              added "let x = 2";
              context "let after = 3";
            ]
        in
        let review = review [ text_file path [ hunk ] ] in
        let model = T.make review in
        let refreshed =
          R.refresh review ~feature:(R.feature review)
            ~cr_items:[ cr_item ~path ~line:11 "(* CR alice: review *)" ]
        in
        let model, _events =
          expect_update_ok ~msg:"replace review"
            (T.update (T.Replace_review refreshed) model)
        in
        expect_refresh_notice ~msg:"context row notice"
          "refreshed: +0/-0 units, +1/-0 CRs" model);
    test "replace review preserves a still-valid cursor" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let scope = R.Scope.of_hunk ~path hunk in
        let model =
          T.make (review [ text_file path [ hunk ] ])
          |> set_cursor (R.Cursor.scope scope)
        in
        let refreshed =
          R.refresh (T.review model)
            ~feature:
              (feature
                 [ text_file path [ hunk ]; binary_file "assets/logo.bin" ])
            ~cr_items:[]
        in
        let model, _events =
          expect_update_ok ~msg:"replace review"
            (T.update (T.Replace_review refreshed) model)
        in
        is_true ~msg:"cursor preserved"
          (R.Cursor.equal (T.cursor model) (R.Cursor.scope scope)));
    test "jump first new review unit selects the first new hunk" (fun () ->
        let path = "lib/core.ml" in
        let old_hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let new_hunk =
          hunk ~old_start:10 ~old_count:1 ~new_start:10 ~new_count:1
            [ removed "let y = 1"; added "let y = 2" ]
        in
        let model =
          T.make (review [ text_file path [ old_hunk ] ])
          |> set_cursor R.Cursor.feature
        in
        let refreshed =
          R.refresh (T.review model)
            ~feature:(feature [ text_file path [ old_hunk; new_hunk ] ])
            ~cr_items:[]
        in
        let model, _events =
          expect_update_ok ~msg:"replace review"
            (T.update (T.Replace_review refreshed) model)
        in
        expect_refresh_notice ~msg:"new hunk notice"
          "refreshed: +3/-0 units, +0/-0 CRs" model;
        let model, events =
          expect_update_ok ~msg:"jump first new"
            (T.update (T.Command T.Jump_first_new_review_unit) model)
        in
        equal ~msg:"jump event count" int 1 (List.length events);
        match R.Cursor.selected_scope (T.cursor model) with
        | Some scope -> (
            match R.Scope.view scope with
            | R.Scope.Hunk hunk ->
                equal ~msg:"new hunk old start" int 10 hunk.old_start;
                equal ~msg:"new hunk new start" int 10 hunk.new_start
            | _ -> failf "expected hunk cursor")
        | None -> failf "expected scope cursor");
    test "replace review clamps a disappeared selection to a nearby visible row"
      (fun () ->
        let hunk_a =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let a = 1"; added "let a = 2" ]
        in
        let hunk_b =
          hunk ~old_start:10 ~old_count:1 ~new_start:10 ~new_count:1
            [ removed "let b = 1"; added "let b = 2" ]
        in
        let model =
          T.make
            (review
               [
                 text_file "lib/a.ml" [ hunk_a ];
                 text_file "lib/b.ml" [ hunk_b ];
               ])
          |> set_cursor
               (R.Cursor.scope (R.Scope.of_hunk ~path:"lib/a.ml" hunk_a))
        in
        let refreshed =
          R.refresh (T.review model)
            ~feature:(feature [ text_file "lib/b.ml" [ hunk_b ] ])
            ~cr_items:[]
        in
        let model, _events =
          expect_update_ok ~msg:"replace review"
            (T.update (T.Replace_review refreshed) model)
        in
        match R.Cursor.selected_scope (T.cursor model) with
        | Some scope -> (
            match R.Scope.view scope with
            | R.Scope.File path ->
                equal ~msg:"clamped file" string "lib/b.ml" path
            | _ -> failf "expected clamped file cursor")
        | None -> failf "expected scope cursor");
    test "stale verdict reset is visible in notice, footer, and feature row"
      (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let approved =
          R.set_approval
            (review [ text_file path [ hunk ] ])
            R.Approval.Approved
        in
        let model = T.make approved in
        let refreshed =
          R.refresh approved
            ~feature:
              (feature
                 [ text_file path [ hunk ]; binary_file "assets/logo.bin" ])
            ~cr_items:[]
        in
        let model, _events =
          expect_update_ok ~msg:"replace review"
            (T.update (T.Replace_review refreshed) model)
        in
        is_true ~msg:"approval reset"
          (R.Approval.equal R.Approval.Pending (T.approval model));
        expect_refresh_notice ~msg:"verdict notice"
          "refreshed: +1/-0 units, +0/-0 CRs, verdict reset" model;
        let output =
          Render_harness.render_model ~width:140 ~height:36
            (resize_model ~width:140 ~height:36 model)
        in
        Render_harness.assert_contains ~msg:"footer verdict reset" output
          "verdict reset";
        Render_harness.assert_contains ~msg:"pending approval" output "pending");
    test "retitle refresh does not make a verdict stale" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let approved =
          R.set_approval
            (review [ text_file path [ hunk ] ])
            R.Approval.Approved
        in
        let model = T.make approved in
        let refreshed =
          R.refresh approved
            ~feature:
              (titled_feature "Retitled review" [ text_file path [ hunk ] ])
            ~cr_items:[]
        in
        let model, _events =
          expect_update_ok ~msg:"replace review"
            (T.update (T.Replace_review refreshed) model)
        in
        is_true ~msg:"approval preserved"
          (R.Approval.equal R.Approval.Approved (T.approval model));
        match T.last_refresh_notice model with
        | None -> failf "expected refresh notice"
        | Some notice ->
            is_false ~msg:"not stale" notice.T.Refresh_notice.stale_verdict;
            is_false ~msg:"not reset" notice.verdict_reset);
  ]

let render_tests =
  let render ~width ~height model =
    let model = resize_model ~width ~height model in
    let output = Render_harness.render_model ~width ~height model in
    equal ~msg:"rendered width" int width output.Render_harness.viewport.width;
    equal ~msg:"rendered height" int height output.viewport.height;
    equal ~msg:"rendered line count" int height (List.length output.lines);
    output
  in
  [
    test "wide render shows the three-pane review workspace" (fun () ->
        let output =
          render ~width:140 ~height:36 (T.make (two_file_review ()))
        in
        Render_harness.assert_contains ~msg:"queue title" output "outstanding";
        Render_harness.assert_contains ~msg:"diff path" output "lib/a.ml";
        Render_harness.assert_contains ~msg:"inspector scope" output "Scope";
        Render_harness.assert_contains ~msg:"diff layout" output "unified");
    test "medium render shows queue and diff without pane focus" (fun () ->
        let model =
          T.make (two_file_review ()) |> resize_model ~width:100 ~height:30
        in
        let output = Render_harness.render_model ~width:100 ~height:30 model in
        Render_harness.assert_contains ~msg:"queue title" output "outstanding";
        Render_harness.assert_contains ~msg:"diff path" output "lib/a.ml";
        Render_harness.assert_not_contains ~msg:"no inspector drawer" output
          "inspector");
    test "file inspector summarizes instead of duplicating the diff" (fun () ->
        let model =
          T.make (two_file_review ())
          |> resize_model ~width:140 ~height:36
          |> set_cursor (R.Cursor.scope (R.Scope.file "lib/a.ml"))
        in
        let output = Render_harness.render_model ~width:140 ~height:36 model in
        Render_harness.assert_contains ~msg:"change section" output "Change";
        Render_harness.assert_contains ~msg:"line summary" output "lines";
        Render_harness.assert_not_contains ~msg:"no raw file diff" output
          "diff --git");
    test "narrow render shows the review queue" (fun () ->
        let output =
          render ~width:72 ~height:24 (T.make (two_file_review ()))
        in
        Render_harness.assert_contains ~msg:"queue title" output "outstanding";
        Render_harness.assert_not_contains ~msg:"no pane tabs" output
          "queue diff");
    test "binary selections render a deliberate empty state" (fun () ->
        let output =
          render ~width:120 ~height:30
            (T.make (review [ binary_file "assets/logo.bin" ]))
        in
        Render_harness.assert_contains ~msg:"binary state" output "Binary file");
    test "CR rows and context expose scan metadata" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let item =
          cr_item ~status:C.Status.CR ~priority:C.Priority.Soon ~recipient:"bob"
            ~body:"please rename this binding" ~path ~line:1
            "(* CR-soon alice for bob: please rename this binding *)"
        in
        let model =
          T.make (review ~cr_items:[ item ] [ text_file path [ hunk ] ])
          |> set_cursor (R.Cursor.cr 0)
        in
        let output = render ~width:140 ~height:36 model in
        Render_harness.assert_contains ~msg:"CR row anchor" output "CR line 1";
        Render_harness.assert_not_contains ~msg:"no duplicated CR badge" output
          "CR CR";
        Render_harness.assert_contains ~msg:"CR body snippet" output
          "please rename";
        Render_harness.assert_contains ~msg:"CR status field" output "status";
        Render_harness.assert_contains ~msg:"CR priority field" output "soon";
        Render_harness.assert_contains ~msg:"CR edit action" output "edit";
        Render_harness.assert_contains ~msg:"CR resolve action" output "resolve";
        Render_harness.assert_contains ~msg:"CR remove action" output "remove");
    test "off-diff CR selection reveals source context" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let old = true"; added "let changed = true" ]
        in
        let anchor = "let cr_anchor = true" in
        let source = source_with_anchor 30 anchor in
        let config =
          T.Config.make
            ~source:(fun ~review:_ ~path:requested ->
              if String.equal requested path then Some source else None)
            ()
        in
        let item = cr_item ~path ~line:30 "(* CR alice: review *)" in
        let model =
          T.make ~config (review ~cr_items:[ item ] [ text_file path [ hunk ] ])
          |> set_cursor (R.Cursor.cr 0)
        in
        let output = render ~width:140 ~height:36 model in
        Render_harness.assert_contains ~msg:"viewer label" output "context";
        Render_harness.assert_contains ~msg:"source anchor" output anchor;
        Render_harness.assert_not_contains ~msg:"compact diff hidden" output
          "let changed = true");
    test "invalid CR rows use one blocking badge" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let item = invalid_cr_item ~path ~line:1 "(* CR-what *)" in
        let model =
          T.make (review ~cr_items:[ item ] [ text_file path [ hunk ] ])
          |> set_cursor (R.Cursor.cr 0)
        in
        let output = render ~width:140 ~height:36 model in
        Render_harness.assert_contains ~msg:"invalid CR row" output
          "! CR line 1";
        Render_harness.assert_contains ~msg:"invalid reason" output
          "invalid CR header";
        Render_harness.assert_not_contains ~msg:"no duplicated invalid badge"
          output "x CR");
    test "composer renders as a compact command dialog" (fun () ->
        let model =
          T.make (two_file_review ()) |> resize_model ~width:120 ~height:30
          |> fun model ->
          fst
            (expect_update_ok ~msg:"open composer"
               (T.update (T.Command T.Add_comment) model))
        in
        let output = Render_harness.render_model ~width:120 ~height:30 model in
        Render_harness.assert_contains ~msg:"composer title" output "Comment";
        Render_harness.assert_contains ~msg:"composer placeholder" output
          "Write a CR comment";
        Render_harness.assert_contains ~msg:"composer submit hint" output
          "enter submit";
        Render_harness.assert_contains ~msg:"composer newline hint" output
          "shift+enter newline";
        Render_harness.assert_contains ~msg:"composer cancel hint" output
          "esc cancel");
    test "command palette stacks grouped command rows" (fun () ->
        let model =
          T.make (two_file_review ()) |> resize_model ~width:120 ~height:30
          |> fun model ->
          fst
            (expect_update_ok ~msg:"show command palette"
               (T.update (T.Command T.Show_command_palette) model))
        in
        let output = Render_harness.render_model ~width:120 ~height:30 model in
        Render_harness.assert_contains ~msg:"palette title" output "Commands";
        Render_harness.assert_contains ~msg:"palette close hint" output "esc";
        Render_harness.assert_contains ~msg:"review group" output "Review";
        Render_harness.assert_contains ~msg:"command label" output
          "mark reviewed / unreviewed";
        Render_harness.assert_contains ~msg:"command key" output "space";
        Render_harness.assert_not_contains ~msg:"no horizontal row collapse"
          output "Reviewmark");
    test "command palette focuses the filter input" (fun () ->
        let model =
          T.make (two_file_review ()) |> fun model ->
          fst
            (expect_update_ok ~msg:"show command palette"
               (T.update (T.Command T.Show_command_palette) model))
        in
        let app =
          Render_harness.render_interactive_model ~width:120 ~height:30 model
        in
        (match Mosaic_ui.Renderer.focused app.renderer with
        | Some node ->
            equal ~msg:"focused node" string "sift-command-palette-filter"
              (Mosaic_ui.Renderable.id node)
        | None -> failf "expected focused palette filter");
        let cursor =
          Matrix.Screen.cursor (Mosaic_ui.Renderer.screen app.renderer)
        in
        is_true ~msg:"filter exposes a terminal cursor"
          (Option.is_some cursor.position));
    test "command palette filters from typed input" (fun () ->
        let model =
          T.make (two_file_review ()) |> fun model ->
          fst
            (expect_update_ok ~msg:"show command palette"
               (T.update (T.Command T.Show_command_palette) model))
        in
        let model =
          match T.message_of_key model (key_char 't') with
          | Some (T.Command_palette_msg _ as msg) ->
              fst
                (expect_update_ok ~msg:"type palette query" (T.update msg model))
          | Some _ | None -> failf "expected typed key to update query"
        in
        let output = Render_harness.render_model ~width:120 ~height:30 model in
        Render_harness.assert_contains ~msg:"query text" output "t";
        Render_harness.assert_contains ~msg:"filtered command" output
          "toggle diff layout";
        Render_harness.assert_not_contains ~msg:"filtered out command" output
          "mark reviewed / unreviewed";
        let model =
          match T.message_of_key model (key Matrix.Input.Key.Backspace) with
          | Some (T.Command_palette_msg _ as msg) ->
              fst
                (expect_update_ok ~msg:"backspace palette query"
                   (T.update msg model))
          | Some _ | None -> failf "expected backspace to edit query"
        in
        let output = Render_harness.render_model ~width:120 ~height:30 model in
        Render_harness.assert_not_contains ~msg:"query cleared" output "> t");
    test "command palette is keyboard selectable" (fun () ->
        let model =
          T.make (two_file_review ()) |> fun model ->
          fst
            (expect_update_ok ~msg:"show command palette"
               (T.update (T.Command T.Show_command_palette) model))
        in
        (match T.message_of_key model (key Matrix.Input.Key.Down) with
        | Some (T.Command_palette_msg _) -> ()
        | Some _ | None -> failf "expected down to select next command");
        (match T.message_of_key model (key Matrix.Input.Key.Up) with
        | Some (T.Command_palette_msg _) -> ()
        | Some _ | None -> failf "expected up to select previous command");
        (match T.message_of_key model (key_char 'j') with
        | Some (T.Command_palette_msg _) -> ()
        | Some _ | None -> failf "expected j to select next command");
        (match T.message_of_key model (key_char 'k') with
        | Some (T.Command_palette_msg _) -> ()
        | Some _ | None -> failf "expected k to select previous command");
        match T.message_of_key model (key Matrix.Input.Key.Enter) with
        | Some (T.Command_palette_msg _) -> ()
        | Some _ | None -> failf "expected enter to activate command");
    test "command palette j selects the next command from filter focus" (fun () ->
        let model =
          T.make (two_file_review ()) |> fun model ->
          fst
            (expect_update_ok ~msg:"show command palette"
               (T.update (T.Command T.Show_command_palette) model))
        in
        let app =
          Render_harness.render_interactive_model ~width:120 ~height:30 model
        in
        Render_harness.clear_messages app;
        Render_harness.type_text app "j";
        let model =
          apply_messages ~msg:"palette j navigation" model
            (Render_harness.messages app)
        in
        let output = Render_harness.render_model ~width:120 ~height:30 model in
        Render_harness.assert_not_contains ~msg:"j did not edit query" output
          "> j";
        let app =
          Render_harness.render_interactive_model ~width:120 ~height:30 model
        in
        Render_harness.clear_messages app;
        Render_harness.enter app;
        let model =
          apply_messages ~msg:"activate selected palette command" model
            (Render_harness.messages app)
        in
        match T.comment_composer model with
        | Some _ -> ()
        | None -> failf "expected j then enter to activate add comment");
    test "command palette enter activates the selected command" (fun () ->
        let model =
          T.make (two_file_review ()) |> fun model ->
          fst
            (expect_update_ok ~msg:"show command palette"
               (T.update (T.Command T.Show_command_palette) model))
        in
        let msg =
          match T.message_of_key model (key Matrix.Input.Key.Enter) with
          | Some msg -> msg
          | None -> failf "expected enter to activate command"
        in
        let _model, events =
          expect_update_ok ~msg:"activate command" (T.update msg model)
        in
        match events with
        | [ T.Review_changed _ ] -> ()
        | _ -> failf "expected command activation to mark the selection");
  ]

let action_tests =
  [
    test "resize is UI-local" (fun () ->
        let model = T.make (two_file_review ()) in
        let cursor = T.cursor model in
        let model, events =
          expect_update_ok ~msg:"resize" (T.update (T.Resize (72, 20)) model)
        in
        equal ~msg:"resize event count" int 0 (List.length events);
        is_true ~msg:"cursor unchanged" (R.Cursor.equal cursor (T.cursor model)));
    test "queue activation focuses the diff pane" (fun () ->
        let model = T.make (two_file_review ()) in
        let model, command = T.update (T.Activate_queue_row 0) model in
        is_true ~msg:"diff focus command"
          (command_focuses "sift.diff" command);
        is_true ~msg:"cursor remains valid"
          (Option.is_some (R.Cursor.selected_scope (T.cursor model))));
    test "queue selection regains semantic focus from diff" (fun () ->
        let model = T.make (two_file_review ()) in
        let model =
          fst (expect_update_ok ~msg:"activate diff" (T.update T.Activate_diff model))
        in
        let model =
          fst
            (expect_update_ok ~msg:"select queue row"
               (T.update (T.Select_queue 3) model))
        in
        expect_current_scope ~msg:"queue selection current scope"
          (R.Scope.file "lib/b.ml") model);
    test "queue activation switches to line selection in diff" (fun () ->
        let model = T.make (two_file_review ()) in
        let model =
          fst
            (expect_update_ok ~msg:"activate queue row"
               (T.update (T.Activate_queue_row 3) model))
        in
        expect_current_scope ~msg:"diff activation current scope"
          (R.Scope.old_line ~path:"lib/b.ml" ~line:10)
          model);
    test "entering diff from queue uses the newly selected hunk" (fun () ->
        let path = "lib/core.ml" in
        let first =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let a = 1"; added "let a = 2" ]
        in
        let second =
          hunk ~old_start:10 ~old_count:1 ~new_start:20 ~new_count:1
            [ removed "let b = 1"; added "let b = 2" ]
        in
        let model = T.make (review [ text_file path [ first; second ] ]) in
        let model =
          fst
            (expect_update_ok ~msg:"activate first diff"
               (T.update T.Activate_diff model))
        in
        expect_current_scope ~msg:"first diff line"
          (R.Scope.old_line ~path ~line:1)
          model;
        let model =
          fst (expect_update_ok ~msg:"return to queue" (T.update T.Activate_queue model))
        in
        let model =
          fst
            (expect_update_ok ~msg:"select second hunk"
               (T.update (T.Select_queue 3) model))
        in
        let msg =
          match T.message_of_key model (key Matrix.Input.Key.Enter) with
          | Some msg -> msg
          | None -> failf "expected enter to focus diff"
        in
        let model =
          fst (expect_update_ok ~msg:"enter selected hunk diff" (T.update msg model))
        in
        expect_current_scope ~msg:"second hunk diff line"
          (R.Scope.new_line ~path ~line:20)
          model);
    test "review replacement restores diff focus" (fun () ->
        let review = two_file_review () in
        let model =
          fst
            (expect_update_ok ~msg:"activate diff"
               (T.update T.Activate_diff (T.make review)))
        in
        let _model, command = T.update (T.Replace_review review) model in
        is_true ~msg:"replace review restores diff focus"
          (command_focuses "sift.diff" command));
    test "mark and approval commands update review state" (fun () ->
        let path = "lib/core.ml" in
        let hunk =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let x = 1"; added "let x = 2" ]
        in
        let model =
          T.make (review [ text_file path [ hunk ] ])
          |> set_cursor (R.Cursor.scope (R.Scope.new_line ~path ~line:1))
        in
        let model, mark_events =
          expect_update_ok ~msg:"mark reviewed"
            (T.update (T.Command (T.Mark_current T.Mark_reviewed)) model)
        in
        is_true ~msg:"line reviewed"
          (R.is_reviewed (T.review model) (R.Scope.new_line ~path ~line:1));
        equal ~msg:"mark event count" int 1 (List.length mark_events);
        let model, approval_events =
          expect_update_ok ~msg:"approve"
            (T.update (T.Command (T.Set_approval R.Approval.Approved)) model)
        in
        is_true ~msg:"approved" (R.Approval.is_approved (T.approval model));
        equal ~msg:"approval event count" int 1 (List.length approval_events));
    test "space on the last hunk keeps the cursor when there is no next unit"
      (fun () ->
        let first =
          hunk ~old_start:1 ~old_count:1 ~new_start:1 ~new_count:1
            [ removed "let a = 1"; added "let a = 2" ]
        in
        let path = "lib/b.ml" in
        let last =
          hunk ~old_start:10 ~old_count:1 ~new_start:10 ~new_count:1
            [ removed "let b = 1"; added "let b = 2" ]
        in
        let scope = R.Scope.of_hunk ~path last in
        let model =
          T.make
            (review
               [
                 text_file "lib/a.ml" [ first ];
                 text_file path [ last ];
               ])
          |> set_cursor (R.Cursor.scope scope)
        in
        let model, events =
          expect_update_ok ~msg:"toggle last hunk reviewed"
            (T.update (T.Command (T.Mark_current T.Toggle_mark)) model)
        in
        equal ~msg:"mark event count" int 1 (List.length events);
        is_true ~msg:"last hunk reviewed"
          (R.is_reviewed (T.review model) scope);
        expect_selected_scope ~msg:"cursor stays on last hunk" scope model);
  ]

let () =
  run "sift.tui"
    [
      group "diff" diff_tests;
      group "queue" queue_tests;
      group "comment" comment_tests;
      group "refresh" refresh_tests;
      group "render" render_tests;
      group "action" action_tests;
    ]
