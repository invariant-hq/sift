# Command Palette Next Steps

This note captures the command palette work to resume after the current
queue/diff navigation pass.

## Product Direction

The command palette is Sift's single command-discovery surface. `?` and `:`
should open the same palette, replacing a separate help modal.

## UX Work

- Selectable list and hover-to-select behavior, similar to opencode.
- Add all current review commands, not only the first batch:
  - review marks: toggle, reviewed, unreviewed, clear;
  - comments: add, edit, resolve, remove;
  - navigation: queue movement, outstanding movement, CR movement, first new
    unit, queue/diff focus;
  - view: diff layout, inspector drawer when it exists;
  - session: quit.
- Show disabled commands with muted text and a concise reason instead of hiding
  everything that is unavailable. This makes the palette useful as contextual
  help.
- Make the footer/status hint consistent with the palette being the help
  surface: prefer `? / : command` over separate `help` language.
- Ensure palette selection never changes the review cursor until a command is
  activated.
- Preserve and restore the previously focused surface when the palette closes.

## Implementation Work

- Keep command metadata as structured data: group, label, key, command,
  availability, optional disabled reason.
- Avoid turning the palette into a generic modal manager. It should render and
  operate on command entries; modal orchestration remains in `Sift_tui`.
- Add tests for:
  - `?` and `:` opening the same palette;
  - filtering preserving a valid selected index;
  - hover and arrow navigation selecting rows;
  - disabled command rendering;
  - `esc` restoring the previous focused surface;
  - activating a command closes the palette and runs only that command.

## Open Questions

- Should disabled commands be filterable by reason text?
- Should the palette remember the last query during one Sift session?
- Should queue/diff focus commands appear only after the focus navigation pass
  is fully settled?
