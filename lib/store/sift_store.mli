(** Durable local review state.

    [Sift_store] is the pure persistence model for state produced while
    reviewing a feature. It stores feature identity, local review decisions, CR
    state, and a resume cursor. It does not store source files or diff contents.

    The narrow waist is {!type-t}, a schema-versioned snapshot for one {!Key.t}.
    Encoding is described separately by {!Codec}; filesystem effects are
    supplied through {!Fs}. Runtime review values are mapped to storage-facing
    {!Record} values at the boundary. *)

(** {1:model Model} *)

module Version = Version
(** Store schema versions. *)

module Key = Key
(** Store keys for feature-local state. *)

module Record = Record
(** Durable review records. *)

module Codec = Codec
(** Backend-neutral store codecs. *)

module Error = Error
(** Structured store errors. *)

module Fs = Fs
(** Filesystem bridge surface. *)

type t
(** The type for durable review snapshots.

    A snapshot is pure data for one feature-local store key. It contains a
    schema version, feature display metadata, whole-feature approval, explicit
    review marks, CR records, and an optional cursor.

    Invariant: marks contain no duplicate scope identities. CR records contain
    no duplicate [(digest, scope)] identities. *)

(** {1:constructors Constructors} *)

val empty : ?version:Version.t -> ?title:string -> Key.t -> t
(** [empty ?version ?title key] is an empty pending snapshot for [key].

    [version] defaults to {!Version.current}. [title] is display metadata and is
    not part of [key]. Raises [Invalid_argument] if [title] is present but
    empty. *)

val of_feature :
  ?version:Version.t -> ?namespace:Key.namespace -> Sift_feature.t -> t
(** [of_feature ?version ?namespace feature] is an empty snapshot for [feature].

    Only the feature's base revision, tip revision, and title are persisted; the
    feature diff is not stored. Raises [Invalid_argument] if [namespace] is
    present but empty. *)

val of_review : ?namespace:Key.namespace -> Sift_review.t -> t
(** [of_review ?namespace review] is a durable snapshot for [review].

    The snapshot stores the feature key, title, explicit marks, whole-feature
    approval, cursor, and enough internal evidence to restore reviewed units
    conservatively after content changes. *)

(** {1:accessors Accessors} *)

val version : t -> Version.t
(** [version t] is [t]'s schema version. *)

val key : t -> Key.t
(** [key t] is [t]'s feature-local key. *)

val title : t -> string option
(** [title t] is [t]'s persisted feature title, if any. *)

val approval : t -> Record.approval
(** [approval t] is [t]'s whole-feature approval. *)

val marks : t -> Record.mark list
(** [marks t] is [t]'s explicit review marks in store order. *)

val cr_records : t -> Record.cr_record list
(** [cr_records t] is [t]'s stored CR records in store order. *)

val cursor : t -> Record.cursor option
(** [cursor t] is [t]'s saved cursor, if any. *)

(** {1:editing Editing} *)

val with_version : t -> Version.t -> t
(** [with_version t version] is [t] with schema [version]. *)

val with_title : t -> string option -> t
(** [with_title t title] is [t] with feature display title [title].

    Raises [Invalid_argument] if [title] is [Some ""] . *)

val with_approval : t -> Record.approval -> t
(** [with_approval t approval] is [t] with whole-feature [approval]. *)

val with_marks : t -> Record.mark list -> t
(** [with_marks t marks] is [t] with explicit review [marks].

    Raises [Invalid_argument] if [marks] contains duplicate scope identities. *)

val put_mark : t -> Record.mark -> t
(** [put_mark t mark] is [t] with [mark] inserted or replaced by scope.

    If a mark already exists for the same scope, it is replaced. *)

val remove_mark : t -> Record.scope -> t
(** [remove_mark t scope] is [t] without an explicit mark for [scope]. *)

val with_cr_records : t -> Record.cr_record list -> t
(** [with_cr_records t crs] is [t] with CR records [crs].

    Raises [Invalid_argument] if [crs] contains duplicate [(digest, scope)]
    identities. *)

val put_cr_record : t -> Record.cr_record -> t
(** [put_cr_record t cr] is [t] with [cr] inserted or replaced by its
    [(digest, scope)] identity. *)

val remove_cr_record :
  t -> digest:Sift_crs.Digest.t -> scope:Record.scope option -> t
(** [remove_cr_record t ~digest ~scope] is [t] without the CR record identified
    by [digest] and [scope]. *)

val with_cursor : t -> Record.cursor option -> t
(** [with_cursor t cursor] is [t] with saved [cursor]. *)

val apply_to_review : t -> Sift_review.t -> Sift_review.t
(** [apply_to_review t review] applies stored local state from [t] to [review].

    If [t] matches [review]'s feature content, explicit marks and approval are
    restored. Otherwise only reviewed units that still have matching content
    evidence are restored and approval remains pending. Stored cursors that no
    longer select valid review targets are ignored. *)

(** {1:codec Codec} *)

val codec : t Codec.t
(** [codec] is the canonical backend-neutral codec for snapshots. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] have the same stored state. *)

val compare : t -> t -> int
(** [compare a b] orders snapshots by key and stored state. The order is
    compatible with {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t]. *)
