(** Pure CR parsers. *)

(** {1:headers Headers and comments} *)

val header : string -> (Header.t, Error.t) result
(** [header s] parses [s] as a CR header without the trailing [:] and body. *)

val comment : string -> (Comment.t, Error.t) result
(** [comment s] parses [s] as CR text without surrounding source comment
    delimiters.

    The input should start with [CR] or [XCR]. *)

(** {1:source Source text} *)

val source : path:string -> string -> Item.t list
(** [source ~path s] is every CR item found in source text [s].

    The parser recognizes OCaml, C-style block comments, XML comments, and
    common line comments used by shell, Lisp, C, and SQL-like languages. Source
    text that looks like a CR but has a malformed header is returned as an
    invalid item rather than being silently dropped. *)
