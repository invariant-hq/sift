(** Self-contained text and file diffs.

    [Sift_diff] models multi-file diffs independently of any renderer or VCS
    implementation. Producers can parse or compute values, review code can
    inspect files and hunks, and UI code can render the same values without
    depending on Mosaic internals. *)

(** {1:model Model} *)

module Line = Line
(** Lines in a text diff. *)

module Hunk = Hunk
(** Contiguous hunks in a text diff. *)

module File = File
(** File-level diffs. *)

type t
(** The type for multi-file diffs. A diff is an ordered list of file-level
    diffs. In Sift this is the content of a feature: the changes from a base
    revision to a tip revision. *)

module Error = Error
(** Structured diff errors. *)

(** {1:diffs Diffs} *)

val empty : t
(** [empty] is the empty diff. *)

val make : File.t list -> t
(** [make files] is a diff containing [files] in order. *)

val files : t -> File.t list
(** [files t] is [t]'s file diffs in order. *)

val file_count : t -> int
(** [file_count t] is [List.length (files t)]. *)

val is_empty : t -> bool
(** [is_empty t] is [true] iff [files t] is [[]]. *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] have the same files. *)

val compare : t -> t -> int
(** [compare a b] orders diffs by their files. The order is compatible with
    {!val-equal}. *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] as a unified multi-file diff. *)

(** {1:operations Operations} *)

module Parser : sig
  (** Diff parsers. *)

  val unified : string -> (t, Error.t) result
  (** [unified s] parses [s] as a unified multi-file diff.

      Git-style file headers are recognized when present, including additions,
      deletions, renames, copies, mode changes, and binary file markers. Mode
      changes are parsed only insofar as they help determine the file entry;
      mode values are not represented.

      Paths are normalized to repository-relative form: leading [a/] and [b/]
      path prefixes are stripped, and [/dev/null] is represented by an absent
      old or new path. Plain unified diffs with [---] and [+++] file headers are
      also accepted.

      Unified diff ["\\ No newline at end of file"] markers are accepted and
      ignored. *)

  val file_unified : string -> (File.t, Error.t) result
  (** [file_unified s] parses [s] as a unified diff for a single file.

      Path normalization and no-newline marker handling are the same as
      {!val-unified}. *)
end

module Compute = Compute
(** Diff computation. *)
