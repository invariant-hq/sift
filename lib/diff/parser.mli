(** Diff parsers. *)

(** {1:unified Unified diffs} *)

val unified : string -> (Diff.t, Error.t) result
(** [unified s] parses [s] as a unified multi-file diff.

    Git-style file headers are recognized when present, including additions,
    deletions, renames, copies, mode changes, and binary file markers. Mode
    changes are parsed only insofar as they help determine the file entry; mode
    values are not represented.

    Paths are normalized to repository-relative form: leading [a/] and [b/] path
    prefixes are stripped, and [/dev/null] is represented by an absent old or
    new path. Plain unified diffs with [---] and [+++] file headers are also
    accepted.

    Unified diff ["\\ No newline at end of file"] markers are accepted and
    ignored. *)

val file_unified : string -> (File.t, Error.t) result
(** [file_unified s] parses [s] as a unified diff for a single file.

    Path normalization and no-newline marker handling are the same as
    {!val-unified}. *)
