(** Review priority for the Sift TUI. *)

val priority : Review_queue.row -> int option
(** [priority row] is [Some n] if [row] is outstanding, where lower [n] means
    higher priority. It is [None] for purely reviewed context rows. *)

val first_outstanding : review:Sift_review.t -> Sift_review.Cursor.t option
(** [first_outstanding ~review] is the highest-priority cursor to select on
    review open, if any. *)

val outstanding_indices : Review_queue.row list -> int list
(** [outstanding_indices rows] is the list of visible outstanding row indices.
*)
