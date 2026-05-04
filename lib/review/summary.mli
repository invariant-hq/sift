(** Review progress summaries. *)

type t
(** The type for review progress summaries.

    Progress is measured over review units derived from the feature diff:
    changed old and new line scopes for text files, plus one file scope for each
    binary file. Broader marks cover the units contained by their scope. *)

(**/**)

val v :
  total:int ->
  reviewed:int ->
  cr_items:int ->
  valid_cr_items:int ->
  approval:Approval.t ->
  t

(**/**)

(** {1:accessors Accessors} *)

val total : t -> int
(** [total t] is the number of review units. *)

val reviewed : t -> int
(** [reviewed t] is the number of reviewed units. *)

val remaining : t -> int
(** [remaining t] is [total t - reviewed t]. *)

val progress : t -> float
(** [progress t] is [reviewed t /. total t].

    It is [1.0] when [total t = 0]. *)

val is_complete : t -> bool
(** [is_complete t] is [true] iff [remaining t = 0]. *)

val cr_items : t -> int
(** [cr_items t] is the number of CR items in the review index. *)

val valid_cr_items : t -> int
(** [valid_cr_items t] is the number of syntactically valid CR items. *)

val invalid_cr_items : t -> int
(** [invalid_cr_items t] is [cr_items t - valid_cr_items t]. *)

val approval : t -> Approval.t
(** [approval t] is the whole-feature approval state summarized by [t]. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] have the same counts and approval
    state. *)

val compare : t -> t -> int
(** [compare a b] orders summaries. The order is compatible with {!val-equal}.
*)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] for humans. *)
