(** Derived review queue rows for the Sift TUI.

    [Review_queue] turns a {!Sift_review.t} into rows suitable for a review
    queue. It is pure derived data: it owns no state, performs no effects, and
    does not render Mosaic views. *)

type cr_nesting =
  | File_level
  | Hunk_level
      (** The queue nesting level for a CR row. CRs are distinct review items,
          but a code-anchored CR can still be rendered under the file or hunk
          that gives it local context. *)

type row =
  | Feature of {
      selected : bool;
      mark : Sift_review.Mark.state option;
      approval : Sift_review.Approval.t;
      remaining : int;
    }
  | File of {
      index : int;
      file : Sift_diff.File.t;
      path : string;
      selected : bool;
      mark : Sift_review.Mark.state option;
      cr_count : int;
      unreviewed_count : int;
    }
  | Hunk of {
      path : string;
      scope : Sift_review.Scope.t;
      hunk : Sift_review.Scope.hunk;
      selected : bool;
      mark : Sift_review.Mark.state option;
      cr_count : int;
      unreviewed_count : int;
    }
  | Cr of {
      index : int;
      item : Sift_crs.Item.t;
      selected : bool;
      valid : bool;
      nesting : cr_nesting;
    }  (** The type for one review queue row. *)

(** {1:rows Rows} *)

val rows :
  review:Sift_review.t -> cursor:Sift_review.Cursor.t -> unit -> row list
(** [rows ~review ~cursor ()] is the review queue for [review], with row
    selection derived from [cursor].

    Rows are ordered as the feature row and file rows. The current file expands
    to hunk rows, with CR rows nested after their containing hunk when possible
    and otherwise after the file's hunks. A line cursor selects the containing
    hunk row. *)

val cursor : row -> Sift_review.Cursor.t
(** [cursor row] is the review cursor selected by [row]. *)
