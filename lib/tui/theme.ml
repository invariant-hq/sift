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

let default =
  let module Color = Mosaic.Ansi.Color in
  let style = Mosaic.Ansi.Style.make in
  let background = Color.of_rgb 11 13 14 in
  let panel = Color.of_rgb 17 20 22 in
  let element = Color.of_rgb 23 27 30 in
  let selection = Color.of_rgb 25 49 58 in
  let focus = Color.of_rgb 91 186 213 in
  {
    diff =
      {
        Mosaic.Diff.default_theme with
        added_bg = Color.of_rgb 20 36 27;
        removed_bg = Color.of_rgb 42 23 28;
        added_line_number_bg = Some (Color.of_rgb 18 43 31);
        removed_line_number_bg = Some (Color.of_rgb 45 31 38);
        line_number_bg = Some panel;
        line_number_fg = Color.of_rgb 102 113 122;
      };
    background;
    panel;
    element;
    selection;
    focus;
    normal = style ~fg:(Color.of_rgb 232 236 239) ();
    muted = style ~fg:(Color.of_rgb 138 147 155) ();
    subtle = style ~fg:(Color.of_rgb 95 104 112) ();
    selected = style ~fg:(Color.of_rgb 244 250 252) ~bg:selection ();
    reviewed = style ~fg:(Color.of_rgb 121 216 143) ();
    unreviewed = style ~fg:(Color.of_rgb 230 180 80) ();
    stale = style ~fg:(Color.of_rgb 214 160 110) ();
    cr = style ~fg:(Color.of_rgb 143 184 200) ();
    warning = style ~fg:(Color.of_rgb 230 180 80) ();
    error = style ~fg:(Color.of_rgb 224 108 117) ~bold:true ();
  }
