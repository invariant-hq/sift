(** File-level diffs. *)

type status =
  | Added
  | Deleted
  | Modified
  | Renamed
  | Copied  (** The type for file-level change status. *)

type text = Hunk.t list
(** The type for text file diff hunks. *)

type content =
  | Text of text
  | Binary
      (** The type for file diff content.

          [Text hunks] is a text diff. [Binary] is a binary file diff whose
          byte-level content is not represented. *)

type t
(** The type for file-level diffs.

    A file has an optional old path, an optional new path, a status, and text or
    binary content. At least one path is present. Mode changes are not
    represented in this core model. *)

(** {1:constructors Constructors} *)

val make :
  ?old_path:string ->
  ?new_path:string ->
  status:status ->
  content ->
  (t, Error.t) result
(** [make ?old_path ?new_path ~status content] is a file diff.

    Errors if both paths are absent, if [status] is inconsistent with the
    missing path, or if text hunks overlap. *)

val v : ?old_path:string -> ?new_path:string -> status:status -> content -> t
(** [v ?old_path ?new_path ~status content] is a file diff.

    Raises [Invalid_argument] if the arguments do not describe a valid file
    diff. *)

(** {1:accessors Accessors} *)

val old_path : t -> string option
(** [old_path t] is [t]'s old path, if any. *)

val new_path : t -> string option
(** [new_path t] is [t]'s new path, if any. *)

val path : t -> string
(** [path t] is [new_path t] if present, otherwise [old_path t].

    This is the path normally shown in file lists. *)

val status : t -> status
(** [status t] is [t]'s file-level status. *)

val content : t -> content
(** [content t] is [t]'s content. *)

val hunks : t -> Hunk.t list
(** [hunks t] is [t]'s hunks. It is [[]] for binary diffs. *)

(** {1:predicates Predicates and comparisons} *)

val is_text : t -> bool
(** [is_text t] is [true] iff [content t] is [Text _]. *)

val is_binary : t -> bool
(** [is_binary t] is [true] iff [content t] is [Binary]. *)

val is_empty : t -> bool
(** [is_empty t] is [true] iff [t] has no represented text changes. *)

val equal_status : status -> status -> bool
(** [equal_status a b] is [true] iff [a] and [b] are the same status. *)

val compare_status : status -> status -> int
(** [compare_status a b] orders statuses. The order is compatible with
    {!val-equal_status}. *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] describe the same file diff. *)

val compare : t -> t -> int
(** [compare a b] orders file diffs by display path and content. The order is
    compatible with {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] as a unified file diff. *)
