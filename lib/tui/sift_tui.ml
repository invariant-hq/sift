open Mosaic

type diff_layout = Unified | Split
type mark_action = Mark_reviewed | Mark_unreviewed | Toggle_mark | Clear_mark
type layout = Wide | Medium | Narrow
type active_surface = Queue | Diff

type command =
  | Quit
  | Move_cursor of Sift_review.Cursor.move
  | Move_outstanding of Sift_review.Cursor.move
  | Move_file of Sift_review.Cursor.move
  | Move_cr of Sift_review.Cursor.move
  | Jump_first_new_review_unit
  | Mark_current of mark_action
  | Add_comment
  | Edit_cr
  | Remove_cr
  | Resolve_cr
  | Set_approval of Sift_review.Approval.t
  | Set_diff_layout of diff_layout
  | Toggle_diff_layout
  | Show_command_palette
  | Close_modal

type overlay = Command_palette of command Command_palette.t

type msg =
  | Command of command
  | Select_queue of int
  | Activate_queue_row of int
  | Select_scope of Sift_review.Scope.t
  | Select_cursor of Sift_review.Cursor.t
  | Diff_pane_msg of Diff_pane.msg
  | Command_palette_msg of Command_palette.msg
  | Composer_msg of Composer.msg
  | Activate_queue
  | Activate_diff
  | Replace_review of Sift_review.t
  | Replace_review_and_select of Sift_review.t * Sift_review.Cursor.t
  | Report_error of string
  | Dismiss_error
  | Resize of int * int
  | Review_changed of Sift_review.t
  | Comment_submitted of comment
  | Cr_removed of cr
  | Cr_edited of cr * string
  | Cr_resolved of cr

and comment = Composer.comment = { scope : Sift_review.Scope.t; body : string }
and cr = Composer.cr = { index : int; item : Sift_crs.Item.t }

module Keymap = struct
  type binding = {
    shortcut : Mosaic.Shortcut.t;
    command : command;
    label : string option;
  }

  type t = binding list

  let binding ?label shortcut command = { shortcut; command; label }
  let make bindings = bindings

  let default =
    [
      binding ~label:"q" (Shortcut.char 'q') Quit;
      binding ~label:"esc" Shortcut.escape Quit;
      binding ~label:"j" (Shortcut.char 'j') (Move_cursor Next);
      binding ~label:"down" Shortcut.down (Move_cursor Next);
      binding ~label:"k" (Shortcut.char 'k') (Move_cursor Previous);
      binding ~label:"up" Shortcut.up (Move_cursor Previous);
      binding ~label:"g" (Shortcut.char 'g') (Move_cursor First);
      binding ~label:"G" (Shortcut.char ~shift:true 'g') (Move_cursor Last);
      binding ~label:"J" (Shortcut.char ~shift:true 'j') (Move_file Next);
      binding ~label:"K" (Shortcut.char ~shift:true 'k') (Move_file Previous);
      binding ~label:"n" (Shortcut.char 'n') (Move_outstanding Next);
      binding ~label:"p" (Shortcut.char 'p') (Move_outstanding Previous);
      binding ~label:"N" (Shortcut.char ~shift:true 'n') (Move_cr Next);
      binding ~label:"P" (Shortcut.char ~shift:true 'p') (Move_cr Previous);
      binding ~label:"m" (Shortcut.char 'm') Jump_first_new_review_unit;
      binding ~label:"space" Shortcut.space (Mark_current Toggle_mark);
      binding ~label:"r" (Shortcut.char 'r') (Mark_current Mark_reviewed);
      binding ~label:"u" (Shortcut.char 'u') (Mark_current Mark_unreviewed);
      binding ~label:"x" (Shortcut.char 'x') (Mark_current Clear_mark);
      binding ~label:"c" (Shortcut.char 'c') Add_comment;
      binding ~label:"e" (Shortcut.char 'e') Edit_cr;
      binding ~label:"d" (Shortcut.char 'd') Remove_cr;
      binding ~label:"R" (Shortcut.char ~shift:true 'r') Resolve_cr;
      binding ~label:"a" (Shortcut.char 'a') (Set_approval Approved);
      binding ~label:"s" (Shortcut.char 's') (Set_approval Seconded);
      binding ~label:"l" (Shortcut.char 'l') Toggle_diff_layout;
      binding ~label:"?" (Shortcut.char '?') Show_command_palette;
      binding (Shortcut.char ~shift:true '/') Show_command_palette;
      binding ~label:":" (Shortcut.char ':') Show_command_palette;
      binding (Shortcut.char ~shift:true ';') Show_command_palette;
    ]

  let bindings t = t

  let command t key =
    let rec loop = function
      | [] -> None
      | binding :: rest ->
          if Shortcut.matches binding.shortcut key then Some binding.command
          else loop rest
    in
    loop t
end

module Config = struct
  type source_resolver = review:Sift_review.t -> path:string -> string option

  type t = {
    theme : Theme.t;
    keymap : Keymap.t;
    diff_layout : diff_layout;
    diff_wrap : Mosaic.Text_surface.wrap;
    show_line_numbers : bool;
    wrap_navigation : bool;
    workspace_label : string option;
    source : source_resolver;
  }

  let no_source ~review:_ ~path:_ = None

  let make ?(theme = Theme.default) ?(keymap = Keymap.default)
      ?(diff_layout = Unified) ?(diff_wrap = `None) ?(show_line_numbers = true)
      ?(wrap_navigation = false) ?workspace_label ?(source = no_source) () =
    {
      theme;
      keymap;
      diff_layout;
      diff_wrap;
      show_line_numbers;
      wrap_navigation;
      workspace_label;
      source;
    }

  let default = make ()
  let theme t = t.theme
  let keymap t = t.keymap
  let diff_layout t = t.diff_layout
  let diff_wrap t = t.diff_wrap
  let show_line_numbers t = t.show_line_numbers
  let wrap_navigation t = t.wrap_navigation
  let workspace_label t = t.workspace_label
  let source t = t.source
end

module Error = struct
  type t =
    | Review of Sift_review.Error.t
    | No_current_scope
    | No_current_file
    | No_current_cr
    | Invalid_cr of Sift_crs.Error.t
    | Empty_comment
    | External of string
    | Invalid_queue_index of int

  let pp ppf = function
    | Review error -> Format.fprintf ppf "%a" Sift_review.Error.pp error
    | No_current_scope -> Format.pp_print_string ppf "no current review scope"
    | No_current_file -> Format.pp_print_string ppf "no current file"
    | No_current_cr -> Format.pp_print_string ppf "no current CR item"
    | Invalid_cr error -> Format.fprintf ppf "%a" Sift_crs.Error.pp error
    | Empty_comment -> Format.pp_print_string ppf "comment body is empty"
    | External message -> Format.pp_print_string ppf message
    | Invalid_queue_index index ->
        Format.fprintf ppf "invalid queue index %d" index
end

module Refresh_notice = struct
  include Refresh_notice
end

module Queue = Review_queue

type t = {
  review : Sift_review.t;
  config : Config.t;
  active_surface : active_surface;
  diff_pane : Diff_pane.t;
  selected_file : int option;
  selected_cr : int option;
  diff_layout : diff_layout;
  width : int;
  height : int;
  overlay : overlay option;
  comment_composer : Composer.t option;
  refresh_notice : Refresh_notice.t option;
  first_new_cursor : Sift_review.Cursor.t option;
  last_notice : string option;
  last_error : Error.t option;
}

let option_bind opt f = match opt with None -> None | Some value -> f value

let cmd_msg msg = Cmd.perform (fun dispatch -> dispatch msg)
let ok_no_cmd t = Ok (t, Cmd.none)

let ok_cursor_change previous_cursor t =
  let cmd =
    if Sift_review.Cursor.equal previous_cursor (Sift_review.cursor t.review)
    then Cmd.none
    else cmd_msg (Review_changed t.review)
  in
  Ok (t, cmd)

let list_find_index predicate list =
  let rec loop index = function
    | [] -> None
    | value :: rest ->
        if predicate value then Some index else loop (index + 1) rest
  in
  loop 0 list

let clamp_index length index =
  if length <= 0 then None
  else if index < 0 then Some 0
  else if index >= length then Some (length - 1)
  else Some index

let move_index ?(wrap = false) length current move =
  if length <= 0 then None
  else
    let last = length - 1 in
    let current =
      match current with
      | None -> 0
      | Some index -> Option.value ~default:0 (clamp_index length index)
    in
    match move with
    | Sift_review.Cursor.First -> Some 0
    | Last -> Some last
    | Previous ->
        if current = 0 then if wrap then Some last else Some current
        else Some (current - 1)
    | Next ->
        if current = last then if wrap then Some 0 else Some current
        else Some (current + 1)

let files review = Sift_feature.files (Sift_review.feature review)
let cr_items review = Sift_review.cr_items review

let selection_or_first count selected =
  match selected with Some _ -> selected | None -> clamp_index count 0

let selected_file_from_cursor review =
  match Sift_review.Cursor.selected_scope (Sift_review.cursor review) with
  | None -> None
  | Some scope -> (
      match Sift_review.Scope.path scope with
      | None -> None
      | Some path ->
          list_find_index
            (fun file -> String.equal (Sift_diff.File.path file) path)
            (files review))

let selected_cr_from_cursor review =
  Sift_review.Cursor.selected_cr (Sift_review.cursor review)

let normalize_selection review selected_file selected_cr =
  let file_count = List.length (files review) in
  let cr_count = List.length (cr_items review) in
  let selected_file =
    match selected_file_from_cursor review with
    | Some index -> Some index
    | None -> option_bind selected_file (clamp_index file_count)
  in
  let selected_file = selection_or_first file_count selected_file in
  let selected_cr =
    match selected_cr_from_cursor review with
    | Some index -> clamp_index cr_count index
    | None -> option_bind selected_cr (clamp_index cr_count)
  in
  let selected_cr = selection_or_first cr_count selected_cr in
  (selected_file, selected_cr)

let initial_review review =
  match Review_plan.first_outstanding ~review with
  | None -> review
  | Some cursor -> (
      match Sift_review.set_cursor review cursor with
      | Ok review -> review
      | Error _ -> review)

let make ?(config = Config.default) review =
  let review = initial_review review in
  let selected_file, selected_cr = normalize_selection review None None in
  {
    review;
    config;
    active_surface = Queue;
    diff_pane = Diff_pane.make ();
    selected_file;
    selected_cr;
    diff_layout = Config.diff_layout config;
    width = 120;
    height = 36;
    overlay = None;
    comment_composer = None;
    refresh_notice = None;
    first_new_cursor = None;
    last_notice = None;
    last_error = None;
  }

let review t = t.review
let cursor t = Sift_review.cursor t.review
let approval t = Sift_review.approval t.review
let last_refresh_notice t = t.refresh_notice
let last_error t = t.last_error
let comment_composer t = Option.map Composer.draft t.comment_composer

let with_notice t notice =
  { t with last_notice = Some notice; last_error = None }

let with_refresh_notice t notice =
  {
    t with
    refresh_notice = Some notice;
    last_notice = Some (Format.asprintf "%a" Refresh_notice.pp notice);
    last_error = None;
  }

let layout t =
  if t.width >= 120 && t.height >= 24 then Wide
  else if t.width >= 88 && t.height >= 22 then Medium
  else Narrow

let queue_rows t =
  let cursor = Sift_review.cursor t.review in
  Review_queue.rows ~review:t.review ~cursor ()

let queue_row_is_selected = function
  | Review_queue.Feature { selected; _ }
  | File { selected; _ }
  | Hunk { selected; _ }
  | Cr { selected; _ } ->
      selected

let selected_queue_index t =
  list_find_index queue_row_is_selected (queue_rows t)

let context t =
  Review_context.v ~review:t.review ~selected_file:t.selected_file
    ~selected_cr:t.selected_cr

let diff_target t =
  let source ~path = Config.source t.config ~review:t.review ~path in
  Diff_target.v ~source (context t)

let current_scope t =
  let context_scope = Review_context.scope (context t) in
  match t.active_surface with
  | Queue -> context_scope
  | Diff -> (
      match Diff_pane.selected_scope t.diff_pane ~target:(diff_target t) with
      | Some _ as scope -> scope
      | None -> context_scope)

let current_detail t =
  let context = context t in
  match (t.active_surface, Review_context.cr context) with
  | Queue, Some cr -> Some (Inspector_pane.Cr (cr.index, cr.item))
  | (Queue | Diff), (None | Some _) -> (
      match current_scope t with
      | None -> None
      | Some scope -> (
          match Sift_review.Scope.view scope with
          | Feature ->
              Some (Inspector_pane.Feature (Sift_review.feature t.review))
          | File path ->
              Option.map
                (fun file -> Inspector_pane.File file)
                (Sift_feature.find_file (Sift_review.feature t.review) ~path)
          | Hunk hunk -> Some (Inspector_pane.Hunk hunk)
          | Line (side, path, line) ->
              Some (Inspector_pane.Line (side, path, line))))

let current_patch t = Diff_target.patch (diff_target t)

let set_review t review =
  let selected_file, selected_cr =
    normalize_selection review t.selected_file t.selected_cr
  in
  { t with review; selected_file; selected_cr; last_error = None }

let set_cursor t cursor =
  match Sift_review.set_cursor t.review cursor with
  | Error error -> Error (Error.Review error)
  | Ok review -> Ok (set_review t review)

let set_scope t scope = set_cursor t (Sift_review.Cursor.scope scope)

let set_review_result t = function
  | Ok review -> Ok (set_review t review)
  | Error error -> Error (Error.Review error)

let select_queue t index =
  match List.nth_opt (queue_rows t) index with
  | None -> Error (Error.Invalid_queue_index index)
  | Some row ->
      let cursor = Review_queue.cursor row in
      set_cursor { t with diff_pane = Diff_pane.make () } cursor

let select_file t index =
  match List.nth_opt (files t.review) index with
  | None -> Error Error.No_current_file
  | Some file ->
      set_scope
        { t with selected_file = Some index }
        (Sift_review.Scope.file (Sift_diff.File.path file))

let select_cr t index =
  match Sift_review.cr_item t.review index with
  | None -> Error Error.No_current_cr
  | Some item ->
      let path = Sift_crs.Item.path item in
      let selected_file =
        list_find_index
          (fun file -> String.equal (Sift_diff.File.path file) path)
          (files t.review)
      in
      set_cursor
        { t with selected_cr = Some index; selected_file }
        (Sift_review.Cursor.cr index)

let move_file t move =
  let length = List.length (files t.review) in
  match
    move_index
      ~wrap:(Config.wrap_navigation t.config)
      length t.selected_file move
  with
  | None -> Error Error.No_current_file
  | Some index -> select_file t index

let move_cr t move =
  let length = Sift_review.cr_count t.review in
  match
    move_index ~wrap:(Config.wrap_navigation t.config) length t.selected_cr move
  with
  | None -> Error Error.No_current_cr
  | Some index -> select_cr t index

let move_queue t move =
  let rows = queue_rows t in
  let length = List.length rows in
  match
    move_index
      ~wrap:(Config.wrap_navigation t.config)
      length (selected_queue_index t) move
  with
  | None -> Error (Error.Invalid_queue_index 0)
  | Some index -> select_queue t index

let move_outstanding t move =
  let rows = queue_rows t in
  let indices = Review_plan.outstanding_indices rows in
  match indices with
  | [] -> Ok (with_notice t "all reviewed")
  | _ ->
      let selected =
        match selected_queue_index t with
        | None -> None
        | Some selected ->
            list_find_index (fun index -> index = selected) indices
      in
      let length = List.length indices in
      let target =
        match
          move_index
            ~wrap:(Config.wrap_navigation t.config)
            length selected move
        with
        | None -> 0
        | Some index -> index
      in
      let full_index = List.nth indices target in
      select_queue t full_index

let jump_first_new_review_unit t =
  match t.first_new_cursor with
  | None -> Ok (with_notice t "no new review unit")
  | Some cursor -> (
      match set_cursor t cursor with
      | Ok t -> Ok t
      | Error _ ->
          Ok (with_notice { t with first_new_cursor = None } "new unit gone"))

let select_next_outstanding_after t index =
  let rows = queue_rows t in
  let rec first_after = function
    | [] -> None
    | (row_index, row) :: rest ->
        if Option.is_some (Review_plan.priority row) then
          if row_index > index then Some row_index else first_after rest
        else first_after rest
  in
  match first_after (List.mapi (fun index row -> (index, row)) rows) with
  | None -> Ok t
  | Some index -> select_queue t index

let mark_current t action =
  match current_scope t with
  | None -> Error Error.No_current_scope
  | Some scope -> (
      match action with
      | Clear_mark -> Ok (set_review t (Sift_review.clear_mark t.review scope))
      | Toggle_mark ->
          if Sift_review.is_reviewed t.review scope then
            set_review_result t (Sift_review.mark_unreviewed t.review scope)
          else set_review_result t (Sift_review.mark_reviewed t.review scope)
      | Mark_reviewed ->
          set_review_result t (Sift_review.mark_reviewed t.review scope)
      | Mark_unreviewed ->
          set_review_result t (Sift_review.mark_unreviewed t.review scope))

let set_approval t approval =
  {
    (set_review t (Sift_review.set_approval t.review approval)) with
    refresh_notice = None;
    first_new_cursor = None;
  }

let commentable_scope t =
  match current_scope t with
  | Some scope when Option.is_some (Sift_review.Scope.path scope) -> Some scope
  | Some _ | None -> None

let start_comment t =
  match commentable_scope t with
  | None -> Error Error.No_current_scope
  | Some scope ->
      Ok
        ( {
            t with
            comment_composer = Some (Composer.add scope);
            last_notice = None;
            last_error = None;
          },
          Cmd.none )

let cr_contains_line item ~path ~line =
  String.equal (Sift_crs.Item.path item) path
  &&
  let span = Sift_crs.Item.span item in
  line >= Sift_crs.Span.start_line span && line <= Sift_crs.Span.stop_line span

let cr_at_current_line t =
  match current_scope t with
  | None -> None
  | Some scope -> (
      match Sift_review.Scope.view scope with
      | Line (_side, path, line) ->
          Sift_review.cr_items t.review
          |> List.mapi (fun index item -> { index; item })
          |> List.find_opt (fun cr -> cr_contains_line cr.item ~path ~line)
      | Feature | File _ | Hunk _ -> None)

let current_cr t =
  match Review_context.cr (context t) with
  | Some cr -> Some { index = cr.index; item = cr.item }
  | None -> cr_at_current_line t

let edit_current_cr t =
  match current_cr t with
  | None -> Error Error.No_current_cr
  | Some cr -> (
      match Sift_crs.Item.comment cr.item with
      | Error error -> Error (Error.Invalid_cr error)
      | Ok comment ->
          Ok
            ( {
                t with
                comment_composer =
                  Some (Composer.edit cr ~body:(Sift_crs.Comment.body comment));
                last_notice = None;
                last_error = None;
              },
              Cmd.none ))

let remove_current_cr t =
  match current_cr t with
  | None -> Error Error.No_current_cr
  | Some cr -> Ok (with_notice t "CR removal requested", cmd_msg (Cr_removed cr))

let resolve_current_cr t =
  match current_cr t with
  | None -> Error Error.No_current_cr
  | Some cr ->
      Ok (with_notice t "CR resolve requested", cmd_msg (Cr_resolved cr))

let notice_for_mark = function
  | Mark_reviewed -> "marked reviewed"
  | Mark_unreviewed -> "marked unreviewed"
  | Toggle_mark -> "review mark toggled"
  | Clear_mark -> "cleared review mark"

let notice_for_approval approval =
  Format.asprintf "approval: %a" Sift_review.Approval.pp approval

let cr_cursor_still_selects_same_item before after index =
  match (Sift_review.cr_item before index, Sift_review.cr_item after index) with
  | Some before, Some after -> Sift_crs.Item.equal before after
  | None, Some _ | Some _, None | None, None -> false

let preserve_cursor_review ~before after cursor =
  match Sift_review.Cursor.target cursor with
  | Cr index ->
      if cr_cursor_still_selects_same_item before after index then
        Result.to_option (Sift_review.set_cursor after cursor)
      else None
  | Scope _ -> Result.to_option (Sift_review.set_cursor after cursor)

let select_nearby_queue_row t previous_index =
  match previous_index with
  | None -> t
  | Some previous_index -> (
      match clamp_index (List.length (queue_rows t)) previous_index with
      | None -> t
      | Some index -> (
          match select_queue t index with Ok t -> t | Error _ -> t))

let replace_review ?select_cursor t review =
  let notice = Refresh_notice.derive ~before:t.review ~after:review in
  let first_new_cursor =
    Refresh_notice.first_new_cursor ~before:t.review ~after:review
  in
  let previous_review = t.review in
  let previous_cursor = cursor t in
  let previous_index = selected_queue_index t in
  let t = set_review t review in
  let t =
    match select_cursor with
    | Some cursor -> (
        match set_cursor t cursor with Ok t -> t | Error _ -> t)
    | None -> (
        match
          preserve_cursor_review ~before:previous_review t.review
            previous_cursor
        with
        | Some review -> set_review t review
        | None -> select_nearby_queue_row t previous_index)
  in
  with_refresh_notice { t with first_new_cursor } notice

type command_entry = {
  group : Command_palette.group;
  key : string;
  label : string;
  command : command;
}

let command_entry group ~key ~label command = { group; key; label; command }

let command_catalog =
  let open Command_palette in
  [
    command_entry Review ~key:"space" ~label:"mark reviewed / unreviewed"
      (Mark_current Toggle_mark);
    command_entry Review ~key:"c" ~label:"add comment" Add_comment;
    command_entry Review ~key:"e" ~label:"edit change request" Edit_cr;
    command_entry Review ~key:"R" ~label:"resolve change request" Resolve_cr;
    command_entry Review ~key:"d" ~label:"remove change request" Remove_cr;
    command_entry Review ~key:"a / s" ~label:"approve / second"
      (Set_approval Approved);
    command_entry Navigation ~key:"j / k" ~label:"move queue selection"
      (Move_cursor Next);
    command_entry Navigation ~key:"n / p" ~label:"move outstanding"
      (Move_outstanding Next);
    command_entry Navigation ~key:"m" ~label:"first new review unit"
      Jump_first_new_review_unit;
    command_entry Navigation ~key:"N / P" ~label:"move change request"
      (Move_cr Next);
    command_entry View ~key:"l" ~label:"toggle diff layout" Toggle_diff_layout;
    command_entry Session ~key:"esc" ~label:"close palette" Close_modal;
    command_entry Session ~key:"q" ~label:"quit" Quit;
  ]

let command_available t = function
  | Quit | Set_approval _ | Set_diff_layout _ | Toggle_diff_layout
  | Show_command_palette | Close_modal ->
      true
  | Move_cursor _ -> queue_rows t <> []
  | Move_outstanding _ -> Review_plan.outstanding_indices (queue_rows t) <> []
  | Move_file _ -> files t.review <> []
  | Move_cr _ -> cr_items t.review <> []
  | Jump_first_new_review_unit -> Option.is_some t.first_new_cursor
  | Mark_current _ -> Option.is_some (current_scope t)
  | Add_comment -> Option.is_some (commentable_scope t)
  | Edit_cr | Remove_cr | Resolve_cr -> Option.is_some (current_cr t)

let command_palette_items t =
  command_catalog
  |> List.filter (fun entry -> command_available t entry.command)
  |> List.map (fun entry ->
      Command_palette.item entry.group ~key:entry.key ~label:entry.label
        entry.command)

let set_command_palette t palette =
  { t with overlay = Some (Command_palette palette) }

let focus_active_surface t =
  match t.active_surface with
  | Queue -> Cmd.focus Queue_pane.focus_id
  | Diff -> Cmd.focus Diff_pane.focus_id

let restore_review_focus t =
  match (t.overlay, t.comment_composer) with
  | None, None -> focus_active_surface t
  | Some _, _ | None, Some _ -> Cmd.none

let update_composer t msg =
  match t.comment_composer with
  | None -> Error Error.No_current_scope
  | Some composer -> (
      let composer, cmd, event = Composer.update msg composer in
      let result =
        match event with
        | None -> ok_no_cmd { t with comment_composer = Some composer }
        | Some Composer.Cancelled ->
            Ok
              ( { t with comment_composer = None; last_error = None },
                focus_active_surface t )
        | Some Composer.Empty_submit ->
            ok_no_cmd
              { t with last_notice = None; last_error = Some Error.Empty_comment }
        | Some (Composer.Submitted submission) ->
            let msg, notice =
              match submission with
              | Composer.Submitted_comment comment ->
                  (Comment_submitted comment, "comment submitted")
              | Composer.Edited_cr (cr, body) ->
                  (Cr_edited (cr, body), "CR edit requested")
            in
            Ok
              ( {
                  t with
                  comment_composer = None;
                  last_notice = Some notice;
                  last_error = None;
                },
                Cmd.batch [ cmd_msg msg; focus_active_surface t ] )
      in
      match result with
      | Error _ as error -> error
      | Ok (t, parent_cmd) ->
          Ok
            ( t,
              Cmd.batch
                [ Cmd.map (fun msg -> Composer_msg msg) cmd; parent_cmd ] ))

let apply_command t = function
  | Quit -> Ok (t, Cmd.quit)
  | Move_cursor move -> (
      let previous_cursor = cursor t in
      match move_queue t move with
      | Ok next -> ok_cursor_change previous_cursor next
      | Error error -> Error error)
  | Move_outstanding move -> (
      let previous_cursor = cursor t in
      match move_outstanding t move with
      | Ok next -> ok_cursor_change previous_cursor next
      | Error error -> Error error)
  | Move_file move -> (
      let previous_cursor = cursor t in
      match move_file t move with
      | Ok next -> ok_cursor_change previous_cursor next
      | Error error -> Error error)
  | Move_cr move -> (
      let previous_cursor = cursor t in
      match move_cr t move with
      | Ok next -> ok_cursor_change previous_cursor next
      | Error error -> Error error)
  | Jump_first_new_review_unit -> (
      let previous_cursor = cursor t in
      match jump_first_new_review_unit t with
      | Ok next -> ok_cursor_change previous_cursor next
      | Error error -> Error error)
  | Mark_current action -> (
      let reviewed_before =
        match current_scope t with
        | None -> false
        | Some scope -> Sift_review.is_reviewed t.review scope
      in
      let selected_before = selected_queue_index t in
      match mark_current t action with
      | Ok next ->
          let next = with_notice next (notice_for_mark action) in
          let next =
            match (action, reviewed_before, selected_before) with
            | Toggle_mark, false, Some index -> (
                match select_next_outstanding_after next index with
                | Ok moved -> moved
                | Error _ -> next)
            | _ -> next
          in
          Ok (next, cmd_msg (Review_changed next.review))
      | Error error -> Error error)
  | Add_comment -> start_comment t
  | Edit_cr -> edit_current_cr t
  | Remove_cr -> remove_current_cr t
  | Resolve_cr -> resolve_current_cr t
  | Set_approval approval ->
      let next =
        set_approval t approval |> fun t ->
        with_notice t (notice_for_approval approval)
      in
      Ok (next, cmd_msg (Review_changed next.review))
  | Set_diff_layout layout ->
      Ok ({ t with diff_layout = layout; last_error = None }, Cmd.none)
  | Toggle_diff_layout ->
      let diff_layout =
        match t.diff_layout with Unified -> Split | Split -> Unified
      in
      Ok ({ t with diff_layout; last_error = None }, Cmd.none)
  | Show_command_palette ->
      Ok
        ( {
            t with
            overlay =
              Some (Command_palette (Command_palette.make (command_palette_items t)));
            last_error = None;
          },
          Cmd.none )
  | Close_modal -> Ok ({ t with overlay = None; last_error = None }, Cmd.none)

let update_command_palette t msg =
  match t.overlay with
  | None -> ok_no_cmd t
  | Some (Command_palette palette) -> (
      let palette, cmd, event = Command_palette.update msg palette in
      let result =
        match event with
        | None -> ok_no_cmd (set_command_palette t palette)
        | Some Command_palette.Closed -> ok_no_cmd { t with overlay = None }
        | Some (Command_palette.Activated command) ->
            apply_command { t with overlay = None } command
      in
      match result with
      | Error _ as error -> error
      | Ok (t, parent_cmd) ->
          Ok
            ( t,
              Cmd.batch
                [
                  Cmd.map (fun msg -> Command_palette_msg msg) cmd;
                  parent_cmd;
                ] ))

let focus_queue t =
  ({ t with active_surface = Queue }, Cmd.focus Queue_pane.focus_id)

let focus_diff t =
  let diff_pane, command =
    Diff_pane.update ~target:(diff_target t) Diff_pane.activate t.diff_pane
  in
  ( { t with active_surface = Diff; diff_pane },
    Cmd.batch
      [
        Cmd.map (fun msg -> Diff_pane_msg msg) command;
        Cmd.focus Diff_pane.focus_id;
      ] )

let result_or_error t = function
  | Ok result -> result
  | Error error -> ({ t with last_notice = None; last_error = Some error }, Cmd.none)

let shift_tab = Shortcut.key ~shift:true Matrix.Input.Key.Tab

let message_of_key t key =
  match (t.overlay, t.comment_composer) with
  | Some (Command_palette _), _ ->
      Option.map
        (fun msg -> Command_palette_msg msg)
        (Command_palette.message_of_key key)
  | None, Some _ ->
      Option.map (fun msg -> Composer_msg msg) (Composer.message_of_key key)
  | None, None ->
      if
        match t.active_surface with
        | Queue -> false
        | Diff ->
            Shortcut.matches Shortcut.escape key || Shortcut.matches Shortcut.tab key
            || Shortcut.matches shift_tab key
      then Some Activate_queue
      else if
        match t.active_surface with
        | Queue -> Shortcut.matches Shortcut.enter key
        | Diff -> false
      then Some Activate_diff
      else
        Option.map
          (fun command -> Command command)
          (Keymap.command (Config.keymap t.config) key)

let update msg t =
  let result =
    match msg with
    | Command command -> apply_command t command
    | Select_queue index ->
        let previous_cursor = cursor t in
        Result.bind (select_queue { t with active_surface = Queue } index)
          (ok_cursor_change previous_cursor)
    | Activate_queue_row index ->
        let previous_cursor = cursor t in
        Result.bind (select_queue t index) (fun t ->
            match ok_cursor_change previous_cursor t with
            | Error error -> Error error
            | Ok (t, cmd) ->
                let t, focus = focus_diff t in
                Ok (t, Cmd.batch [ cmd; focus ]))
    | Select_scope scope ->
        let previous_cursor = cursor t in
        Result.bind (set_scope { t with active_surface = Diff } scope)
          (ok_cursor_change previous_cursor)
    | Select_cursor next_cursor ->
        let previous_cursor = cursor t in
        Result.bind (set_cursor t next_cursor) (ok_cursor_change previous_cursor)
    | Diff_pane_msg msg ->
        let diff_pane, cmd =
          Diff_pane.update ~target:(diff_target t) msg t.diff_pane
        in
        Ok
          ( { t with active_surface = Diff; diff_pane },
            Cmd.map (fun msg -> Diff_pane_msg msg) cmd )
    | Command_palette_msg msg -> update_command_palette t msg
    | Composer_msg msg -> update_composer t msg
    | Activate_queue -> Ok (focus_queue t)
    | Activate_diff -> Ok (focus_diff t)
    | Replace_review review ->
        let t = replace_review t review in
        Ok (t, restore_review_focus t)
    | Replace_review_and_select (review, cursor) ->
        let t = replace_review ~select_cursor:cursor t review in
        Ok (t, restore_review_focus t)
    | Report_error message ->
        ok_no_cmd
          { t with last_notice = None; last_error = Some (External message) }
    | Dismiss_error -> ok_no_cmd { t with last_notice = None; last_error = None }
    | Resize (width, height) -> ok_no_cmd { t with width; height }
    | Review_changed _ | Comment_submitted _ | Cr_removed _ | Cr_edited _
    | Cr_resolved _ ->
        ok_no_cmd t
  in
  result_or_error t result

let string_of_approval approval =
  Format.asprintf "%a" Sift_review.Approval.pp approval

let string_of_error error = Format.asprintf "%a" Error.pp error

let diff_layout_to_mosaic = function
  | Unified -> Mosaic.Diff.Unified
  | Split -> Split

let compact_text ?(limit = 28) text =
  let text = String.trim text in
  let len = String.length text in
  if len <= limit then text
  else if limit <= 3 then String.sub text 0 limit
  else String.sub text 0 (limit - 3) ^ "..."

let compact_path ?(limit = 28) path =
  let len = String.length path in
  if limit <= 0 then ""
  else if len <= limit then path
  else if limit <= 3 then String.sub path 0 limit
  else
    let basename =
      match String.rindex_opt path '/' with
      | None -> path
      | Some index -> String.sub path (index + 1) (len - index - 1)
    in
    let base_len = String.length basename in
    if base_len + 4 >= limit then
      let tail_len = min base_len (limit - 3) in
      "..." ^ String.sub basename (base_len - tail_len) tail_len
    else
      let prefix_len = limit - base_len - 4 in
      let prefix = String.sub path 0 prefix_len in
      let prefix =
        if String.ends_with ~suffix:"/" prefix then
          String.sub prefix 0 (String.length prefix - 1)
        else prefix
      in
      prefix ^ "/..." ^ basename

let verdict_notice_label = function
  | Some notice when notice.Refresh_notice.verdict_reset -> Some "verdict reset"
  | Some notice when notice.stale_verdict -> Some "stale verdict"
  | Some _ | None -> None

let has_new_review_units = function
  | Some notice -> notice.Refresh_notice.new_review_units > 0
  | None -> false

let handled_key key msg =
  Mosaic.Event.Key.prevent_default key;
  Some msg

let queue_key key =
  if Shortcut.matches Shortcut.tab key || Shortcut.matches shift_tab key
  then handled_key key Activate_diff
  else None

module View = struct
  let queue_width = Queue_pane.default_width
  let context_width = Inspector_pane.default_width

  let queue_pane ?(width = queue_width) ?(compact = false) t =
    Queue_pane.view ~theme:(Config.theme t.config) ~rows:(queue_rows t)
      ~selected_index:(selected_queue_index t) ~refresh_notice:t.refresh_notice
      ~width ~compact
      ~focused:(match t.active_surface with Queue -> true | Diff -> false)
      ~wrap_navigation:(Config.wrap_navigation t.config) ~on_key:queue_key
      ~on_select:(fun index -> Select_queue index)
      ~on_activate:(fun index -> Activate_queue_row index)

  let diff t =
    Diff_pane.view t.diff_pane ~theme:(Config.theme t.config)
      ~review:t.review ~target:(diff_target t)
      ~layout:(diff_layout_to_mosaic t.diff_layout)
      ~show_line_numbers:(Config.show_line_numbers t.config)
      ~wrap:(Config.diff_wrap t.config)
      ~focused:(match t.active_surface with Diff -> true | Queue -> false)
    |> Mosaic.map (fun msg -> Diff_pane_msg msg)

  let feature_identity feature =
    match Sift_feature.title feature with
    | Some title -> title
    | None -> (
        let tip = Sift_feature.Revision.to_string (Sift_feature.tip feature) in
        match tip with "WORKTREE" -> "worktree" | _ -> "feature")

  let revision_range feature =
    let compact_revision revision =
      let text = Sift_feature.Revision.to_string revision in
      if String.length text <= 12 then text else String.sub text 0 10
    in
    compact_revision (Sift_feature.base feature)
    ^ ".."
    ^ compact_revision (Sift_feature.tip feature)

  let context_pane ?(width = context_width) t =
    Inspector_pane.view ~theme:(Config.theme t.config) ~review:t.review
      ~target:(current_detail t) ~width

  let overlay t =
    match t.overlay with
    | None -> fragment []
    | Some (Command_palette palette) ->
        Command_palette.view palette ~theme:(Config.theme t.config)
          ~width:t.width ~height:t.height
        |> Mosaic.map (fun msg -> Command_palette_msg msg)

  let footer_legend t =
    if t.width < 90 then "! left   R reviewed   CR   ? / :"
    else "! unreviewed   R reviewed   CR request   ? / : command"

  let status t =
    let theme = Config.theme t.config in
    let summary = Sift_review.summary t.review in
    let state =
      match (t.last_error, t.last_notice) with
      | Some error, _ -> "error: " ^ string_of_error error
      | None, Some notice -> notice
      | None, None when Option.is_some t.comment_composer -> "comment"
      | None, None when Sift_review.Summary.remaining summary = 0 ->
          "all reviewed  a approve"
      | None, None -> "saved"
    in
    let left =
      match Config.workspace_label t.config with
      | None -> state
      | Some label ->
          Printf.sprintf "%s  %s" (compact_path ~limit:48 label) state
    in
    let right =
      match t.comment_composer with
      | Some _ -> "ctrl+enter submit   esc cancel"
      | None when has_new_review_units t.refresh_notice ->
          "m first new   " ^ footer_legend t
      | None -> footer_legend t
    in
    let style =
      match t.last_error with
      | Some _ -> theme.error
      | None -> (
          match verdict_notice_label t.refresh_notice with
          | Some _ -> theme.stale
          | None -> theme.muted)
    in
    let right_width = min (String.length right) (max 12 (t.width - 2)) in
    box ~flex_direction:Row ~justify_content:Space_between
      ~padding:(padding_xy 1 0) ~background:theme.background
      [
        text ~style ~truncate:true ~flex_grow:1.
          ~min_size:{ width = px 0; height = px 0 }
          left;
        text ~style:theme.muted ~truncate:true ~flex_shrink:0.
          ~size:{ width = px right_width; height = px 1 }
          right;
      ]

  let header t =
    let theme = Config.theme t.config in
    let feature = Sift_review.feature t.review in
    let summary = Sift_review.summary t.review in
    let feature_summary = Sift_feature.summary feature in
    let title = feature_identity feature in
    let range = revision_range feature in
    let right =
      Printf.sprintf "%.0f%%  %s"
        (Sift_review.progress t.review *. 100.)
        (string_of_approval (approval t))
    in
    let meta =
      Printf.sprintf "%s  %d files  %d CRs" range
        (Sift_feature.Summary.files feature_summary)
        (Sift_review.Summary.cr_items summary)
    in
    box ~flex_direction:Column ~padding:(padding_xy 1 0)
      ~background:theme.background
      [
        box ~flex_direction:Row ~justify_content:Space_between
          [
            text
              ~style:(Mosaic.Ansi.Style.make ~bold:true ())
              (compact_text ~limit:56 title);
            text ~style:theme.muted right;
          ];
        text ~style:theme.muted
          (compact_text ~limit:(max 24 (t.width - 2)) meta);
      ]

  let workspace t =
    match layout t with
    | Wide ->
        box ~flex_direction:Row ~gap:(gap_xy 1 0) ~flex_grow:1.
          ~min_size:{ width = px 0; height = px 0 }
          [ queue_pane t; diff t; context_pane t ]
    | Medium ->
        box ~flex_direction:Row ~gap:(gap_xy 1 0) ~flex_grow:1.
          ~min_size:{ width = px 0; height = px 0 }
          [ queue_pane ~width:32 ~compact:true t; diff t ]
    | Narrow -> queue_pane ~width:(max 24 (t.width - 2)) ~compact:true t

  let root t =
    box ~flex_direction:Column
      ~size:{ width = pct 100; height = pct 100 }
      ~background:(Config.theme t.config).background
      [
        header t;
        workspace t;
        (match t.comment_composer with
        | None -> fragment []
        | Some composer ->
            Composer.view ~theme:(Config.theme t.config) ~width:t.width
              ~height:t.height composer
            |> Mosaic.map (fun msg -> Composer_msg msg));
        overlay t;
        status t;
      ]
end

let view = View.root

let subscriptions t =
  Sub.batch
    [
      Sub.on_key_all (fun key ->
          if Mosaic.Event.Key.default_prevented key then None
          else
            match message_of_key t key with
            | None -> None
            | Some msg ->
                Mosaic.Event.Key.prevent_default key;
                Some msg);
      Sub.on_resize (fun ~width ~height -> Resize (width, height));
    ]

let app ?(config = Config.default) review =
  let init () = (make ~config review, Cmd.none) in
  { init; update; view; subscriptions }
