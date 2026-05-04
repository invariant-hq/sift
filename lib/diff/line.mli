(** Lines in a text diff. *)

type kind =
  | Context
  | Added
  | Removed
      (** The type for line kinds.

          [Context] appears on both sides of a diff, [Added] only on the new
          side, and [Removed] only on the old side. *)

type t
(** The type for diff lines.

    The line text excludes the unified diff prefix character and excludes the
    trailing newline. *)

(** {1:constructors Constructors} *)

val make : kind -> text:string -> t
(** [make kind ~text] is a diff line of [kind] with [text]. *)

(** {1:accessors Accessors} *)

val kind : t -> kind
(** [kind t] is [t]'s kind. *)

val text : t -> string
(** [text t] is [t]'s text without a diff prefix or trailing newline. *)

(** {1:predicates Predicates and comparisons} *)

val is_change : t -> bool
(** [is_change t] is [true] iff [kind t] is [Added] or [Removed]. *)

val equal_kind : kind -> kind -> bool
(** [equal_kind a b] is [true] iff [a] and [b] are the same kind. *)

val compare_kind : kind -> kind -> int
(** [compare_kind a b] orders line kinds. The order is compatible with
    {!val-equal_kind}. *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] have the same kind and text. *)

val compare : t -> t -> int
(** [compare a b] orders lines. The order is compatible with {!val-equal}. *)

(** {1:fmt Formatting} *)

val prefix : kind -> char
(** [prefix kind] is [kind]'s unified diff prefix. *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] as a unified diff line. *)
