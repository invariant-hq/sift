(** Command palette overlay. *)

type group =
  | Review
  | Navigation
  | View
  | Session  (** The type for command palette groups. *)

type 'a item
(** The type for one rendered command carrying a payload of type ['a]. *)

val item : group -> key:string -> label:string -> 'a -> 'a item
(** [item group ~key ~label value] is a command palette item carrying
    [value]. *)

type 'a event = Activated of 'a | Closed
(** The type for events emitted by the command palette. *)

type msg
(** The type for command palette messages. *)

type 'a t
(** The type for command palette models. *)

val make : 'a item list -> 'a t
(** [make items] is a fresh command palette model displaying [items]. *)

val message_of_key : Mosaic.Event.key -> msg option
(** [message_of_key key] maps palette key input to a palette message. *)

val update : msg -> 'a t -> 'a t * msg Mosaic.Cmd.t * 'a event option
(** [update msg t] updates [t] for [msg]. *)

val view :
  'a t ->
  theme:Theme.t ->
  width:int ->
  height:int ->
  msg Mosaic.t
(** [view t ~theme ~width ~height] renders the command palette overlay. *)
