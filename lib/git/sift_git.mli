(** Git bridge for review input.

    [Sift_git] loads real review input from a Git repository into the pure Sift
    models: {!Sift_feature.t}, {!Sift_diff.t}, and {!Sift_crs.Item.t}. It is a
    Git-specific effect boundary, not a generic VCS abstraction.

    The narrow waist is {!type-t}, a repository handle containing the Git
    executable and repository root. Keeping this handle explicit lets callers
    discover a repository once, inspect the chosen root, and run later
    subprocess and filesystem operations against the same configuration. Values
    of type {!type-t} do not own file descriptors or processes. *)

(** {1:model Model} *)

module Error = Error
(** Structured Git bridge errors. *)

type revision = Sift_feature.Revision.t
(** The type for resolved Git revisions used by Sift features. *)

type range = { base : revision; tip : revision }
(** The type for resolved review ranges.

    [base] and [tip] are concrete commit revisions. Diffs are computed as the
    changes needed to get from [base] to [tip]. *)

type input = { feature : Sift_feature.t; cr_items : Sift_crs.Item.t list }
(** The type for review inputs loaded from Git.

    [feature] is the feature under review. [cr_items] are CR items scanned from
    relevant source files in the tip tree and ordered by diff file order, then
    source order. The value is ready to pass to [Sift_review.v] without making
    this library depend on [sift.review]. *)

module Fingerprint : sig
  type t
  (** The type for a worktree content fingerprint.

      Fingerprints are process-local equality tokens. They are not stable file
      formats and should not be persisted or parsed. *)

  val v : string -> t
  (** [v s] is [s] as a fingerprint token.

      This is mainly useful for tests and alternate Git bridge implementations.
      Production callers should normally obtain fingerprints from
      {!val-worktree_fingerprint}. Raises [Invalid_argument] if [s] is empty. *)

  val equal : t -> t -> bool
  (** [equal a b] is [true] iff [a] and [b] identify the same tracked worktree
      diff content. *)

  val pp : Format.formatter -> t -> unit
  (** [pp ppf t] formats [t] for diagnostics. *)
end

type t
(** The type for Git repository handles.

    A handle records a Git executable and the absolute repository work-tree root
    used as the working directory for Git subprocesses. Constructing a handle
    does not run Git; operations below perform subprocess and filesystem effects
    and report recoverable failures as {!Error.t}. *)

(** {1:repositories Repositories} *)

val v : ?git:string -> root:string -> unit -> t
(** [v ?git ~root ()] is a repository handle rooted at [root].

    [git] defaults to ["git"]. [root] must be the absolute path to a Git
    work-tree root. The path is not checked until an effectful operation is run.

    Raises [Invalid_argument] if [git] or [root] is empty. *)

val discover : ?git:string -> ?cwd:string -> unit -> (t, Error.t) result
(** [discover ?git ?cwd ()] discovers the Git work-tree root containing [cwd].

    [git] defaults to ["git"]. [cwd] defaults to the current process working
    directory. The operation runs Git and may inspect the filesystem.

    Errors with {!Error.Invalid_repository} if [cwd] is not inside a Git
    repository, {!Error.No_worktree} if the repository has no checked-out work
    tree, {!Error.Git_not_found} if [git] cannot be executed,
    {!Error.Git_failed} if Git exits unsuccessfully, or {!Error.Io} for other
    process or filesystem failures. Raises [Invalid_argument] if [git] or [cwd]
    is empty. *)

val root : t -> string
(** [root t] is [t]'s repository work-tree root. *)

val git : t -> string
(** [git t] is [t]'s Git executable. *)

(** {1:revisions Revisions} *)

val resolve_revision : t -> string -> (revision, Error.t) result
(** [resolve_revision t spec] resolves Git revision expression [spec] to a
    commit revision.

    The operation runs Git in {!val-root} [t]. The returned revision is suitable
    for {!Sift_feature.v}. Errors with {!Error.Git_failed} if [spec] does not
    name a commit. Raises [Invalid_argument] if [spec] is empty. *)

val default_tip : t -> (revision, Error.t) result
(** [default_tip t] is [resolve_revision t "HEAD"]. *)

val default_base : ?tip:string -> t -> (revision, Error.t) result
(** [default_base ?tip t] is the default review base for [tip].

    [tip] defaults to ["HEAD"]. The base is the merge base of [tip] and the
    current branch upstream. If the current branch has no upstream, the base is
    the merge base of [tip] and [origin/HEAD].

    Errors if neither default comparison reference exists or if Git cannot
    compute a merge base. Raises [Invalid_argument] if [tip] is empty. *)

val resolve :
  ?base:string -> ?tip:string -> t -> unit -> (range, Error.t) result
(** [resolve ?base ?tip t ()] resolves a review range.

    [tip] defaults to ["HEAD"]. If [base] is supplied, it is resolved as a Git
    revision expression. If [base] is absent, {!val-default_base} is used with
    the selected [tip]. The resulting [base] and [tip] are concrete commit
    revisions.

    Raises [Invalid_argument] if [base] or [tip] is present but empty. *)

(** {1:loading Loading review input} *)

val diff : t -> range -> (Sift_diff.t, Error.t) result
(** [diff t range] is the unified Git diff from [range.base] to [range.tip]
    parsed as a {!Sift_diff.t}.

    The operation runs Git in {!val-root} [t] and parses its unified diff output
    with {!Sift_diff.Parser.unified}. Errors with {!Error.Diff} if the Git
    output cannot be represented by the pure diff model. *)

val cr_items :
  t ->
  tip:revision ->
  diff:Sift_diff.t ->
  (Sift_crs.Item.t list, Error.t) result
(** [cr_items t ~tip ~diff] scans relevant source files in [tip]'s tree for CR
    items.

    Relevant files are files represented by text entries in [diff] with a new
    path. Deleted files and binary diff entries are skipped. Each scanned blob
    is read from Git at [tip:path] and parsed with {!Sift_crs.Parser.source}
    using the repository-relative path from the diff. Items are returned in diff
    file order, then source order.

    The operation runs Git and reads blob contents through Git subprocesses.
    Errors if Git cannot read a relevant tip-tree blob or if process I/O fails.
    Malformed CR comments are returned as invalid {!Sift_crs.Item.t} values
    rather than failing the scan. *)

val source : t -> tip:revision -> path:string -> (string, Error.t) result
(** [source t ~tip ~path] is [path]'s source text from [tip]'s tree.

    [path] is repository-relative. The operation runs Git and errors if the blob
    cannot be read. Raises [Invalid_argument] if [path] is empty. *)

val worktree_source : t -> path:string -> (string, Error.t) result
(** [worktree_source t ~path] is [path]'s source text from the working tree.

    [path] is repository-relative. The operation reads the filesystem under
    {!val-root} [t]. Raises [Invalid_argument] if [path] is empty. *)

val load :
  ?title:string ->
  ?base:string ->
  ?tip:string ->
  t ->
  unit ->
  (input, Error.t) result
(** [load ?title ?base ?tip t ()] loads review input from [t].

    The operation resolves the range with {!val-resolve}, computes {!val-diff},
    scans {!val-cr_items}, and constructs a {!Sift_feature.t}. [title] is
    forwarded to {!Sift_feature.v} and defaults to [None].

    Errors are reported at the stage where they occur. The function performs Git
    subprocess and filesystem effects but does not create review state or write
    persistent data. Raises [Invalid_argument] if [title], [base], or [tip] is
    present but empty. *)

val load_worktree :
  ?title:string -> ?base:string -> t -> unit -> (input, Error.t) result
(** [load_worktree ?title ?base t ()] loads review input from uncommitted
    worktree changes.

    [base] defaults to ["HEAD"]. The diff is computed from [base] to the working
    tree, including staged and unstaged tracked changes. CR items are scanned
    from the working tree files represented by the diff. Untracked files are not
    included yet. [title] is forwarded to {!Sift_feature.v} and defaults to
    [None].

    Errors are reported at the stage where they occur. The feature tip revision
    is the synthetic revision ["WORKTREE"]. Raises [Invalid_argument] if [title]
    or [base] is present but empty. *)

type worktree_input = { input : input; fingerprint : Fingerprint.t }
(** The type for a worktree review input loaded together with the fingerprint of
    the tracked worktree content it represents. *)

val worktree_fingerprint : ?base:string -> t -> (Fingerprint.t, Error.t) result
(** [worktree_fingerprint ?base t] is a stable fingerprint of the tracked
    worktree changes that {!load_worktree} would review.

    [base] defaults to ["HEAD"]. The fingerprint is derived from Git's no-color,
    no-external-diff worktree diff from [base] to the working tree. It changes
    when tracked staged or unstaged reviewable content changes and intentionally
    ignores untracked files. The value is only meant for equality checks within
    one running process; callers should not persist or parse it.

    Errors are reported at the stage where they occur. Raises [Invalid_argument]
    if [base] is present but empty. *)

val load_worktree_stable :
  ?title:string -> ?base:string -> t -> unit -> (worktree_input, Error.t) result
(** [load_worktree_stable ?title ?base t ()] loads worktree review input and a
    fingerprint, retrying the fingerprint around the load.

    The operation fingerprints the tracked worktree diff, loads
    {!load_worktree}, then fingerprints again. If the fingerprints differ, the
    worktree changed while the input was loading and the function returns an
    error instead of mixing a diff and CR scan from different source states.

    Errors are reported at the stage where they occur. Raises [Invalid_argument]
    if [title] or [base] is present but empty. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] have the same Git executable and
    repository root. *)

val compare : t -> t -> int
(** [compare a b] orders repository handles. The order is compatible with
    {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] for humans. *)
