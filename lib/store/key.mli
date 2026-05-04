(** Store keys for feature-local state. *)

type namespace = string
(** The type for optional key namespaces.

    Namespaces distinguish stores for different repositories, worktrees, or VCS
    remotes. A namespace supplied to a constructor must be non-empty. *)

type t
(** The type for store keys.

    A key identifies the local state for a feature by namespace, base revision,
    and tip revision. It does not include diff contents and should not include
    mutable display metadata such as a feature title. *)

(** {1:constructors Constructors} *)

val v :
  ?namespace:namespace ->
  base:Sift_feature.Revision.t ->
  tip:Sift_feature.Revision.t ->
  unit ->
  t
(** [v ?namespace ~base ~tip ()] is a store key for [base] and [tip].

    Raises [Invalid_argument] if [namespace] is present but empty. *)

val of_feature : ?namespace:namespace -> Sift_feature.t -> t
(** [of_feature ?namespace feature] is a key for [feature].

    Only {!Sift_feature.base} and {!Sift_feature.tip} are used; the feature
    title and diff are not part of the key. Raises [Invalid_argument] if
    [namespace] is present but empty. *)

(** {1:accessors Accessors} *)

val namespace : t -> namespace option
(** [namespace t] is [t]'s namespace, if any. *)

val base : t -> Sift_feature.Revision.t
(** [base t] is [t]'s base revision. *)

val tip : t -> Sift_feature.Revision.t
(** [tip t] is [t]'s tip revision. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] identify the same stored feature. *)

val compare : t -> t -> int
(** [compare a b] orders keys by namespace, base, and tip. The order is
    compatible with {!val-equal}. *)

(** {1:converting Converting} *)

val to_string : t -> string
(** [to_string t] is a stable textual key.

    The result is intended for encoded data and logs. It is not guaranteed to be
    a valid filename; use {!Fs.file} for filesystem paths. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t]. *)
