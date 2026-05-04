(** Source comment syntax. *)

type t =
  | Ocaml_block
  | C_block
  | C_line
  | Shell_line
  | Lisp_line
  | Sql_line
  | Xml_block
      (** The type for source comment syntaxes that can contain CR comments. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] are the same syntax. *)

val compare : t -> t -> int
(** [compare a b] orders syntaxes. The order is compatible with {!val-equal}. *)

(** {1:converting Converting} *)

val to_string : t -> string
(** [to_string t] is a lowercase name for [t]. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] as a lowercase name. *)
