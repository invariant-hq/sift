(** User handles in CR syntax. *)

type t
(** The type for user handles.

    A handle is non-empty and contains only ASCII letters, digits, [-], [_],
    [.], [[] and []]. The square brackets allow common bot handles such as
    [dependabot[bot]]. *)

(** {1:constructors Constructors} *)

val of_string : string -> (t, Error.t) result
(** [of_string s] is [s] as a handle.

    Errors if [s] is empty or contains a character outside the handle character
    set. *)

val v : string -> t
(** [v s] is [s] as a handle.

    Raises [Invalid_argument] if [s] is not a valid handle. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] are the same handle. *)

val compare : t -> t -> int
(** [compare a b] orders handles lexicographically. The order is compatible with
    {!val-equal}. *)

(** {1:converting Converting} *)

val to_string : t -> string
(** [to_string t] is the handle text. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] as written in CR syntax. *)
