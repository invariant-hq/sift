(** Derived TUI context for a review cursor.

    [Review_context] is a pure helper for the Sift TUI. It resolves the current
    {!Sift_review.Cursor.t} plus UI selection hints to the file, path, line, and
    CR item the user is focused on. It performs no effects and owns no state. *)

type line = { side : Sift_review.Scope.side; number : Sift_review.Scope.line }
(** The type for a source line in the current review context. *)

type cr = { index : int; item : Sift_crs.Item.t }
(** The type for a CR item selected by the review cursor. *)

type t
(** The type for resolved review context. *)

(** {1:constructors Constructors} *)

val v :
  review:Sift_review.t ->
  selected_file:int option ->
  selected_cr:int option ->
  t
(** [v ~review ~selected_file ~selected_cr] is the review context for [review].

    The review cursor is authoritative. [selected_file] is used only when the
    cursor does not identify a file directly. [selected_cr] is accepted so
    callers can pass their row selections uniformly; it does not override the
    cursor. Invalid indexes are ignored. *)

(** {1:accessors Accessors} *)

val review : t -> Sift_review.t
(** [review t] is the review used to derive [t]. *)

val cursor : t -> Sift_review.Cursor.t
(** [cursor t] is the current review cursor. *)

val scope : t -> Sift_review.Scope.t option
(** [scope t] is the scope selected by [cursor t], if any. *)

val cr : t -> cr option
(** [cr t] is the CR item selected by [cursor t], if any. Row selection hints do
    not make a CR current. *)

val file : t -> Sift_diff.File.t option
(** [file t] is the file associated with [scope t], [cr t], or the selected file
    hint, if any. *)

val path : t -> string option
(** [path t] is the path associated with [file t], [scope t], or [cr t], if any.
*)

val line : t -> line option
(** [line t] is the source line selected by [scope t] or [cr t], if any. CR
    source lines are reported on the {!Sift_review.Scope.New} side. *)
