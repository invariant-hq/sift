(** Structured Git bridge errors. *)

type command = { cwd : string; argv : string list }
(** The type for Git subprocess invocations.

    [cwd] is the process working directory. [argv] is the executable name and
    arguments in execution order. *)

type status =
  | Exited of int
  | Signaled of int
  | Stopped of int  (** The type for subprocess termination statuses. *)

type t =
  | Invalid_repository of string
  | No_worktree of string
  | Git_not_found of string
  | Git_failed of command * status * string
  | Io of string
  | Diff of Sift_diff.Error.t
      (** The type for Git bridge errors.

          [Invalid_repository path] means [path] is not inside a Git repository.
          [No_worktree path] means [path] is inside a Git repository without a
          checked-out work tree. [Git_not_found git] means the configured Git
          executable could not be executed.
          [Git_failed (command, status, stderr)] means Git ran and exited
          unsuccessfully. [Io message] reports a filesystem or process I/O
          failure not already represented by a Git exit status. [Diff e] wraps a
          recoverable diff parsing error from the pure Sift model. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] are the same Git bridge error. *)

val compare : t -> t -> int
(** [compare a b] orders errors. The order is compatible with {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] for humans. *)
