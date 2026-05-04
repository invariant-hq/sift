(** Pure source edits for CR comments. *)

type anchor =
  | Before_line of int
  | After_line of int
  | End_of_file
      (** The type for CR insertion anchors.

          Line numbers are 1-based. [Before_line n] inserts before line [n].
          [After_line n] inserts after line [n]. [End_of_file] appends to the
          end of the source text. *)

type t
(** The type for pure source edits.

    An edit describes a byte-range replacement in one source string. Applying an
    edit has no filesystem effects. *)

(** {1:constructors Constructors} *)

val attach :
  source:string ->
  syntax:Syntax.t ->
  anchor:anchor ->
  Comment.t ->
  (t, Error.t) result
(** [attach ~source ~syntax ~anchor c] is an edit that inserts [c] in [source]
    at [anchor], rendered with [syntax].

    Errors if [anchor] does not point into [source]. *)

val replace : Item.t -> Comment.t -> (t, Error.t) result
(** [replace o c] is an edit that replaces [o] by [c], preserving [o]'s source
    comment syntax.

    Errors if [o] is invalid. *)

val remove : Item.t -> t
(** [remove o] is an edit that removes [o]. *)

(** {1:accessors Accessors} *)

val start_offset : t -> int
(** [start_offset t] is the first byte replaced by [t]. *)

val stop_offset : t -> int
(** [stop_offset t] is the first byte after the range replaced by [t]. *)

val replacement : t -> string
(** [replacement t] is the replacement text inserted by [t]. *)

(** {1:applying Applying} *)

val apply : t -> source:string -> (string, Error.t) result
(** [apply t ~source] applies [t] to [source].

    Errors if [t]'s range does not point into [source]. *)
