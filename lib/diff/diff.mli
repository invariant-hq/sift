(** Multi-file diffs. *)

type t
(** The type for multi-file diffs.

    A diff is an ordered list of file-level diffs. In Sift this is the content
    of a feature: the changes from a base revision to a tip revision. *)

(** {1:constructors Constructors} *)

val empty : t
(** [empty] is the empty diff. *)

val make : File.t list -> t
(** [make files] is a diff containing [files] in order. *)

(** {1:accessors Accessors} *)

val files : t -> File.t list
(** [files t] is [t]'s file diffs in order. *)

val file_count : t -> int
(** [file_count t] is [List.length (files t)]. *)

(** {1:predicates Predicates and comparisons} *)

val is_empty : t -> bool
(** [is_empty t] is [true] iff [files t] is [[]]. *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] have the same files. *)

val compare : t -> t -> int
(** [compare a b] orders diffs by their files. The order is compatible with
    {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] as a unified multi-file diff. *)
