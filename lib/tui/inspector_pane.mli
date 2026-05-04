(** Inspector pane rendering. *)

type target =
  | Feature of Sift_feature.t
  | File of Sift_diff.File.t
  | Hunk of Sift_review.Scope.hunk
  | Line of
      Sift_review.Scope.side * Sift_review.Scope.path * Sift_review.Scope.line
  | Cr of int * Sift_crs.Item.t
      (** The type for the inspector payload selected by the current cursor. *)

val default_width : int
(** [default_width] is the standard inspector pane width. *)

val view :
  theme:Theme.t ->
  review:Sift_review.t ->
  target:target option ->
  width:int ->
  'msg Mosaic.t
(** [view] renders the inspector surface. *)
