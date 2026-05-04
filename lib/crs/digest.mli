(** Stable CR digests. *)

type t
(** The type for stable CR digests.

    A digest identifies CR text while ignoring position and insignificant
    whitespace changes. It is intended for matching CRs across line shifts and
    small formatting changes. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] are the same digest. *)

val compare : t -> t -> int
(** [compare a b] orders digests lexicographically. The order is compatible with
    {!val-equal}. *)

(** {1:converting Converting} *)

val create : string -> t
(** [create s] is a stable digest for [s], after normalizing insignificant
    whitespace. *)

val of_string : string -> t option
(** [of_string s] is [Some t] if [s] is a lowercase hexadecimal digest. *)

val to_string : t -> string
(** [to_string t] is [t]'s lowercase hexadecimal representation. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] as lowercase hexadecimal. *)
