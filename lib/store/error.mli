(** Structured store errors.

    Store errors report recoverable persistence failures: invalid encoded data
    and filesystem bridge failures. Invalid arguments passed to pure
    constructors raise [Invalid_argument]. *)

(** The type for store errors. *)
type t =
  | Invalid_version of int  (** An encoded schema version is not supported. *)
  | Invalid_key of string  (** An encoded key is malformed. *)
  | Invalid_path of string
      (** An encoded repository or filesystem path is invalid. *)
  | Invalid_range of { first : int; last : int }
      (** An encoded line or hunk range is invalid. *)
  | Duplicate_mark  (** Encoded marks contain duplicate scope identities. *)
  | Duplicate_cr  (** Encoded CR records contain duplicate identities. *)
  | Decode of string  (** Encoded data does not match the expected schema. *)
  | Io of string  (** A filesystem bridge reported an effect failure. *)

val message : t -> string
(** [message t] is a human-readable error message. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] are the same store error. *)

val compare : t -> t -> int
(** [compare a b] orders errors. The order is compatible with {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t]. *)
