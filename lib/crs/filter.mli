(** Item filters. *)

type t =
  | All
  | Invalid
  | Status of Status.t
  | Priority of Priority.t
  | Reporter of Handle.t
  | Recipient of Handle.t option  (** The type for item filters. *)

(** {1:matching Matching} *)

val matches : t -> Item.t -> bool
(** [matches f o] is [true] iff [o] satisfies [f]. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] are the same filter. *)

val compare : t -> t -> int
(** [compare a b] orders filters. The order is compatible with {!val-equal}. *)

(** {1:converting Converting} *)

val to_string : t -> string
(** [to_string t] is a lowercase command-line representation of [t]. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] for humans. *)
