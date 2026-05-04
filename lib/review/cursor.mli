(** Review navigation cursors. *)

type cr_index = int
(** The type for zero-based CR item indexes in a review.

    Values supplied to cursor constructors must be non-negative. *)

type target =
  | Scope of Scope.t
  | Cr of cr_index
      (** The type for cursor targets.

          [Scope scope] selects reviewable diff scope [scope]. [Cr i] selects
          the [i]th CR item in the review's CR index. *)

type move =
  | First
  | Previous
  | Next
  | Last  (** The type for cursor movement requests. *)

type t
(** The type for review cursors.

    A cursor is a pure selection. It is validated against a concrete
    {!Sift_review.t} by {!Sift_review.set_cursor} and
    {!Sift_review.move_cursor}. *)

(** {1:constructors Constructors} *)

val feature : t
(** [feature] selects the whole-feature scope. *)

val scope : Scope.t -> t
(** [scope s] selects [s]. *)

val cr : cr_index -> t
(** [cr i] selects CR item index [i].

    Raises [Invalid_argument] if [i < 0]. *)

(** {1:accessors Accessors} *)

val target : t -> target
(** [target t] is [t]'s target. *)

val selected_scope : t -> Scope.t option
(** [selected_scope t] is the selected scope, if [target t] is [Scope _]. *)

val selected_cr : t -> cr_index option
(** [selected_cr t] is the selected CR item index, if [target t] is [Cr _]. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] select the same target. *)

val compare : t -> t -> int
(** [compare a b] orders cursors. The order is compatible with {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] for humans. *)
