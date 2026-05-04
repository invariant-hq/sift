(** Backend-neutral store codecs. *)

type value =
  | Null
  | Bool of bool
  | Int of int
  | String of string
  | List of value list
  | Fields of (string * value) list
      (** The type for encoded values.

          The shape is intentionally close to common structured formats without
          depending on a JSON, S-expression, or binary codec library. Field
          order is significant only for byte codecs that choose to preserve it.
          Decoders should reject duplicate field names when a record schema
          requires unique fields. *)

type 'a t
(** The type for bidirectional codecs between OCaml values and {!type-value}. *)

(** {1:constructors Constructors} *)

val make :
  encode:('a -> value) -> decode:(value -> ('a, Error.t) result) -> 'a t
(** [make ~encode ~decode] is a codec using [encode] and [decode]. *)

(** {1:converting Converting} *)

val encode : 'a t -> 'a -> value
(** [encode codec v] is [v] encoded with [codec]. *)

val decode : 'a t -> value -> ('a, Error.t) result
(** [decode codec value] decodes [value] with [codec].

    Errors if [value] does not satisfy [codec]'s schema. Decoding errors are
    recoverable persistence errors. *)
