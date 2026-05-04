(** CR headers. *)

type t
(** The type for CR headers.

    A header contains the structured prefix of a CR comment: status, priority,
    reporter, and optional recipient. It does not contain the comment body. *)

(** {1:constructors Constructors} *)

val make :
  ?status:Status.t ->
  ?priority:Priority.t ->
  reporter:Handle.t ->
  ?recipient:Handle.t ->
  unit ->
  t
(** [make ~reporter ()] is a header with [reporter].

    [status] defaults to {!Status.CR}. [priority] defaults to {!Priority.Now}.
    [recipient] defaults to [None]. *)

(** {1:accessors Accessors} *)

val status : t -> Status.t
(** [status t] is [t]'s status. *)

val priority : t -> Priority.t
(** [priority t] is [t]'s priority. *)

val reporter : t -> Handle.t
(** [reporter t] is the handle that filed the CR. *)

val recipient : t -> Handle.t option
(** [recipient t] is the handle named by the [for] clause, if any. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] have the same fields. *)

val compare : t -> t -> int
(** [compare a b] orders headers. The order is compatible with {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] as a CR header without the trailing [:]. *)
