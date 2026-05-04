(** Source spans. *)

type t
(** The type for source spans.

    Spans are half-open byte ranges with 1-based line numbers and 0-based
    columns. [stop_offset] is the first byte after the span. *)

(** {1:constructors Constructors} *)

val make :
  start_offset:int ->
  stop_offset:int ->
  start_line:int ->
  start_col:int ->
  stop_line:int ->
  stop_col:int ->
  unit ->
  t option
(** [make ~start_offset ~stop_offset ~start_line ~start_col ~stop_line ~stop_col
     ()] is the corresponding span, if the arguments describe a valid source
    range.

    Returns [None] if offsets are negative, line numbers are less than [1],
    columns are negative, or the stop position is before the start position. *)

val v :
  start_offset:int ->
  stop_offset:int ->
  start_line:int ->
  start_col:int ->
  stop_line:int ->
  stop_col:int ->
  unit ->
  t
(** [v ...] is the span described by its arguments.

    Raises [Invalid_argument] if the arguments do not describe a valid span. *)

(** {1:accessors Accessors} *)

val start_offset : t -> int
(** [start_offset t] is the first byte offset in [t]. *)

val stop_offset : t -> int
(** [stop_offset t] is the first byte offset after [t]. *)

val start_line : t -> int
(** [start_line t] is the 1-based line number where [t] starts. *)

val start_col : t -> int
(** [start_col t] is the 0-based column where [t] starts. *)

val stop_line : t -> int
(** [stop_line t] is the 1-based line number where [t] stops. *)

val stop_col : t -> int
(** [stop_col t] is the 0-based column where [t] stops. *)

(** {1:predicates Predicates and comparisons} *)

val equal : t -> t -> bool
(** [equal a b] is [true] iff [a] and [b] describe the same span. *)

val compare : t -> t -> int
(** [compare a b] orders spans by source position. The order is compatible with
    {!val-equal}. *)

(** {1:fmt Formatting} *)

val pp : Format.formatter -> t -> unit
(** [pp ppf t] formats [t] as [line:column-line:column]. *)
