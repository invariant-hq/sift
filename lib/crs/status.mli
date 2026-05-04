(** CR status. *)

type t =
  | CR
  | XCR
      (** The type for CR statuses.

          [CR] is an unresolved review comment. [XCR] is a resolved review
          comment left in source until the reporter accepts the resolution. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] are the same status. *)

val compare : t -> t -> int
(** [compare a b] orders statuses. The order is compatible with {!val-equal}. *)

(** {1:converting Converting} *)

val of_string : string -> t option
(** [of_string s] is the status named by [s], if any. Recognized strings are
    ["CR"] and ["XCR"]. *)

val to_string : t -> string
(** [to_string t] is [t] as written in a CR header. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] as written in a CR header. *)
