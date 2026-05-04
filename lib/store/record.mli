(** Durable review records.

    This module defines storage-facing mirror types for review state. It does
    not depend on [sift.review]: review code maps its runtime values into these
    durable records at the storage boundary. *)

type path = string
(** The type for repository-relative display paths.

    Paths supplied to constructors must be non-empty and must not be absolute.
    Path normalization belongs to the VCS or diff producer. *)

type line = int
(** The type for one-based source line numbers. *)

type side =
  | Old
  | New
      (** The type for the side of a changed line.

          [Old] identifies a line in the feature base. [New] identifies a line
          in the feature tip. *)

type hunk = private {
  path : path;
  old_start : line;
  old_count : int;
  new_start : line;
  new_count : int;
}
(** The type for durable hunk positions.

    [path] is the file display path. Counts are non-negative. A start line is
    [0] only when the corresponding count is [0], matching unified diff empty
    ranges. Otherwise start lines are one-based. *)

type approval =
  | Pending
  | Approved
  | Seconded
      (** The type for whole-feature approval stored locally.

          This mirrors the review model without depending on [sift.review]. *)

type mark_state =
  | Reviewed
  | Unreviewed
      (** The type for stored review mark states.

          [Reviewed] marks a scope as reviewed. [Unreviewed] records an explicit
          unreviewed override, for example when a narrower scope should not
          inherit a broader reviewed mark. *)

type scope_view =
  | Feature
  | File of path
  | Hunk of hunk
  | Line of side * path * line
      (** The type for stored scope views.

          [Feature] selects the whole feature. [File path] selects one file.
          [Hunk h] selects one diff hunk. [Line (side, path, line)] selects one
          old or new source line. *)

type scope
(** The type for durable review scopes.

    A scope is the feature as a whole, a file, a hunk, or one side-specific
    source line. It is the persistence shape for review marks and CR
    disambiguation, not a runtime [Sift_review.Scope.t] value.

    Invariant: file paths are non-empty and relative; line numbers are
    one-based; hunk counts are non-negative; empty hunk ranges have start line
    [0]. *)

type mark
(** The type for stored review marks.

    A mark stores one exact durable scope and its explicit state. It is the
    persistence shape for {!Sift_review.Mark.t}, not a computed effective review
    state.

    Invariant: marks are identified by their scope; a store snapshot must not
    contain two marks for the same exact scope. *)

type cr_state =
  | Open
  | Addressed
  | Accepted
      (** The type for local CR state.

          [Open] means the CR still needs attention. [Addressed] means the
          author marked it as handled. [Accepted] means the reviewer accepted
          the resolution. *)

type cr_record
(** The type for stored CR state.

    A CR record stores a stable CR digest, optional durable scope, and local
    state. It does not store CR source text. *)

type cr_index = int
(** The type for zero-based CR item indexes in a review.

    Values supplied to cursor constructors must be non-negative. *)

type cursor_target =
  | Scope of scope
  | Cr of cr_index
      (** The type for saved cursor targets.

          [Scope scope] resumes at a durable review scope. [Cr i] resumes at the
          [i]th CR item in the review's CR index. *)

type cursor
(** The type for a saved review cursor.

    A cursor is a persistence hint for resuming a review. It should be ignored
    if the target no longer exists in the current feature. *)

(** {1:constructors Constructors} *)

val feature : scope
(** [feature] is the whole-feature review scope. *)

val file : path:path -> scope
(** [file ~path] is the file review scope for [path].

    Raises [Invalid_argument] if [path] is empty or absolute. *)

val hunk :
  path:path ->
  old_start:line ->
  old_count:int ->
  new_start:line ->
  new_count:int ->
  scope
(** [hunk ~path ~old_start ~old_count ~new_start ~new_count] is a hunk review
    scope.

    Raises [Invalid_argument] if [path] is empty or absolute, if a count is
    negative, if a start line is negative, or if a start line is [0] while the
    corresponding count is positive. *)

val old_line : path:path -> line:line -> scope
(** [old_line ~path ~line] is an old-side line review scope.

    Raises [Invalid_argument] if [path] is empty or absolute, or if [line < 1].
*)

val new_line : path:path -> line:line -> scope
(** [new_line ~path ~line] is a new-side line review scope.

    Raises [Invalid_argument] if [path] is empty or absolute, or if [line < 1].
*)

val cr_record :
  ?scope:scope ->
  digest:Sift_crs.Digest.t ->
  state:cr_state ->
  unit ->
  cr_record
(** [cr_record ?scope ~digest ~state ()] is a CR record for [digest].

    [scope] disambiguates repeated comments with the same digest when the caller
    has a stable source location. *)

val cursor : cursor_target -> cursor
(** [cursor target] is a saved cursor for [target].

    Raises [Invalid_argument] if [target] is [Cr i] and [i < 0]. *)

val mark : scope:scope -> state:mark_state -> mark
(** [mark ~scope ~state] is a stored explicit mark for [scope]. *)

(** {1:accessors Accessors} *)

val scope_view : scope -> scope_view
(** [scope_view scope] is [scope]'s view. *)

val scope_path : scope -> path option
(** [scope_path scope] is [scope]'s path, if [scope] is file-local. *)

val mark_scope : mark -> scope
(** [mark_scope mark] is the exact scope marked by [mark]. *)

val mark_state : mark -> mark_state
(** [mark_state mark] is [mark]'s explicit state. *)

val cr_digest : cr_record -> Sift_crs.Digest.t
(** [cr_digest cr] is [cr]'s stable CR digest. *)

val cr_scope : cr_record -> scope option
(** [cr_scope cr] is [cr]'s disambiguating scope, if any. *)

val cr_state : cr_record -> cr_state
(** [cr_state cr] is [cr]'s local state. *)

val cursor_target : cursor -> cursor_target
(** [cursor_target cursor] is [cursor]'s saved target. *)

val cursor_scope : cursor -> scope option
(** [cursor_scope cursor] is the selected scope, if [cursor] selects a scope. *)

val cursor_cr : cursor -> cr_index option
(** [cursor_cr cursor] is the selected CR item index, if [cursor] selects a CR
    item. *)

(** {1:predicates Predicates and comparisons} *)

val equal_side : side -> side -> bool
(** [equal_side a b] is [true] iff [a] and [b] are the same side. *)

val compare_side : side -> side -> int
(** [compare_side a b] orders sides. The order is compatible with
    {!val-equal_side}. *)

val equal_approval : approval -> approval -> bool
(** [equal_approval a b] is [true] iff [a] and [b] are the same approval. *)

val compare_approval : approval -> approval -> int
(** [compare_approval a b] orders approvals. The order is compatible with
    {!val-equal_approval}. *)

val equal_mark_state : mark_state -> mark_state -> bool
(** [equal_mark_state a b] is [true] iff [a] and [b] are the same mark state. *)

val compare_mark_state : mark_state -> mark_state -> int
(** [compare_mark_state a b] orders mark states. The order is compatible with
    {!val-equal_mark_state}. *)

val equal_scope : scope -> scope -> bool
(** [equal_scope a b] is [true] iff [a] and [b] describe the same scope. *)

val compare_scope : scope -> scope -> int
(** [compare_scope a b] orders scopes. The order is compatible with
    {!val-equal_scope}. *)

val equal_mark : mark -> mark -> bool
(** [equal_mark a b] is [true] iff [a] and [b] mark the same scope with the same
    state. *)

val compare_mark : mark -> mark -> int
(** [compare_mark a b] orders marks by scope and state. The order is compatible
    with {!val-equal_mark}. *)

val compare_mark_identity : mark -> mark -> int
(** [compare_mark_identity a b] orders marks by scope only. *)

val equal_cr_state : cr_state -> cr_state -> bool
(** [equal_cr_state a b] is [true] iff [a] and [b] are the same CR state. *)

val compare_cr_state : cr_state -> cr_state -> int
(** [compare_cr_state a b] orders CR states. The order is compatible with
    {!val-equal_cr_state}. *)

val equal_cr_record : cr_record -> cr_record -> bool
(** [equal_cr_record a b] is [true] iff [a] and [b] have the same digest, scope,
    and state. *)

val compare_cr_record : cr_record -> cr_record -> int
(** [compare_cr_record a b] orders CR records by digest, scope, and state. The
    order is compatible with {!val-equal_cr_record}. *)

val equal_cursor_target : cursor_target -> cursor_target -> bool
(** [equal_cursor_target a b] is [true] iff [a] and [b] select the same saved
    target. *)

val compare_cursor_target : cursor_target -> cursor_target -> int
(** [compare_cursor_target a b] orders cursor targets. The order is compatible
    with {!val-equal_cursor_target}. *)

val equal_cursor : cursor -> cursor -> bool
(** [equal_cursor a b] is [true] iff [a] and [b] point at the same target. *)

val compare_cursor : cursor -> cursor -> int
(** [compare_cursor a b] orders cursors. The order is compatible with
    {!val-equal_cursor}. *)

(** {1:fmt Formatting} *)

val pp_scope : Format.formatter -> scope -> unit
(** [pp_scope ppf scope] formats [scope] for humans. *)

val pp_mark : Format.formatter -> mark -> unit
(** [pp_mark ppf mark] formats [mark] for humans. *)

val pp_cr_record : Format.formatter -> cr_record -> unit
(** [pp_cr_record ppf cr] formats [cr] for humans. *)

val pp_cursor : Format.formatter -> cursor -> unit
(** [pp_cursor ppf cursor] formats [cursor] for humans. *)
