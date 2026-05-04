(** Structured feature errors. *)

type t =
  | Invalid_revision of string
  | Invalid_title  (** The type for feature errors. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] are the same feature error. *)

val compare : t -> t -> int
(** [compare a b] orders errors. The order is compatible with {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] for humans. *)
