(** Diff pane rendering. *)

val focus_id : string
(** [focus_id] is the stable renderable id for the diff scroll surface. *)

type msg
(** The type for diff-pane messages. *)

type t
(** The type for diff-pane models.

    A value owns only the diff-local line selection. The displayed target
    remains a parent prop because it is derived from the review cursor and
    source resolver. *)

val make : unit -> t
(** [make ()] is a diff-pane model with no selected line. *)

val activate : msg
(** [activate] selects a line in the current target when the diff pane receives
    focus. *)

val update : target:Diff_target.t -> msg -> t -> t * msg Mosaic.Cmd.t
(** [update ~target msg t] updates the diff-local model for [msg]. *)

val selected_scope : t -> target:Diff_target.t -> Sift_review.Scope.t option
(** [selected_scope t ~target] is the selected source line as a review scope,
    if [target] can resolve it. *)

val view :
  t ->
  theme:Theme.t ->
  review:Sift_review.t ->
  target:Diff_target.t ->
  layout:Mosaic.Diff.layout ->
  show_line_numbers:bool ->
  wrap:Mosaic.Text_surface.wrap ->
  focused:bool ->
  msg Mosaic.t
(** [view] renders the diff surface for [target]. *)
