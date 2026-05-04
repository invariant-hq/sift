(** Inline code review comments.

    [Sift_crs] is a pure model for CR comments embedded in source text. It
    parses valid CR comments, preserves malformed CR-like source comments as
    items, and describes source rewrites without performing filesystem effects.
*)

(** {1:comments Comments} *)

module Handle = Handle
(** User handles in CR syntax. *)

module Status = Status
(** CR status. *)

module Priority = Priority
(** CR priority. *)

module Header = Header
(** CR headers. *)

module Comment = Comment
(** Valid CR comments. *)

module Digest = Digest
(** Stable CR digests. *)

(** {1:source Source items} *)

module Syntax = Syntax
(** Source comment syntax. *)

module Span = Span
(** Source spans. *)

module Item = Item
(** CR items in source text. *)

module Error = Error
(** Structured CRS errors. *)

(** {1:operations Operations} *)

module Parser = Parser
(** Pure CR parsers. *)

module Filter = Filter
(** Item filters. *)

module Edit = Edit
(** Pure source edits for CR comments. *)
