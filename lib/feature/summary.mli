(** Feature summaries. *)

type t
(** The type for feature summaries.

    A summary contains derived diff counts useful for navigation, status bars,
    and review dashboards. *)

(**/**)

val of_diff : Sift_diff.t -> t

(**/**)

(** {1:accessors Accessors} *)

val files : t -> int
(** [files t] is the number of file diffs. *)

val text_files : t -> int
(** [text_files t] is the number of text file diffs. *)

val binary_files : t -> int
(** [binary_files t] is the number of binary file diffs. *)

val hunks : t -> int
(** [hunks t] is the number of text hunks. *)

val added_lines : t -> int
(** [added_lines t] is the number of added lines. *)

val removed_lines : t -> int
(** [removed_lines t] is the number of removed lines. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] have the same counts. *)

val compare : t -> t -> int
(** [compare a b] orders summaries by their counts. The order is compatible with
    {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] for humans. *)
