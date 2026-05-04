(** Live worktree refresh protocol.

    [Live_worktree] is the pure runner state machine for standalone mutable
    worktree review. It owns debounce state, request identity, stale-result
    rejection, mode transitions, and conservative review refresh. It does not
    run Git, mutate files, persist reviews, or render the TUI; callers interpret
    its actions. *)

type mode =
  | Off
  | Worktree
      (** The type for live-refresh modes. [Off] is used for read-only explicit
          feature review. [Worktree] keeps [base -> WORKTREE] review live. *)

type request
(** The type for an in-flight runner request. *)

type load = { input : Sift_git.input; fingerprint : Sift_git.Fingerprint.t }
(** The type for stable worktree input loaded by the host interpreter. *)

type t
(** The type for live worktree refresh state. *)

type event =
  | Tick of float
  | Fingerprint_loaded of
      float * request * (Sift_git.Fingerprint.t, string) result
  | Worktree_loaded of request * (load, string) result
  | Review_changed of Sift_review.t
      (** The type for events accepted by the state machine. *)

type action =
  | Load_fingerprint of request
  | Load_worktree of request * Sift_git.Fingerprint.t
  | Replace_review of Sift_review.t
  | Report_error of string
      (** The type for actions requested from the caller. *)

val make :
  ?debounce:float ->
  mode ->
  review:Sift_review.t ->
  fingerprint:Sift_git.Fingerprint.t option ->
  unit ->
  t
(** [make mode ~review ~fingerprint ()] is live-refresh state for [review].

    [fingerprint] is the loaded baseline for [review] when [mode] is [Worktree].
    [debounce] defaults to [0.75] seconds. Raises [Invalid_argument] if
    [debounce] is negative. *)

val mode : t -> mode
(** [mode t] is [t]'s live-refresh mode. *)

val review : t -> Sift_review.t
(** [review t] is the latest review state known to the runner. *)

val step : event -> t -> t * action list
(** [step event t] advances [t] and returns actions for the caller to interpret.
    Results for stale requests are ignored. *)

val source_mutation_started :
  ?fingerprint:Sift_git.Fingerprint.t -> t -> (t * request, string) result
(** [source_mutation_started ?fingerprint t] invalidates pending watch requests
    before a source-mutating CR action starts and returns the request token that
    must be supplied to {!val-source_mutation_loaded}.

    In [Worktree] mode, [fingerprint] must be the current worktree fingerprint
    and must match the latest loaded review input. This prevents source edits
    based on stale review anchors. In [Off] mode no fingerprint is required. *)

val source_mutation_aborted : t -> request -> t * bool
(** [source_mutation_aborted t request] clears [request] when a source-mutating
    CR action failed before its reload phase. The boolean is [true] iff
    [request] was the active request; stale aborts leave [t] unchanged and
    return [false]. *)

val source_mutation_loaded :
  t ->
  request ->
  (load, string) result ->
  t * (Sift_review.t option, string) result
(** [source_mutation_loaded t request result] applies the result of a
    source-mutating CR reload. Successful reloads transition to [Worktree] mode
    and return the refreshed review so the caller can select the affected CR.
    Stale request results return [Ok None]. Errors for the active request leave
    the current review visible but enter [Worktree] mode with no loaded
    fingerprint, so the next watch tick can recover from the source change. Use
    {!val-source_mutation_aborted} for failures that happen before source is
    written. *)
