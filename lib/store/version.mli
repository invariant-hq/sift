(** Store schema versions. *)

type t
(** The type for supported store schema versions.

    A version is a positive integer. Unknown positive versions can be decoded by
    migrations, but writers should use {!val-current}. *)

(** {1:versions Versions} *)

val current : t
(** [current] is the schema version written by the current store model. *)

val of_int : int -> (t, Error.t) result
(** [of_int n] decodes [n] as a schema version.

    Errors if [n] is not positive. Use {!v} when [n] is caller-controlled and
    invalid input is a programming error. *)

val v : int -> t
(** [v n] is [n] as a schema version.

    Raises [Invalid_argument] if [n] is not positive. *)

val to_int : t -> int
(** [to_int t] is [t]'s integer representation. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] are the same schema version. *)

val compare : t -> t -> int
(** [compare a b] orders versions numerically. The order is compatible with
    {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] as an integer. *)
