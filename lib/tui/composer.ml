open Mosaic

type comment = { scope : Sift_review.Scope.t; body : string }
type cr = { index : int; item : Sift_crs.Item.t }
type target = Add_comment_to of Sift_review.Scope.t | Editing_cr of cr
type submission = Submitted_comment of comment | Edited_cr of cr * string
type event = Submitted of submission | Empty_submit | Cancelled
type msg = Input of string | Submit of string | Cancel

type t = {
  target : target;
  draft : comment;
}

let add scope =
  { target = Add_comment_to scope; draft = { scope; body = "" } }

let scope_of_cr item =
  let path = Sift_crs.Item.path item in
  let line = Sift_crs.Span.start_line (Sift_crs.Item.span item) in
  Sift_review.Scope.new_line ~path ~line

let edit cr ~body =
  let scope = scope_of_cr cr.item in
  { target = Editing_cr cr; draft = { scope; body } }

let draft t = t.draft
let set_body t body = { t with draft = { t.draft with body } }

let submission t ~body =
  let body = String.trim body in
  if String.equal body "" then None
  else
    match t.target with
    | Add_comment_to scope -> Some (Submitted_comment { scope; body })
    | Editing_cr cr -> Some (Edited_cr (cr, body))

let message_of_key key =
  if Shortcut.matches Shortcut.escape key then Some Cancel else None

let key_bindings =
  let binding = Mosaic_ui.Textarea.key_binding in
  [
    binding "return" Mosaic_ui.Textarea.Submit;
    binding "linefeed" Mosaic_ui.Textarea.Submit;
    binding ~shift:true "return" Mosaic_ui.Textarea.Newline;
    binding ~shift:true "linefeed" Mosaic_ui.Textarea.Newline;
  ]

let update msg t =
  match msg with
  | Input body -> (set_body t body, Cmd.none, None)
  | Submit body -> (
      let t = set_body t body in
      match submission t ~body with
      | None -> (t, Cmd.none, Some Empty_submit)
      | Some submission -> (t, Cmd.none, Some (Submitted submission)))
  | Cancel -> (t, Cmd.none, Some Cancelled)

let style_fg ~default (style : Mosaic.Ansi.Style.t) =
  Option.value ~default style.fg

let title = function
  | Add_comment_to _ -> "Comment"
  | Editing_cr { index; _ } -> Printf.sprintf "Edit CR #%d" index

let subtitle t =
  match t.target with
  | Add_comment_to scope -> Format.asprintf "%a" Sift_review.Scope.pp scope
  | Editing_cr { item; _ } ->
      let path = Sift_crs.Item.path item in
      let line = Sift_crs.Span.start_line (Sift_crs.Item.span item) in
      Printf.sprintf "%s:%d" path line

let dialog_width width = min 72 (max 1 (width - 8))
let dialog_height height = min 12 (max 1 (height - 4))

let title_style theme =
  Mosaic.Ansi.Style.make
    ~fg:(style_fg ~default:theme.Theme.focus theme.normal)
    ~bold:true ()

let view ~(theme : Theme.t) ~width ~height t =
  box ~position:Absolute ~inset:(inset 0) ~z_index:30 ~flex_direction:Column
    ~align_items:Center ~justify_content:Flex_start
    ~padding:(padding_lrtb 0 0 (max 0 (height / 4)) 0)
    ~background:(Mosaic.Ansi.Color.of_rgba 0 0 0 150)
    ~size:{ width = pct 100; height = pct 100 }
    [
      box ~background:theme.panel ~padding:(padding_lrtb 4 4 1 1)
        ~flex_direction:Column ~gap:(gap_xy 0 1)
        ~size:
          {
            width = px (dialog_width width);
            height = px (dialog_height height);
          }
        ~min_size:{ width = px 0; height = px 0 }
        [
          box ~flex_direction:Row ~justify_content:Space_between
            ~size:{ width = pct 100; height = px 1 }
            [
              text ~style:(title_style theme) (title t.target);
              text ~style:theme.muted "esc";
            ];
          text ~style:theme.muted ~truncate:true (subtitle t);
          textarea ~id:"sift-comment-composer" ~autofocus:true
            ~value:t.draft.body ~placeholder:"Write a CR comment"
            ~text_color:(style_fg ~default:Mosaic.Ansi.Color.white theme.normal)
            ~focused_text_color:
              (style_fg ~default:Mosaic.Ansi.Color.white theme.normal)
            ~placeholder_color:
              (style_fg
                 ~default:(Mosaic.Ansi.Color.grayscale ~level:12)
                 theme.muted)
            ~background_color:theme.element
            ~focused_background_color:theme.element
            ~key_bindings
            ~size:{ width = pct 100; height = pct 100 }
            ~on_input:(fun body -> Some (Input body))
            ~on_submit:(fun body -> Some (Submit body))
            ();
          box ~flex_direction:Row ~justify_content:Flex_end ~gap:(gap_xy 3 0)
            ~size:{ width = pct 100; height = px 1 }
            [
              text ~style:theme.muted "enter submit";
              text ~style:theme.muted "shift+enter newline";
              text ~style:theme.muted "esc cancel";
            ];
        ];
    ]
