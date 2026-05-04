(** Pure code review state.

    [Sift_review] models the local state of a review for one {!Sift_feature.t}:
    CR items discovered in source text, reviewed marks, whole-feature approval,
    the current cursor, and a derived progress summary. It performs no
    filesystem, VCS, network, or persistence effects. *)

(** {1:model Model} *)

module Scope = Scope
(** Durable review scopes. *)

module Mark = Mark
(** Reviewed and unreviewed marks. *)

module Approval = Approval
(** Whole-feature approval state. *)

module Cursor = Cursor
(** Review navigation cursors. *)

module Summary = Summary
(** Review progress summaries. *)

module Error = Error
(** Structured review errors. *)

type t
(** The type for pure review state.

    A review owns one feature, a CR item index in source order, at most one mark
    for each exact scope, one approval state, and one cursor. Transforming a
    review returns a new value and leaves the original unchanged. *)

(** {1:constructors Constructors} *)

val v : feature:Sift_feature.t -> cr_items:Sift_crs.Item.t list -> t
(** [v ~feature ~cr_items] is a pending review for [feature] with [cr_items]
    indexed in the supplied order.

    The initial cursor selects {!Scope.feature}. *)

val refresh : t -> feature:Sift_feature.t -> cr_items:Sift_crs.Item.t list -> t
(** [refresh t ~feature ~cr_items] is [t] moved to a newer view of the same
    logical review.

    If [feature]'s content is unchanged, reviewed marks and approval are
    preserved. Feature titles are display metadata and do not affect content
    freshness. If the feature content changed, broad reviewed marks from [t] are
    first expanded to the concrete review units they covered; only still-valid
    line units with matching content evidence are carried forward, and approval
    returns to {!Approval.Pending}. The cursor is preserved when it still
    selects a valid scope or CR item, and otherwise returns to {!Scope.feature}.
*)

(** {1:accessors Accessors} *)

val feature : t -> Sift_feature.t
(** [feature t] is the feature under review. *)

val cr_items : t -> Sift_crs.Item.t list
(** [cr_items t] is [t]'s CR item index in source order. *)

val cr_count : t -> int
(** [cr_count t] is [List.length (cr_items t)]. *)

val cr_item : t -> int -> Sift_crs.Item.t option
(** [cr_item t i] is the CR item at zero-based index [i], if any. *)

val find_cr_items : t -> digest:Sift_crs.Digest.t -> Sift_crs.Item.t list
(** [find_cr_items t ~digest] is the list of CR items whose digest is [digest].

    More than one item can have the same digest if the same CR source text
    appears more than once. *)

val marks : t -> Mark.t list
(** [marks t] is [t]'s explicit marks in deterministic scope order. *)

val mark : t -> Scope.t -> Mark.t option
(** [mark t scope] is the explicit mark for [scope], if any. *)

val effective_mark : t -> Scope.t -> Mark.t option
(** [effective_mark t scope] is the most specific mark that covers [scope], if
    any. *)

val approval : t -> Approval.t
(** [approval t] is [t]'s whole-feature approval state. *)

val cursor : t -> Cursor.t
(** [cursor t] is [t]'s current cursor. *)

val summary : t -> Summary.t
(** [summary t] is [t]'s derived progress summary. *)

val progress : t -> float
(** [progress t] is [Summary.progress (summary t)]. *)

(** {1:marks Reviewed marks} *)

val set_mark : t -> Mark.t -> (t, Error.t) result
(** [set_mark t mark] is [t] with [mark] as the explicit mark for
    [Mark.scope mark].

    Replaces any previous explicit mark for the same exact scope. Errors if the
    mark scope cannot be represented in [feature t]. *)

val mark_reviewed : t -> Scope.t -> (t, Error.t) result
(** [mark_reviewed t scope] is [set_mark t (Mark.reviewed scope)]. *)

val mark_unreviewed : t -> Scope.t -> (t, Error.t) result
(** [mark_unreviewed t scope] is [set_mark t (Mark.unreviewed scope)]. *)

val clear_mark : t -> Scope.t -> t
(** [clear_mark t scope] is [t] without an explicit mark for [scope].

    It is [t] if [scope] has no explicit mark. *)

val is_reviewed : t -> Scope.t -> bool
(** [is_reviewed t scope] is [true] iff [effective_mark t scope] is reviewed.

    Unmarked scopes are not reviewed. *)

(** {1:approval Approval} *)

val set_approval : t -> Approval.t -> t
(** [set_approval t approval] is [t] with whole-feature [approval]. *)

(** {1:cursor Cursor} *)

val set_cursor : t -> Cursor.t -> (t, Error.t) result
(** [set_cursor t cursor] is [t] with [cursor].

    Errors if [cursor] cannot select a scope or CR item in [t]. *)

val move_cursor : ?wrap:bool -> t -> Cursor.move -> t
(** [move_cursor ?wrap t move] is [t] with its cursor moved through the review
    navigation order.

    [wrap] defaults to [false]. Navigation order is the feature scope, file
    scopes in diff order, hunk scopes in file order, changed line scopes in hunk
    order, and CR items in their index order. [First] and [Last] ignore [wrap].
    [Previous] at the first target and [Next] at the last target leave the
    cursor unchanged unless [wrap] is [true]. *)

val next : ?wrap:bool -> t -> t
(** [next ?wrap t] is [move_cursor ?wrap t Next]. *)

val previous : ?wrap:bool -> t -> t
(** [previous ?wrap t] is [move_cursor ?wrap t Previous]. *)

(** {1:predicates Predicates and comparisons} *)

val is_complete : t -> bool
(** [is_complete t] is [Summary.is_complete (summary t)]. *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] have the same feature, CR item index,
    marks, approval, and cursor. *)

val compare : t -> t -> int
(** [compare a b] orders reviews. The order is compatible with {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] for humans. *)
