(** Valid CR comments. *)

type t
(** The type for valid CR comments.

    A comment is a parsed CR header together with free-form body text. It is not
    tied to a source location; use {!module-Item} for CR-like source items. *)

(** {1:constructors Constructors} *)

val make : header:Header.t -> body:string -> t
(** [make ~header ~body] is a CR comment with [header] and [body].

    [body] is kept verbatim. Parsers remove surrounding source comment
    delimiters and the CR header before constructing comments. *)

(** {1:accessors Accessors} *)

val header : t -> Header.t
(** [header t] is [t]'s header. *)

val body : t -> string
(** [body t] is [t]'s free-form body. *)

val status : t -> Status.t
(** [status t] is [Header.status (header t)]. *)

val priority : t -> Priority.t
(** [priority t] is [Header.priority (header t)]. *)

val reporter : t -> Handle.t
(** [reporter t] is [Header.reporter (header t)]. *)

val recipient : t -> Handle.t option
(** [recipient t] is [Header.recipient (header t)]. *)

val digest : t -> Digest.t
(** [digest t] is [t]'s stable digest. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] have the same header and body. *)

val compare : t -> t -> int
(** [compare a b] orders comments. The order is compatible with {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp_header : Format.formatter -> t -> unit
(** [pp_header ppf t] formats [t]'s header followed by [:]. *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] as CR body text without surrounding source comment
    delimiters. *)
