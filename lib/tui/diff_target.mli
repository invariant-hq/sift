(** Derived diff-pane target for the Sift TUI.

    [Diff_target] maps a resolved {!Review_context.t} to the file and patch the
    diff pane should display. It is pure derived data: it owns no state,
    performs no effects, and does not render Mosaic views. *)

type source_context = {
  file : Sift_diff.File.t;
  text : string;
  first_line : int;
  anchor_line : int;
}
(** The type for a source excerpt rendered by the review code viewer.

    [text] is the excerpt content. [first_line] is the one-based source line
    number of the first rendered line. [anchor_line] is the selected one-based
    source line number. *)

type content =
  | No_file
  | Binary of Sift_diff.File.t
  | Empty of Sift_diff.File.t
  | Source_unavailable of Sift_diff.File.t * Review_context.line
  | Source_context of source_context
  | Patch of Sift_diff.File.t * Mosaic.Diff.Patch.t
      (** The type for diff-pane content.

          [No_file] means the current review context has no file. [Binary file]
          means [file] has no text hunks. [Empty file] means [file] is textual
          but has no rendered patch rows. [Source_unavailable (file, line)]
          means [line] should be revealed from source but no source text is
          available. [Source_context context] means the viewer should render
          source text around [context.anchor_line]. [Patch (file, patch)] means
          [patch] is the rendered text diff for [file]. *)

type t
(** The type for a resolved diff-pane target. *)

(** {1:constructors Constructors} *)

val v : ?source:(path:string -> string option) -> Review_context.t -> t
(** [v ?source context] is the diff-pane target derived from [context].

    [source] resolves repository-relative file paths to source text. It is used
    only when the selected target is not present in the compact diff and the
    viewer must adaptively render source context. *)

(** {1:accessors Accessors} *)

val context : t -> Review_context.t
(** [context t] is the review context used to derive [t]. *)

val file : t -> Sift_diff.File.t option
(** [file t] is the file displayed by [t], if any. *)

val scope : t -> Sift_review.Scope.t option
(** [scope t] is the review scope associated with [t], if any. *)

val line : t -> Review_context.line option
(** [line t] is the source line associated with [t], if any. *)

val content : t -> content
(** [content t] is the content displayed by [t]. *)

val patch : t -> Mosaic.Diff.Patch.t option
(** [patch t] is the text patch displayed by [t], if any. *)
