(** CR items in source text. *)

type t
(** The type for CR items.

    An item is one CR-looking source comment with its path, source comment
    syntax, source span, raw comment text, and parsed payload. *)

(** {1:constructors Constructors} *)

val make :
  path:string ->
  syntax:Syntax.t ->
  span:Span.t ->
  raw:string ->
  (Comment.t, Error.t) result ->
  t
(** [make ~path ~syntax ~span ~raw result] is a CR item.

    [raw] is the complete source comment text, including the language comment
    delimiters when they exist in the source. *)

(** {1:accessors Accessors} *)

val path : t -> string
(** [path t] is the path supplied when [t] was parsed. *)

val syntax : t -> Syntax.t
(** [syntax t] is [t]'s source comment syntax. *)

val span : t -> Span.t
(** [span t] is [t]'s source span. *)

val raw : t -> string
(** [raw t] is [t]'s raw source text. *)

val comment : t -> (Comment.t, Error.t) result
(** [comment t] is [t]'s parsed payload.

    [Ok c] is a syntactically valid CR comment. [Error e] is source text that
    looks enough like a CR to report, but whose header is malformed. *)

val digest : t -> Digest.t
(** [digest t] is [t]'s stable digest. *)

(** {1:predicates Predicates and comparisons} *)

val is_valid : t -> bool
(** [is_valid t] is [true] iff [comment t] is [Ok _]. *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] have the same path, span, raw text,
    and comment result. *)

val compare : t -> t -> int
(** [compare a b] orders items by path and source position. The order is
    compatible with {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] with its path and source position. *)
