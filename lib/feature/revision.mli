(** Revision identifiers. *)

type t
(** The type for revision identifiers.

    A revision is a non-empty string supplied by a VCS bridge. The core feature
    library treats it as an opaque identifier and does not interpret its syntax.
*)

(** {1:constructors Constructors} *)

val v : string -> t
(** [v s] is [s] as a revision identifier.

    Raises [Invalid_argument] if [s] is empty. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] are the same revision. *)

val compare : t -> t -> int
(** [compare a b] orders revisions lexicographically. The order is compatible
    with {!val-equal}. *)

(** {1:converting Converting} *)

val to_string : t -> string
(** [to_string t] is [t]'s text. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t]. *)
