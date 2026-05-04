(** Refresh notices for the Sift TUI.

    [Refresh_notice] derives UI-local checkpoint summaries from two review
    states. It is not durable review state; hosts provide refreshed
    {!Sift_review.t} values and the TUI derives the visible notice. *)

type t = {
  new_review_units : int;
  removed_review_units : int;
  new_crs : int;
  removed_crs : int;
  verdict_reset : bool;
  stale_verdict : bool;
}
(** The type for one refresh summary.

    Review-unit counts exclude CRs, which are counted separately. A stale
    verdict means the previous review had an approved or seconded verdict for
    content that changed. [verdict_reset] is [true] when that stale verdict is
    now pending in the refreshed review. *)

val derive : before:Sift_review.t -> after:Sift_review.t -> t
(** [derive ~before ~after] is the UI-local refresh summary for replacing
    [before] with [after]. *)

val first_new_cursor :
  before:Sift_review.t -> after:Sift_review.t -> Sift_review.Cursor.t option
(** [first_new_cursor ~before ~after] is the cursor for the first review unit in
    [after] whose refresh identity was not present in [before], if any. *)

val is_empty : t -> bool
(** [is_empty t] is [true] iff [t] has no review-unit delta, no CR delta, and no
    stale verdict. *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] as a concise footer notice. *)
