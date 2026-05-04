(** Comment composer component. *)

type comment = { scope : Sift_review.Scope.t; body : string }
(** The type for a review comment draft or submission. *)

type cr = { index : int; item : Sift_crs.Item.t }
(** The type for a CR item selected for editing. *)

type submission =
  | Submitted_comment of comment
  | Edited_cr of cr * string  (** The type for a valid composer submission. *)

type event =
  | Submitted of submission
  | Empty_submit
  | Cancelled  (** The type for events emitted by the composer. *)

type msg
(** The type for composer messages. *)

type t
(** The type for an open composer. *)

val add : Sift_review.Scope.t -> t
(** [add scope] is a composer for a new comment on [scope]. *)

val edit : cr -> body:string -> t
(** [edit cr ~body] is a composer for editing [cr] with initial [body]. *)

val draft : t -> comment
(** [draft t] is the current draft. *)

val message_of_key : Mosaic.Event.key -> msg option
(** [message_of_key key] maps composer key input to a composer message. *)

val update : msg -> t -> t * msg Mosaic.Cmd.t * event option
(** [update msg t] updates [t] for [msg]. *)

val view :
  theme:Theme.t ->
  width:int ->
  height:int ->
  t ->
  msg Mosaic.t
(** [view] renders [t] as a modal composer. *)
