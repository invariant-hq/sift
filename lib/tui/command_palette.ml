open Mosaic

type group = Review | Navigation | View | Session
type 'a item = { group : group; key : string; label : string; value : 'a }
type 'a event = Activated of 'a | Closed

type msg =
  | Insert_text of string
  | Set_query of string
  | Backspace
  | Select of int
  | Move_selection of int
  | Activate_selected
  | Close

type 'a t = {
  items : 'a item list;
  query : string;
  selected : int;
}

let item group ~key ~label value = { group; key; label; value }

let make items = { items; query = ""; selected = 0 }

let clamp_index length index =
  if length <= 0 then 0
  else if index < 0 then 0
  else if index >= length then length - 1
  else index

let utf8_of_uchar uchar =
  let buffer = Buffer.create (Uchar.utf_8_byte_length uchar) in
  Buffer.add_utf_8_uchar buffer uchar;
  Buffer.contents buffer

let drop_last_utf8 text =
  let length = String.length text in
  if length = 0 then text
  else
    let index = ref (length - 1) in
    while !index > 0 && Char.code text.[!index] land 0xc0 = 0x80 do
      decr index
    done;
    String.sub text 0 !index

let key_text key =
  let data = Event.Key.data key in
  match data.event_type with
  | Matrix.Input.Key.Release -> None
  | Press | Repeat -> (
      let modifier = data.modifier in
      if
        modifier.ctrl || modifier.alt || modifier.super || modifier.hyper
        || modifier.meta
      then None
      else
        match data.key with
        | Char uchar -> Some (utf8_of_uchar uchar)
        | _ -> None)

let group_search_label = function
  | Review -> "review"
  | Navigation -> "navigation"
  | View -> "view"
  | Session -> "session"

let contains_substring ~needle text =
  let needle_length = String.length needle in
  let text_length = String.length text in
  if needle_length = 0 then true
  else if needle_length > text_length then false
  else
    let rec loop index =
      if index + needle_length > text_length then false
      else if String.equal needle (String.sub text index needle_length) then
        true
      else loop (index + 1)
    in
    loop 0

let item_matches query item =
  let query = String.lowercase_ascii (String.trim query) in
  String.equal query ""
  ||
  let matches text =
    contains_substring ~needle:query (String.lowercase_ascii text)
  in
  matches item.label || matches item.key || matches (group_search_label item.group)

let items t = List.filter (item_matches t.query) t.items
let selected_index t = clamp_index (List.length (items t)) t.selected

let message_of_key key =
  if Shortcut.matches Shortcut.escape key then Some Close
  else if Shortcut.matches Shortcut.enter key then Some Activate_selected
  else if Shortcut.matches Shortcut.backspace key then Some Backspace
  else if Shortcut.matches Shortcut.down key then Some (Move_selection 1)
  else if Shortcut.matches (Shortcut.char 'j') key then Some (Move_selection 1)
  else if Shortcut.matches Shortcut.up key then Some (Move_selection (-1))
  else if Shortcut.matches (Shortcut.char 'k') key then
    Some (Move_selection (-1))
  else Option.map (fun text -> Insert_text text) (key_text key)

let update msg t =
  match msg with
  | Insert_text text ->
      ({ t with query = t.query ^ text; selected = 0 }, Cmd.none, None)
  | Set_query query -> ({ t with query; selected = 0 }, Cmd.none, None)
  | Backspace ->
      ({ t with query = drop_last_utf8 t.query; selected = 0 }, Cmd.none, None)
  | Select selected ->
      ( { t with selected = clamp_index (List.length (items t)) selected },
        Cmd.none,
        None )
  | Move_selection delta ->
      let selected = clamp_index (List.length (items t)) (t.selected + delta) in
      ({ t with selected }, Cmd.none, None)
  | Activate_selected ->
      let items = items t in
      let event =
        match List.nth_opt items (selected_index t) with
        | None -> None
        | Some item -> Some (Activated item.value)
      in
      (t, Cmd.none, event)
  | Close -> (t, Cmd.none, Some Closed)

let group_label = function
  | Review -> "Review"
  | Navigation -> "Navigation"
  | View -> "View"
  | Session -> "Session"

let dialog_width width = min 60 (max 1 (width - 2))

let style_fg ~default (style : Mosaic.Ansi.Style.t) =
  Option.value ~default style.fg

let group_style theme =
  Mosaic.Ansi.Style.make
    ~fg:(style_fg ~default:theme.Theme.focus theme.cr)
    ~bold:true ()

type 'a row = Spacer | Header of group | Item of int * 'a item

let row_items items =
  let rec loop previous_group index acc = function
    | [] -> List.rev acc
    | item :: rest ->
        let acc =
          if Some item.group = previous_group then acc
          else if Option.is_none previous_group then Header item.group :: acc
          else Header item.group :: Spacer :: acc
        in
        loop (Some item.group) (index + 1) (Item (index, item) :: acc) rest
  in
  loop None 0 [] items

let row_count items = List.length (row_items items)

let dialog_height height items =
  min (max 12 (row_count items + 7)) (max 1 (height - 4))

let selected_y rows selected_index =
  let rec loop y = function
    | [] -> None
    | Item (index, _) :: _ when index = selected_index -> Some y
    | _ :: rest -> loop (y + 1) rest
  in
  loop 0 rows

let reveal_request selected_index selected_y : Mosaic.Scroll_box.reveal =
  {
    key = Printf.sprintf "command-palette-%d" selected_index;
    x = None;
    y = Some selected_y;
    align_x = `Nearest;
    align_y = `Nearest;
    margin = 1;
  }

let item_row theme ~selected ~index item =
  let style = if selected then theme.Theme.selected else theme.normal in
  let key_style = if selected then theme.selected else theme.muted in
  let background = if selected then theme.selection else theme.panel in
  box ~flex_direction:Row ~gap:(gap_xy 2 0) ~background
    ~padding:(padding_lrtb 1 1 0 0)
    ~on_mouse:(fun ev ->
      match Event.Mouse.kind ev with
      | Move | Over _ ->
          Event.Mouse.stop_propagation ev;
          Some (Select index)
      | Down { button = Left } ->
          Event.Mouse.stop_propagation ev;
          Some (Select index)
      | Up { button = Left; _ } ->
          Event.Mouse.stop_propagation ev;
          Some (Select index)
      | _ -> None)
    ~size:{ width = pct 100; height = px 1 }
    [
      text ~style ~truncate:true ~flex_grow:1.
        ~min_size:{ width = px 0; height = px 0 }
        item.label;
      text ~style:key_style ~truncate:true ~flex_shrink:0.
        ~size:{ width = px 12; height = px 1 }
        item.key;
    ]

let rows theme ~selected_index items =
  match items with
  | [] -> [ text ~style:theme.Theme.muted "No matching commands" ]
  | _ ->
      List.map
        (function
          | Spacer -> text ""
          | Header group -> text ~style:(group_style theme) (group_label group)
          | Item (index, item) ->
              item_row theme ~selected:(index = selected_index) ~index item)
        (row_items items)

let handled_key key msg =
  Event.Key.prevent_default key;
  Some msg

let input_key key =
  if Shortcut.matches Shortcut.escape key then handled_key key Close
  else if Shortcut.matches Shortcut.enter key then
    handled_key key Activate_selected
  else if Shortcut.matches Shortcut.down key then
    handled_key key (Move_selection 1)
  else if Shortcut.matches (Shortcut.char 'j') key then
    handled_key key (Move_selection 1)
  else if Shortcut.matches Shortcut.up key then
    handled_key key (Move_selection (-1))
  else if Shortcut.matches (Shortcut.char 'k') key then
    handled_key key (Move_selection (-1))
  else None

let query_row theme query =
  box ~flex_direction:Row ~gap:(gap_xy 1 0) ~background:theme.Theme.element
    ~padding:(padding_lrtb 1 1 0 0)
    ~size:{ width = pct 100; height = px 1 }
    [
      text ~style:theme.muted ~flex_shrink:0. ">";
      input ~id:"sift-command-palette-filter" ~autofocus:true ~value:query
        ~placeholder:"Filter commands"
        ~text_color:(style_fg ~default:Mosaic.Ansi.Color.white theme.normal)
        ~focused_text_color:
          (style_fg ~default:Mosaic.Ansi.Color.white theme.normal)
        ~placeholder_color:
          (style_fg
             ~default:(Mosaic.Ansi.Color.grayscale ~level:12)
             theme.subtle)
        ~background_color:theme.element ~focused_background_color:theme.element
        ~cursor_style:`Line
        ~cursor_color:(style_fg ~default:theme.focus theme.normal)
        ~on_key:input_key
        ~on_input:(fun query -> Some (Set_query query))
        ~flex_grow:1.
        ~min_size:{ width = px 0; height = px 0 }
        ();
    ]

let view t ~(theme : Theme.t) ~width ~height =
  let query = t.query in
  let items = items t in
  let selected_index = selected_index t in
  let row_items = row_items items in
  let reveal =
    selected_y row_items selected_index
    |> Option.map (reveal_request selected_index)
  in
  box ~position:Absolute ~inset:(inset 0) ~z_index:20 ~flex_direction:Column
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
            height = px (dialog_height height items);
          }
        ~min_size:{ width = px 0; height = px 0 }
        [
          box ~flex_direction:Row ~justify_content:Space_between
            ~size:{ width = pct 100; height = px 1 }
            [
              text
                ~style:
                  (Mosaic.Ansi.Style.make
                     ~fg:(style_fg ~default:theme.focus theme.normal)
                     ~bold:true ())
                "Commands";
              text ~style:theme.muted "esc";
            ];
          query_row theme query;
          scroll_box ~scroll_y:true ~scroll_x:false ~background:theme.panel
            ?reveal
            ~size:{ width = pct 100; height = pct 100 }
            [
              box ~flex_direction:Column
                ~size:{ width = pct 100; height = auto }
                (rows theme ~selected_index items);
            ];
        ];
    ]
