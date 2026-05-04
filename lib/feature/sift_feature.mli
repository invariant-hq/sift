(** Pure review features.

    [Sift_feature] ties together a base revision, a tip revision, and a
    self-contained {!module-Sift_diff} value. It is pure data; VCS access,
    persistence, CR indexing, and review state live in higher layers. *)

(** {1:model Model} *)

module Revision = Revision
(** Revision identifiers. *)

module Summary = Summary
(** Feature summaries. *)

type t
(** The type for review features.

    A feature is the pure review unit: a base revision, a tip revision, and the
    diff from base to tip. It does not own VCS handles, files, network
    resources, CR indexes, or review state. *)

(** {1:features Features} *)

val v :
  ?title:string ->
  base:Revision.t ->
  tip:Revision.t ->
  diff:Sift_diff.t ->
  unit ->
  t
(** [v ~base ~tip ~diff ()] is a feature.

    Raises [Invalid_argument] if [title] is present but empty. *)

val title : t -> string option
(** [title t] is [t]'s title, if any. *)

val base : t -> Revision.t
(** [base t] is [t]'s base revision. *)

val tip : t -> Revision.t
(** [tip t] is [t]'s tip revision. *)

val diff : t -> Sift_diff.t
(** [diff t] is the diff from [base t] to [tip t]. *)

val summary : t -> Summary.t
(** [summary t] is [t]'s derived summary. *)

val files : t -> Sift_diff.File.t list
(** [files t] is [Sift_diff.files (diff t)]. *)

val find_file : t -> path:string -> Sift_diff.File.t option
(** [find_file t ~path] is the file diff whose display path is [path], if any.
*)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] have the same title, revisions, and
    diff. *)

val compare : t -> t -> int
(** [compare a b] orders features. The order is compatible with {!val-equal}. *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] for humans. *)
