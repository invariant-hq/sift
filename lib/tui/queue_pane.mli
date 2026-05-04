(** Review queue pane rendering. *)

val default_width : int
(** [default_width] is the standard queue pane width. *)

val focus_id : string
(** [focus_id] is the stable renderable id for the queue selection surface. *)

val view :
  theme:Theme.t ->
  rows:Review_queue.row list ->
  selected_index:int option ->
  refresh_notice:Refresh_notice.t option ->
  width:int ->
  compact:bool ->
  focused:bool ->
  wrap_navigation:bool ->
  on_key:(Mosaic.Event.key -> 'msg option) ->
  on_select:(int -> 'msg) ->
  on_activate:(int -> 'msg) ->
  'msg Mosaic.t
(** [view] renders the review queue surface. *)
