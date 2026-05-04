(** Structured review errors.

    Review errors report stale or out-of-model selections. Invalid constructor
    arguments in pure value modules raise [Invalid_argument]; only operations
    that validate against a concrete {!Sift_review.t} return this type. *)

(** The type for structured review errors. *)
type t =
  | Invalid_scope of Scope.t
      (** A scope cannot be represented in the reviewed feature. *)
  | Invalid_cursor of Cursor.t
      (** A cursor cannot select an item in the review. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] are the same review error. *)

val compare : t -> t -> int
(** [compare a b] orders errors. The order is compatible with {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] for humans. *)
