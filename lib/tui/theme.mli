(** Visual design tokens for the Sift TUI. *)

type t = {
  diff : Mosaic.Diff.theme;
  background : Mosaic.Ansi.Color.t;
  panel : Mosaic.Ansi.Color.t;
  element : Mosaic.Ansi.Color.t;
  selection : Mosaic.Ansi.Color.t;
  focus : Mosaic.Ansi.Color.t;
  normal : Mosaic.Ansi.Style.t;
  muted : Mosaic.Ansi.Style.t;
  subtle : Mosaic.Ansi.Style.t;
  selected : Mosaic.Ansi.Style.t;
  reviewed : Mosaic.Ansi.Style.t;
  unreviewed : Mosaic.Ansi.Style.t;
  stale : Mosaic.Ansi.Style.t;
  cr : Mosaic.Ansi.Style.t;
  warning : Mosaic.Ansi.Style.t;
  error : Mosaic.Ansi.Style.t;
}
(** The type for review-screen design tokens. *)

val default : t
(** [default] is the built-in dark graphite theme. *)
