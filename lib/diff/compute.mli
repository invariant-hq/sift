(** Diff computation. *)

(** {1:text Text diffs} *)

val hunks :
  ?context:int -> old_text:string -> new_text:string -> unit -> Hunk.t list
(** [hunks ~old_text ~new_text ()] computes line-level hunks from [old_text] to
    [new_text].

    [context] controls unchanged lines around changes and defaults to [3].

    Raises [Invalid_argument] if [context] is negative. *)

val file :
  ?context:int ->
  ?old_path:string ->
  ?new_path:string ->
  old_text:string ->
  new_text:string ->
  unit ->
  File.t option
(** [file ~old_text ~new_text ()] computes a text file diff.

    [context] defaults to [3]. [old_path] and [new_path] default to [None]. The
    returned file status is derived from path presence and content changes:
    added when only [new_path] is present, deleted when only [old_path] is
    present, renamed when both paths are present and differ, and modified when
    both paths are present, equal, and the computed hunks are non-empty. Returns
    [None] when both paths are present, equal, and the texts are equal.

    Raises [Invalid_argument] if [context] is negative or the computed file
    arguments are invalid. *)
