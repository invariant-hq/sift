(** Filesystem bridge surface. *)

type path = string
(** The type for host filesystem paths. *)

type bytes = string
(** The type for serialized store bytes.

    The string is an uninterpreted byte sequence. Text encoders should document
    their character encoding. *)

type 'a codec = { encode : 'a -> bytes; decode : bytes -> ('a, Error.t) result }
(** The type for byte codecs used by filesystem operations.

    Decoding errors are recoverable persistence errors and should use
    {!Error.Decode} or a more specific store error. *)

type io = {
  read : path -> (bytes, Error.t) result;
  write : path -> bytes -> (unit, Error.t) result;
  mkdir_p : path -> (unit, Error.t) result;
}
(** The type for filesystem effects supplied by a caller or bridge.

    [read path] reads [path]. [write path bytes] replaces [path] with [bytes].
    [mkdir_p path] creates [path] and its parents if absent. Implementations
    report effect failures with {!Error.Io}. *)

(** {1:paths Paths} *)

val file : dir:path -> Key.t -> path
(** [file ~dir key] is the store file path for [key] under [dir].

    The result must be deterministic and must not escape [dir]. *)

(** {1:operations Operations} *)

val load : io -> 'a codec -> path -> ('a, Error.t) result
(** [load io codec path] reads [path] with [io] and decodes it with [codec]. *)

val save : io -> 'a codec -> path -> 'a -> (unit, Error.t) result
(** [save io codec path v] encodes [v] with [codec] and writes it to [path] with
    [io]. *)
