(** Contiguous hunks in a text diff. *)

type t
(** The type for validated hunks.

    A hunk has an old-file range, a new-file range, and a non-empty sequence of
    {!Line.t} values. The old range count must equal context plus removed lines.
    The new range count must equal context plus added lines. Empty ranges use
    start line [0], matching unified diff syntax such as ["@@ -0,0 +1,3 @@"]. *)

type row = { old_line : int option; new_line : int option; line : Line.t }
(** The type for rendered hunk rows with old and new line numbers.

    [old_line] is [None] for added lines. [new_line] is [None] for removed
    lines. *)

(** {1:constructors Constructors} *)

val make :
  old_start:int ->
  old_count:int ->
  new_start:int ->
  new_count:int ->
  Line.t list ->
  (t, Error.t) result
(** [make ~old_start ~old_count ~new_start ~new_count lines] is the hunk
    described by its ranges and [lines].

    Errors if ranges are invalid, [lines] is empty, or line counts disagree with
    line kinds. *)

val v :
  old_start:int ->
  old_count:int ->
  new_start:int ->
  new_count:int ->
  Line.t list ->
  t
(** [v ~old_start ~old_count ~new_start ~new_count lines] is the hunk described
    by its ranges and [lines].

    Raises [Invalid_argument] if the arguments do not describe a valid hunk. *)

(** {1:accessors Accessors} *)

val old_start : t -> int
(** [old_start t] is the first old-file line in [t]'s range. *)

val old_count : t -> int
(** [old_count t] is the old-file line count in [t]'s range. *)

val new_start : t -> int
(** [new_start t] is the first new-file line in [t]'s range. *)

val new_count : t -> int
(** [new_count t] is the new-file line count in [t]'s range. *)

val lines : t -> Line.t list
(** [lines t] is [t]'s lines in source order. *)

val rows : t -> row list
(** [rows t] is [t]'s lines annotated with old and new line numbers. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] have the same ranges and lines. *)

val compare : t -> t -> int
(** [compare a b] orders hunks by old range, new range, and lines. The order is
    compatible with {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] as a unified diff hunk. *)
