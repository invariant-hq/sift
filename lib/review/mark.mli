(** Reviewed and unreviewed marks. *)

type state =
  | Reviewed
  | Unreviewed
      (** The type for mark states.

          [Reviewed] marks a scope as reviewed. [Unreviewed] clears or overrides
          a broader reviewed mark for a narrower scope. *)

type t
(** The type for review marks.

    A mark assigns a review state to one {!Scope.t}. When several marks cover a
    scope, the most specific mark determines the effective state. *)

(** {1:constructors Constructors} *)

val make : Scope.t -> state -> t
(** [make scope state] is a mark of [scope] with [state]. *)

val reviewed : Scope.t -> t
(** [reviewed scope] is [make scope Reviewed]. *)

val unreviewed : Scope.t -> t
(** [unreviewed scope] is [make scope Unreviewed]. *)

(** {1:accessors Accessors} *)

val scope : t -> Scope.t
(** [scope t] is [t]'s marked scope. *)

val state : t -> state
(** [state t] is [t]'s state. *)

(** {1:predicates Predicates and comparisons} *)

val is_reviewed : t -> bool
(** [is_reviewed t] is [true] iff [state t] is [Reviewed]. *)

val is_unreviewed : t -> bool
(** [is_unreviewed t] is [true] iff [state t] is [Unreviewed]. *)

val equal_state : state -> state -> bool
(** [equal_state a b] is [true] iff [a] and [b] are the same mark state. *)

val compare_state : state -> state -> int
(** [compare_state a b] orders mark states. The order is compatible with
    {!val-equal_state}. *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] mark the same scope with the same
    state. *)

val compare : t -> t -> int
(** [compare a b] orders marks by scope and state. The order is compatible with
    {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] for humans. *)
