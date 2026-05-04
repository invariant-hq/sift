(** Structured CRS errors. *)

type kind =
  | Invalid_handle of string
  | Invalid_status of string
  | Invalid_priority of string
  | Invalid_header of string
  | Invalid_span of string
  | Invalid_anchor of string
  | Stale_item  (** The type for CRS error kinds. *)

type t
(** The type for CRS errors. *)

(** {1:constructors Constructors} *)

val make : kind -> t
(** [make kind] is an error of [kind]. *)

val with_span : Span.t -> t -> t
(** [with_span span t] is [t] associated with [span]. *)

(** {1:accessors Accessors} *)

val kind : t -> kind
(** [kind t] is [t]'s error kind. *)

val span : t -> Span.t option
(** [span t] is the source span associated with [t], if any. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] have the same kind and span. *)

val compare : t -> t -> int
(** [compare a b] orders errors. The order is compatible with {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] for humans. *)
