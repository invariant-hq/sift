(** Structured diff errors. *)

type kind =
  | Invalid_hunk of string
  | Invalid_file of string
  | Invalid_unified_diff of string
  | Invalid_context of int  (** The type for diff error kinds. *)

type t
(** The type for diff errors. *)

(** {1:constructors Constructors} *)

val make : kind -> t
(** [make kind] is an error of [kind]. *)

val with_line : int -> t -> t
(** [with_line line t] is [t] associated with input line [line].

    Raises [Invalid_argument] if [line] is less than [1]. *)

(** {1:accessors Accessors} *)

val kind : t -> kind
(** [kind t] is [t]'s error kind. *)

val line : t -> int option
(** [line t] is the 1-based input line associated with [t], if any. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] have the same kind. *)

val compare : t -> t -> int
(** [compare a b] orders errors. The order is compatible with {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] for humans. *)
