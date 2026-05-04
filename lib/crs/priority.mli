(** CR priority. *)

type t =
  | Now
  | Soon
  | Someday
      (** The type for CR priorities.

          [Now] is the default priority and has no suffix in CR syntax. [Soon]
          is written as [-soon]. [Someday] is written as [-someday]. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] are the same priority. *)

val compare : t -> t -> int
(** [compare a b] orders priorities. The order is compatible with {!val-equal}.
*)

(** {1:converting Converting} *)

val of_suffix : string -> t option
(** [of_suffix s] is the priority suffix named by [s], if any. Recognized
    suffixes are ["soon"] and ["someday"]. The empty suffix is not accepted;
    callers should use {!Now} for the default priority. *)

val suffix : t -> string
(** [suffix t] is the suffix used in CR syntax. [suffix Now] is [""]. *)

val to_string : t -> string
(** [to_string t] is a lowercase name for [t]. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] as a lowercase name. *)
