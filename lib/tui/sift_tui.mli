(** Mosaic TUI model for Sift reviews.

    [Sift_tui.t] is the TEA model for the first Sift review screen. It is
    constructed from a pure {!Sift_review.t}, keeps only UI-local state such as
    selected rows and modal state, and delegates durable review state changes
    back to {!Sift_review}. It performs no Git, filesystem, store, or terminal
    effects.

    The module has two layers:
    - the pure model/update API, which can be tested without a running terminal;
    - Mosaic rendering entry points in {!val-view}, {!val-subscriptions}, and
      {!val-app}. *)

(** {1:types Types} *)

type t
(** The type for TUI models.

    A value owns one current {!Sift_review.t}, view configuration, selected
    rows, modal state, and the last recoverable UI error. It is immutable:
    operations that change the UI return a fresh value. *)

type diff_layout = Unified | Split  (** The type for diff display layouts. *)

type mark_action =
  | Mark_reviewed
  | Mark_unreviewed
  | Toggle_mark
  | Clear_mark
      (** The type for review-mark edits on the current review target. *)

type command =
  | Quit
  | Move_cursor of Sift_review.Cursor.move
  | Move_outstanding of Sift_review.Cursor.move
  | Move_file of Sift_review.Cursor.move
  | Move_cr of Sift_review.Cursor.move
  | Jump_first_new_review_unit
  | Mark_current of mark_action
  | Add_comment
  | Edit_cr
  | Remove_cr
  | Resolve_cr
  | Set_approval of Sift_review.Approval.t
  | Set_diff_layout of diff_layout
  | Toggle_diff_layout
  | Show_command_palette
  | Close_modal
      (** The type for semantic UI commands.

          Commands are usually produced by {!Keymap.command}, but callers may
          dispatch them directly through {!Command}. Movement commands use
          {!Sift_review.Cursor.move}; [First] and [Last] jump to list bounds,
          while [Previous] and [Next] move by one visible item.
          [Jump_first_new_review_unit] selects the first new unit reported by
          the last refresh notice, if one is still available. *)

type comment = Composer.comment = { scope : Sift_review.Scope.t; body : string }
(** The type for a review comment draft or submission.

    [scope] is the review scope where the user requested the comment. Submitted
    comment bodies are trimmed and non-empty. *)

type cr = Composer.cr = { index : int; item : Sift_crs.Item.t }
(** The type for a CR item selected for a runner-owned action. *)

type msg =
  | Command of command
  | Select_queue of int
  | Activate_queue_row of int
  | Select_scope of Sift_review.Scope.t
  | Select_cursor of Sift_review.Cursor.t
  | Diff_pane_msg of Diff_pane.msg
  | Command_palette_msg of Command_palette.msg
  | Composer_msg of Composer.msg
  | Activate_queue
  | Activate_diff
  | Replace_review of Sift_review.t
  | Replace_review_and_select of Sift_review.t * Sift_review.Cursor.t
  | Report_error of string
  | Dismiss_error
  | Resize of int * int
  | Review_changed of Sift_review.t
  | Comment_submitted of comment
  | Cr_removed of cr
  | Cr_edited of cr * string
  | Cr_resolved of cr
      (** The type for TEA messages handled by {!update}.

          [Select_queue i] selects the [i]th visible queue row for a mouse
          click. [Activate_queue_row i] selects the row and moves focus to the
          diff surface. [Activate_queue] and [Activate_diff] move keyboard
          focus between the two main review surfaces. [Diff_pane_msg msg],
          [Command_palette_msg msg], and [Composer_msg msg] delegate local
          interaction updates and event production to child components. Hunk
          rows resolve to their first changed line so line review stays the
          primary mouse target. [Select_scope scope] and [Select_cursor cursor]
          delegate validation to
          {!Sift_review.set_cursor}. [Replace_review review] swaps in
          externally loaded state without performing any loading itself.
          [Replace_review_and_select (review, cursor)] also selects [cursor] in
          the replacement review. [Report_error msg] stores an externally
          produced error message for display. [Resize (width, height)] records
          the terminal size for responsive rendering.

          [Review_changed], [Comment_submitted], [Cr_removed], [Cr_edited],
          and [Cr_resolved] are semantic messages emitted by commands returned
          from {!update}. A parent application may handle them before delegating
          other messages back to {!update}. *)

(** {1:keymap Key maps} *)

module Keymap : sig
  type binding = {
    shortcut : Mosaic.Shortcut.t;
    command : command;
    label : string option;
  }
  (** The type for one keyboard binding.

      [label] is a short display string for help/status views. It does not
      affect matching. *)

  type t
  (** The type for key maps.

      Bindings are matched in list order. The first binding whose shortcut
      matches the key event wins. *)

  val make : binding list -> t
  (** [make bindings] is a key map with [bindings] matched in list order. *)

  val default : t
  (** [default] is the v1 key map for cursor movement, review marks, approval,
      seconding, diff layout, command discovery, and quit. *)

  val bindings : t -> binding list
  (** [bindings t] is [t]'s bindings in matching order. *)

  val command : t -> Mosaic.Event.key -> command option
  (** [command t key] is the command bound to [key], if any. Key-release events
      do not match. *)
end

(** {1:config Configuration} *)

module Config : sig
  type source_resolver = review:Sift_review.t -> path:string -> string option
  (** The type for source text resolvers.

      [review] is the currently displayed review and [path] is a
      repository-relative file path. Returning [None] means source context is
      unavailable for that path. *)

  type t
  (** The type for UI configuration.

      Configuration is intentionally narrow: it covers only the v1 choices that
      affect the first usable review workflow. *)

  val make :
    ?theme:Theme.t ->
    ?keymap:Keymap.t ->
    ?diff_layout:diff_layout ->
    ?diff_wrap:Mosaic.Text_surface.wrap ->
    ?show_line_numbers:bool ->
    ?wrap_navigation:bool ->
    ?workspace_label:string ->
    ?source:source_resolver ->
    unit ->
    t
  (** [make ()] is a configuration value.

      [theme] defaults to {!Theme.default}. [keymap] defaults to
      {!Keymap.default}. [diff_layout] defaults to [Unified]. [diff_wrap]
      defaults to [`None]. [show_line_numbers] defaults to [true].
      [wrap_navigation] defaults to [false]. [workspace_label] is optional
      footer context, usually the repository root or current directory. [source]
      defaults to a resolver that returns [None]. *)

  val default : t
  (** [default] is [make ()]. *)
end

(** {1:errors Errors} *)

module Error : sig
  type t =
    | Review of Sift_review.Error.t
    | No_current_scope
    | No_current_file
    | No_current_cr
    | Invalid_cr of Sift_crs.Error.t
    | Empty_comment
    | External of string
    | Invalid_queue_index of int
        (** The type for UI update errors.

            [Review e] wraps validation errors reported by {!Sift_review}.
            [No_current_scope], [No_current_file], and [No_current_cr] report
            commands that require a current target when none exists.
            [Invalid_cr e] reports a CR edit command on malformed CR source.
            [Empty_comment] reports a composer submit with no body. [External]
            reports a runner-owned effect failure. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf e] formats [e] for humans. *)
end

(** {1:refresh Refresh notices} *)

module Refresh_notice : sig
  type t = private {
    new_review_units : int;
    removed_review_units : int;
    new_crs : int;
    removed_crs : int;
    verdict_reset : bool;
    stale_verdict : bool;
  }
  (** The type for a UI-local refresh summary. *)

  val is_empty : t -> bool
  (** [is_empty t] is [true] iff [t] has no visible refresh delta. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf t] formats [t] as a concise footer notice. *)
end

(** {1:queue Queue rows} *)

module Queue : sig
  type cr_nesting =
    | File_level
    | Hunk_level  (** The queue nesting level for a CR row. *)

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

  val cursor : row -> Sift_review.Cursor.t
  (** [cursor row] is the review cursor selected by [row]. *)
end

(** {1:constructors Constructors} *)

val make : ?config:Config.t -> Sift_review.t -> t
(** [make review] is a TUI model for [review].

    [config] defaults to {!Config.default}. The initial selected file and CR row
    are derived from [Sift_review.cursor review] when possible and otherwise
    clamped to the first available row. *)

(** {1:accessors Accessors} *)

val review : t -> Sift_review.t
(** [review t] is the durable review state displayed by [t]. *)

val cursor : t -> Sift_review.Cursor.t
(** [cursor t] is [Sift_review.cursor (review t)]. *)

val approval : t -> Sift_review.Approval.t
(** [approval t] is [Sift_review.approval (review t)]. *)

val last_refresh_notice : t -> Refresh_notice.t option
(** [last_refresh_notice t] is the last UI-local review replacement summary, if
    any. *)

val last_error : t -> Error.t option
(** [last_error t] is the last recoverable UI error, if any. *)

val comment_composer : t -> comment option
(** [comment_composer t] is the open comment draft, if any. *)

val queue_rows : t -> Queue.row list
(** [queue_rows t] is the visible review queue. *)

val current_scope : t -> Sift_review.Scope.t option
(** [current_scope t] is the active review scope.

    Queue focus follows the durable review cursor. Diff focus follows the
    diff-pane line selection, falling back to the review cursor when the diff
    pane has no selected source line. *)

val current_patch : t -> Mosaic.Diff.Patch.t option
(** [current_patch t] is the Mosaic diff patch for the current review context,
    if it has represented text changes. It is [None] for absent selections,
    binary file diffs, and empty text diffs. *)

(** {1:updates Updates} *)

val message_of_key : t -> Mosaic.Event.key -> msg option
(** [message_of_key t key] maps [key] through the configured key map. *)

val update : msg -> t -> t * msg Mosaic.Cmd.t
(** [update msg t] is [t] updated for [msg] and the command requested by the
    update.

    Recoverable validation failures are stored in the returned model's error
    state so the next view can render them. Runtime work such as quitting,
    moving keyboard focus, and notifying a parent application is represented as
    a Mosaic command. *)

(** {1:views Mosaic views} *)

val view : t -> msg Mosaic.t
(** [view t] renders the complete review screen. *)

val subscriptions : t -> msg Mosaic.Sub.t
(** [subscriptions t] subscribes to keyboard events handled by {!message_of_key}
    and terminal resize events. *)

val app :
  ?config:Config.t -> Sift_review.t -> (t, msg) Mosaic.app
(** [app review] is a Mosaic application for [review].

    Loading reviews from Git or store, and persisting [Review_changed _],
    belongs outside this app. Parent applications can intercept semantic
    messages emitted by commands before delegating other messages back to
    {!update}. *)
