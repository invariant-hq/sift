(** Whole-feature approval state. *)

type t =
  | Pending
  | Approved
  | Seconded
      (** The type for whole-feature approval.

          [Pending] means the review has no final approval. [Approved] means the
          primary reviewer approves the feature. [Seconded] means approval has
          an additional seconding signal. *)

(** {1:predicates Predicates and comparisons} *)

val is_approved : t -> bool
(** [is_approved t] is [true] iff [t] is [Approved] or [Seconded]. *)

val is_seconded : t -> bool
(** [is_seconded t] is [true] iff [t] is [Seconded]. *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] are the same approval state. *)

val compare : t -> t -> int
(** [compare a b] orders approval states. The order is compatible with
    {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] for humans. *)
