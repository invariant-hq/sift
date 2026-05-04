(** Durable review scopes. *)

type path = string
(** The type for repository-relative display paths. *)

type line = int
(** The type for one-based source line numbers. *)

type side =
  | Old
  | New
      (** The type for the side of a changed line.

          [Old] identifies a line in the feature base. [New] identifies a line
          in the feature tip. *)

type hunk = private {
  path : path;
  old_start : line;
  old_count : int;
  new_start : line;
  new_count : int;
}
(** The type for durable hunk positions.

    [path] is the file display path. Counts are non-negative. A start line is
    [0] only when the corresponding count is [0], matching unified diff empty
    ranges. Otherwise start lines are one-based. *)

type view =
  | Feature
  | File of path
  | Hunk of hunk
  | Line of side * path * line
      (** The type for scope views.

          [Feature] selects the whole feature. [File path] selects one file.
          [Hunk h] selects one diff hunk. [Line (side, path, line)] selects one
          old or new source line. *)

type t
(** The type for review scopes.

    Scopes are pure, durable positions suitable for local review marks. They do
    not encode storage keys, VCS object names, or filesystem state.

    Invariant: file paths are non-empty; line numbers are one-based; hunk counts
    are non-negative; empty hunk ranges have start line [0]. *)

(** {1:constructors Constructors} *)

val feature : t
(** [feature] is the whole-feature scope. *)

val file : path -> t
(** [file path] is a file scope for [path].

    Raises [Invalid_argument] if [path] is empty. *)

val hunk :
  path:path ->
  old_start:line ->
  old_count:int ->
  new_start:line ->
  new_count:int ->
  t
(** [hunk ~path ~old_start ~old_count ~new_start ~new_count] is a hunk scope, if
    the arguments describe a valid hunk position.

    Raises [Invalid_argument] if [path] is empty, if a count is negative, if a
    start line is negative, or if a start line is [0] while the corresponding
    count is positive. *)

val of_hunk : path:path -> Sift_diff.Hunk.t -> t
(** [of_hunk ~path hunk] is the scope corresponding to [hunk] at [path].

    Raises [Invalid_argument] if [path] is empty. *)

val old_line : path:path -> line:line -> t
(** [old_line ~path ~line] is an old-side line scope.

    Raises [Invalid_argument] if [path] is empty or [line < 1]. *)

val new_line : path:path -> line:line -> t
(** [new_line ~path ~line] is a new-side line scope.

    Raises [Invalid_argument] if [path] is empty or [line < 1]. *)

(** {1:accessors Accessors} *)

val view : t -> view
(** [view t] is [t]'s view. *)

val path : t -> path option
(** [path t] is [t]'s file path, if [t] is not {!val-feature}. *)

(** {1:predicates Predicates and comparisons} *)

val contains : t -> t -> bool
(** [contains outer inner] is [true] iff [outer] covers [inner].

    The whole-feature scope covers every scope. File scopes cover hunks and
    lines with the same path. Hunk scopes cover old and new line scopes whose
    line number lies in the corresponding hunk range. Line scopes cover only
    equal line scopes. *)

val equal_side : side -> side -> bool
(** [equal_side a b] is [true] iff [a] and [b] are the same side. *)

val compare_side : side -> side -> int
(** [compare_side a b] orders sides. The order is compatible with
    {!val-equal_side}. *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] describe the same scope. *)

val compare : t -> t -> int
(** [compare a b] orders scopes by breadth and source position. The order is
    compatible with {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] for humans. *)
