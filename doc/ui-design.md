# Sift UI design specification

Sift should feel like a calm, precise review instrument: fast to scan, hard to
get lost in, and visually quiet until something deserves attention. The
interface should be minimalist, but not bare. It should look intentionally
composed: clear hierarchy, restrained color, generous alignment, and no
ornament that does not help review.

The target reaction is: this is clean, serious, and beautiful.

## Current UI Assessment

The current UI has the right structural pieces:

- queue, diff, and context panes;
- cursor-driven queue expansion;
- line and hunk reveal in the diff;
- comment composer;
- approval and review progress;
- diff syntax highlighting for OCaml;
- persisted review state through the standalone runner.

The issue is presentation and hierarchy. The screen currently reads like a
debugging tool for the data model rather than a polished review product.

Specific problems:

- Every major region is boxed with a full border, so the screen has too much
  chrome and too many competing rectangles.
- Active focus is shown by a title star and bright border, which feels
  mechanical rather than designed.
- The top bar says only `Sift review`, leaving the highest-value context
  unused.
- The footer is overloaded with permanent key hints. It consumes attention even
  when the user already knows the workflow.
- Queue rows are dense strings instead of composed review objects. Status,
  progress, file kind, CR count, and path are visually flattened.
- The context pane is mostly raw pretty-printed data. It does not feel like a
  deliberate inspector.
- Empty states such as `No file selected` and `Binary file diff` are correct but
  not helpful enough.
- Comment composition appears as a full-width bottom box, which interrupts the
  review workspace instead of feeling like an inline action.
- The theme is small and hard-coded. It has useful colors, but no complete
  product palette or state tokens.
- The layout does not yet adapt across narrow, normal, and wide terminals.

The redesign should keep the underlying product model but replace the visible
surface with a tighter, more intentional review desk.

## Design Principles

### 1. One Review Surface

The diff is the product. Queue and context exist to orient and act on the diff.
The diff pane should be visually dominant at normal widths.

### 2. Hierarchy Before Decoration

Use spacing, alignment, muted text, and one or two separators before borders.
Borders are reserved for overlays, modal surfaces, the focused command palette,
and rare cases where containment is otherwise ambiguous.

### 3. State Is Semantic

Color should mean something:

- green: reviewed, approved, success;
- amber: unreviewed and warning;
- copper: stale review or seconded approval;
- red: invalid CR, removed content, blocking error;
- cyan or blue: active focus, selected source, navigational anchor;
- muted gray: secondary metadata.

No color should be used only because the screen needs more color.

### 4. Stable Geometry

Selection, status changes, CR count changes, and refresh notices must not shift
the layout unexpectedly. Use fixed-width badges, aligned count columns, and
truncated paths with stable leading indicators.

### 5. Progressive Disclosure

The default screen should show the review, not a manual. Help, commands, and
rare actions belong behind `?` and `:` or a command palette. The footer should
show current state plus one contextual next action.

### 6. Local First, Host Ready

Sift must work alone, but the design should leave space for Spice or another
host to provide semantic context, agent checkpoints, risk summaries, and
review-refresh notices without redesigning the whole screen.

## Primary Review Loop

The main loop must be excellent without opening help or the command palette.
Sift should guide the reviewer from the most important remaining work to a clean
finish.

On open:

- select the first invalid CR, else first stale unit, else first new unit, else
  first unreviewed unit, else the feature row;
- reveal the selected diff scope immediately;
- use the `outstanding` queue filter by default when there is outstanding work;
- use `all` only when everything is reviewed or the user explicitly changes
  filter.

On `space`:

- mark the current smallest reviewable scope reviewed when it is unreviewed,
  stale, or new;
- mark it unreviewed when it is already reviewed;
- never cycle through a hidden third state;
- after marking reviewed, advance to the next outstanding unit unless a modal or
  composer is open;
- after marking unreviewed, keep the current selection stable.

Completion:

- when no units remain, select the feature row;
- if approval is pending, footer says `all reviewed  a approve`;
- if approved and there are no stale units, footer says `approved  saved`;
- if seconded and there are no stale units, footer says `seconded  saved`;
- if a refresh makes the review stale, footer and feature row both show stale
  state until the user records a fresh verdict.

Required navigation commands:

- `n`: next outstanding unit;
- `p`: previous outstanding unit;
- `N`: next CR;
- `P`: previous CR;
- `f`: cycle queue filter: outstanding, CRs, stale, all.

Queue priority within each filter:

1. invalid CRs;
2. stale units;
3. new units;
4. unresolved CRs;
5. unreviewed changed hunks or lines;
6. reviewed context.

## Information Architecture

Sift has five conceptual regions:

1. Header: feature identity, review state, branch/revision context.
2. Queue: review plan and outstanding work.
3. Diff: selected file or scope.
4. Inspector: details, CRs, actions, host context.
5. Footer: repository location, transient state, compact command affordance.

The default screen should use these regions differently by terminal width.

### Wide Layout, 120 Columns and Above

Use a three-column review desk:

```text
 mosaic worktree                                82% reviewed  pending
 main..WORKTREE  6 files  2 CRs  1 stale        refreshed 12s ago

 outstanding                   lib/review/cursor.ml                  line 124
 > ! M  lib/review/cursor.ml   120 | let move ...                    Scope
   ! H  +118,14                121 | ...                             new line
   C CR alice                  122 | - old
   R H  +210,8                 123 | + new                           Comments
                                124 | + selected line                 CR alice
                                                                      Needs a clearer...

 /Users/.../mosaic        ? / : command       saved
```

Recommended proportions:

- queue: 32 to 38 columns;
- diff: flexible, minimum 48 columns;
- inspector: 34 to 46 columns;
- gaps: one column between regions;
- no full outer app border.

### Normal Layout, 90 to 119 Columns

Use queue + diff by default. The inspector becomes a right drawer toggled by
`i`. Selecting a CR updates the footer inspector summary; it must not resize the
diff by opening a drawer automatically.

```text
 mosaic worktree                            82% reviewed  pending

 outstanding                   lib/review/cursor.ml
 > ! M  lib/review/cursor.ml   120 | let move ...
   ! H  +118,14                121 | ...
   C CR alice                  122 | - old
                                123 | + new

 inspector: line 124, 1 CR      ? / : command       saved
```

### Narrow Layout, Below 90 Columns

Use a single focused surface with tabs:

```text
 sift  mosaic worktree            82% pending
 [queue] diff  info

 > ! M  lib/review/cursor.ml  3 left
   ! H  +118,14               1 CR
   C CR alice                 line 124

 j/k move   enter open   ? / : command
```

Tabs should be stateful. Moving from queue to diff keeps the same selection and
reveals the same scope.

## Visual System

### Design Identity

Sift's visual identity should be "graphite desk, precise review marks." It
should feel closer to a beautiful code editor or instrument panel than to a
dashboard. The app should be dark, quiet, compact, and sharp, with color used
as evidence.

#### Personality

Use these words as the identity filter:

- precise;
- calm;
- editorial;
- local;
- serious;
- fast;
- understated.

Avoid these:

- playful;
- neon;
- glossy;
- boxed-in;
- dashboard-like;
- noisy;
- decorative.

#### Default Palette

Use a neutral graphite base with two accents:

- quiet copper for product identity;
- amber for unresolved review attention;
- cool cyan for focus and navigation.

Default dark palette:

```text
 background              #0B0D0E
 background_panel        #111416
 background_element      #171B1E
 background_elevated     #1D2328

 text                    #E8ECEF
 text_muted              #8A939B
 text_subtle             #5F6870
 text_inverse            #071013

 border                  #2A3035
 border_subtle           #1D2328
 border_active           #4E5963

 primary                 #D6A06E
 focus                   #5BBAD5
 selection               #19313A
 selection_text          #F4FAFC

 success                 #79D88F
 warning                 #E6B450
 error                   #E06C75
 info                    #56B6C2
 notice                  #D6A06E
```

Review colors:

```text
 reviewed                #79D88F
 unreviewed              #E6B450
 stale                   #D6A06E
 cr                      #8FB8C8
 cr_invalid              #E06C75
 approval_pending        #8A939B
 approval_seconded       #D6A06E
 approval_approved       #79D88F
```

Diff colors:

```text
 diff_added              #7FD88F
 diff_removed            #E06C75
 diff_context            #A7B0B8
 diff_hunk               #8A939B
 diff_added_bg           #14241B
 diff_removed_bg         #2A171C
 diff_context_bg         #0B0D0E
 diff_line_number        #66717A
 diff_line_number_bg     #111416
 diff_selected_line_bg   #18313A
```

Color rules:

- keep the app background nearly black but not pure black;
- use panel backgrounds instead of borders for secondary regions;
- do not put saturated color behind large blocks of text except selected rows;
- use copper for quiet product identity and amber for unresolved attention;
- use cyan only for current focus, links, and selected source anchors;
- use CR labels and rail markers first; CR color is secondary;
- never combine red and green as the only distinction between states.

Contrast rules:

- normal text and actionable metadata must be at least 4.5:1 against its
  background;
- selected row text must be at least 7:1 against selection background;
- non-text state indicators and meaningful borders must be at least 3:1;
- `text_subtle` is only for nonessential chrome and may not carry actions,
  counts, errors, or review state;
- decorative borders are exempt only when they do not communicate state.

Color capability ladder:

1. Truecolor: use the palette above.
2. 256 color: map each token to the nearest xterm color and preserve contrast
   before hue.
3. 16 color: use standard terminal colors only for semantic markers; keep most
   text default foreground.
4. Monochrome: rely on rail markers, labels, bold, reverse video for selection,
   and spacing. The review must remain fully usable with color disabled.

#### Character Vocabulary

The default state vocabulary should be ASCII-first. It will look crisp in every
terminal and avoids turning review state into decoration.

The review rail has three fixed slots:

```text
 selection  state  kind  label                       meta
```

Core selection markers:

```text
 >  selected row or selected diff scope
    not selected
```

Core state markers:

```text
 R  reviewed
 !  unreviewed, stale, or needs attention
 N  new since refresh
 S  stale since refresh
 C  has unresolved CR
 x  invalid CR or failed state
 .  neutral, inherited, or informational
```

State precedence when several apply:

```text
 x invalid
 S stale
 N new
 C unresolved CR
 ! unreviewed
 R reviewed
 . neutral
```

File and scope kinds always occupy two columns:

```text
 F   feature
 M   modified file
 A   added file
 D   deleted file
 Rn  renamed file
 Cp  copied file
 H   hunk
 L   line
 CR  comment row
```

Separators:

```text
 |   ASCII vertical separator and fallback
 -   ASCII horizontal separator and fallback
 /   command prefix
 :   command palette prefix
 ..  revision range separator
```

Unicode-enhanced terminals may use:

```text
 U+2503 heavy vertical separator between main regions
 U+2500 light horizontal separator in dialogs
 U+25CF filled status dot for connected/saved states
 U+25B8 small triangular disclosure marker
```

The ASCII set remains the source of truth. Unicode glyphs are presentation
enhancements only and must have exact ASCII fallbacks.

#### Signature Motif

Sift's signature visual motif should be a left review rail: fixed columns that
carry selection, review state, and item kind.

Example:

```text
 > ! M  lib/review/cursor.ml           3 left  1 CR
   ! H  +118,14                        3 left
   C CR alice                          line 124
   R H  +210,8                         done
```

The rail makes the screen recognizable without a logo or decorative header. It
also keeps color local: markers can carry color while labels remain readable.
Use the same rail grammar in the queue, inspector summaries, refresh notices,
and diff gutter so review marks become Sift's product signature.

#### Product Wordmark

Use lowercase `sift` in compact UI chrome and prose-like `Sift` in titles and
documentation.

Header examples:

```text
 sift  main..WORKTREE                         74% reviewed  pending
```

Do not use large ASCII art in the app. It takes space away from the diff and
does not match the product's editorial tone.

#### Tone of Text

Text should be short, direct, and product-like:

```text
 No file selected
 Choose a file from the review queue.

 Binary file
 This change cannot be rendered as text.

 review stale after refresh
 selection moved to nearest hunk
 comment submitted
```

Avoid:

```text
 Oops
 Something went wrong
 Please choose a valid current review scope
 CR removal requested
```

Errors should say what failed. Notices should say what changed.
Use `change request` in help and inspector prose. Use `CR` only as a compact
badge after the full term has appeared in the current surface or help text.

### Theme Tokens

Move from ad hoc styles to a complete theme record.

Required base tokens:

```text
 background
 background_panel
 background_element
 background_elevated
 background_overlay
 background_input
 text
 text_muted
 text_subtle
 text_disabled
 text_inverse
 border
 border_subtle
 border_active
 modal_border
 selection
 selection_text
 focus
 primary
 success
 warning
 error
 info
 notice
 toast_bg
 scrollbar_thumb
 disabled_reason
```

Required review tokens:

```text
 reviewed
 unreviewed
 stale
 cr
 cr_invalid
 approval_pending
 approval_seconded
 approval_approved
```

Required diff tokens:

```text
 diff_added
 diff_removed
 diff_context
 diff_hunk
 diff_added_bg
 diff_removed_bg
 diff_context_bg
 diff_line_number
 diff_line_number_bg
 diff_added_line_number_bg
 diff_removed_line_number_bg
 diff_added_sign
 diff_removed_sign
 diff_selected_line_bg
```

The default dark theme should be neutral, not saturated. Use warm accents
sparingly: very dark background, panel step, muted gray text, one quiet
primary, one cool focus color, and semantic green/amber/copper/red.

### Borders and Separators

Do not box every pane.

Use:

- no border around the whole app;
- no full border around the diff;
- a subtle vertical separator between queue and diff on wide layouts;
- a subtle panel background for queue and inspector;
- active focus indicated by a one-cell left rail, title color, or selected row
  style;
- full border only for dialogs, help, command palette, confirmation prompts,
  and the comment composer if it floats.

### Typography and Text Treatment

Terminal typography is mostly weight, color, and spacing:

- bold only for the feature title, selected path basename, modal titles, and
  the primary command in empty states;
- muted metadata always follows primary text and never precedes it;
- paths should preserve the basename and truncate the middle when needed;
- counts should align in a short right column when the queue is wide enough;
- avoid uppercase labels except fixed badges such as `CR`, `NEW`, `STALE`.

## Header

The header should make Sift feel like a product immediately.

Contents:

- feature title, or a derived local identity such as `mosaic worktree`;
- base and tip, rendered as `base..tip`;
- progress percentage;
- approval state;
- file count and CR count;
- refresh or persistence state when relevant.

Example:

```text
 mosaic worktree                             74% reviewed  pending
 main..WORKTREE        6 files  2 CRs        saved  refreshed 12s ago
```

Rules:

- two rows on wide and normal screens;
- one compact row on narrow screens;
- no heavy background unless it is very subtle;
- progress and approval are right-aligned on wide screens;
- stale verdict state overrides normal approval color with the stale token.
- `Untitled review` is allowed only when no title, repository, branch, range, or
  worktree identity can be derived.

## Queue

The queue is not a file tree. It is the review plan. Rows should make review
status scannable at a glance.

### Row Anatomy

Every queue row has stable slots:

```text
 sel  state  kind  label/path                     meta
```

Slot contract:

```text
 sel:   width 1
 state: width 1
 kind:  width 2
 label: flexible, minimum 8 columns
 meta:  right-aligned, width 10 to 14 when space allows
```

The row renderer should use structured spans when possible, not one
pre-concatenated string. If a plain string renderer is the only option for the
first slice, it must still preserve these columns.

State markers:

```text
 R reviewed
 ! unreviewed or needs attention
 N new since refresh
 S stale since refresh
 C has unresolved CR
 x invalid CR
 . neutral / inherited
```

Kinds:

```text
 F  feature
 M  modified file
 A  added file
 D  deleted file
 Rn renamed file
 Cp copied file
 H  hunk
 L  line
 CR comment
```

Do not render `[R]`, `[!]`, or `[ ]`. Brackets add noise and make the queue feel
like a debug table.

Truncation rules:

- preserve the basename of paths;
- truncate the middle of long paths;
- use Unicode-width-aware measurement even when rendering ASCII;
- never truncate the state or kind slots;
- hide `meta` before truncating label below 8 columns.

Metadata priority:

1. `stale` or `new`;
2. `N left`;
3. `N CR`;
4. `done`;
5. approval state on the feature row.

### Feature Row

Current:

```text
. F  feature  3 left  pending
```

Target:

```text
 > ! F  feature                       3 left  pending
```

If the verdict is stale:

```text
 > S F  feature                       stale  pending
```

### File Row

Target:

```text
 > ! M  lib/review/cursor.ml          3 left  1 CR
   R A  test/test_tui.ml              done
   R D  old/path.ml                   done
```

Use color:

- selected row: focus background with selection text;
- reviewed marker: green;
- unreviewed marker: amber;
- invalid CR marker: red;
- path: normal text, basename can be brighter if rendering spans are available;
- metadata: muted.

### Hunk Row

Target:

```text
   ! H  +118,14                       3 left
   R H  -40,5 +43,9                   done
```

Hunks should be visually subordinate to files. Indent by two columns and use
muted kind labels.

### CR Row

Target:

```text
   C CR alice                         line 124
   x CR invalid change request        line 88
```

The description should be available in the inspector, not packed into the row.

### Queue Interactions

Required:

- `j/k`: move visible queue selection;
- `g/G`: first/last visible item;
- `n/p`: next/previous outstanding unit;
- `N/P`: next/previous CR;
- `f`: cycle filter: outstanding, CRs, stale, all;
- `enter`: focus diff for current selection;
- `space`: mark unreviewed/stale/new as reviewed, or reviewed as unreviewed;
- `r/u`: explicit reviewed/unreviewed actions remain available;
- `c`: comment on current line/scope when commentable;
- `?` / `:`: command palette.

Optional later:

- collapse/expand current file;
- custom sort profiles.

## Keyboard Model

Sift has one global review cursor and one active review surface. The queue
surface navigates review items. The diff surface navigates the rendered review
context. Actions apply to the current review target regardless of which surface
has keyboard focus. Closing a modal or composer must not change the review
cursor.

Focus transfer is a TEA command interpreted by Mosaic. Sift stores only the
active surface needed for rendering and behavior; it never stores
`Renderable.t` handles. Queue and diff panes expose stable focus ids, and
`Sift_tui.update` returns `Cmd.focus` when a transition moves keyboard focus.
The standalone runner must not know queue/diff focus internals.

Review surface:

- movement keys change the selected review target;
- `space`, `r`, and `u` act on the current review target;
- `c` opens composer when the current target is commentable;
- `n/p` move between outstanding review units;
- `N/P` move between change requests.

Composer:

- text input owns printable keys;
- `ctrl+enter` submits;
- `esc` cancels and restores the review surface;
- `:` and `?` do not open global modals while the textarea is focused.

Modal:

- `esc` closes the modal and restores the review surface;
- `enter` accepts the selected modal action;
- background panes remain visible but inert;
- disabled commands may appear only with a muted reason.

Represent modal state explicitly:

```ocaml
type modal =
  | No_modal
  | Command_palette of { query : string; selected : int }
  | Confirm of confirm_state
```

## Review Code Viewer

The main pane is a review code viewer with adaptive context. It defaults to a
diff, because changed code is the primary review workload, but every selected
queue target must have a faithful code representation. Selecting a CR outside
the rendered diff should expand to source context around the CR anchor instead
of leaving the previous diff view on screen.

Adaptive context is invisible as a mode. The viewer simply shows the amount of
the file needed for the selected target: compact diff by default, more file
context when the selected CR or anchor is outside the rendered hunks, and more
surrounding context when the user asks for it.

Unchanged file context can host CR anchors without becoming review progress.
Review progress is still driven by feature, file, hunk, and changed-line scopes.

## Diff

The diff is the default viewer mode. It should be quiet, readable, and stable.

### Presentation

Use the Mosaic diff renderer, but revise colors and surrounding layout:

- no full border;
- path and scope shown in a small diff title row;
- line numbers visible by default, muted;
- selected scope highlight is subtle and extends across content;
- added and removed backgrounds should be low contrast enough to read syntax;
- hunk headers should be muted info, not visually louder than code;
- binary and empty diffs should use productized empty states.

Do not rely on rendered hunk header rows unless the diff renderer owns them.
The first implementation may show hunk identity only in the diff title row and
inspector. If synthetic hunk title rows are later added, they must use
`diff_hunk` text and `diff_context_bg`, not a decorative banner.

Example title:

```text
 lib/review/cursor.ml      hunk +118,14      unified
```

For split mode:

```text
 lib/review/cursor.ml      split      old left / new right
```

Highlight precedence:

1. selected line or selected scope overlay;
2. CR anchor marker;
3. stale/new review marker;
4. added/removed/context background;
5. syntax highlighting foreground.

Selected line background should remain readable over added and removed rows. If
the renderer cannot blend colors, selected scope wins and the change sign still
communicates add/remove.

### Diff Gutter

The diff should carry Sift's review rail into the code surface. The queue tells
the user what to review; the gutter tells them why this exact line matters.

Gutter slots:

```text
 review  old-line  new-line  sign  code
```

Review markers:

```text
 > selected line or selected scope
 C line has an unresolved CR
 x invalid CR anchor
 S stale review unit
 N new review unit
 ! unreviewed changed unit
 R reviewed unit inherited from line, hunk, or file
 . no review marker
```

Rules:

- `>` is shown only for the selected source line or first line of selected hunk;
- if a line has both selection and state, selection is shown in the review slot
  and state is shown through row background plus inspector summary;
- CR anchors are visible even when the row is reviewed;
- line numbers remain muted and must not compete with review markers;
- split mode keeps review markers on both sides when the scope spans old and
  new lines.

### Empty States

Empty states should explain what happened and provide the next action.

No file:

```text
 No file selected
 Choose a file from the review queue.
```

Binary:

```text
 Binary file
 This change cannot be rendered as text.
```

No represented changes:

```text
 No text changes
 The selected scope has no renderable diff rows.
```

No reviewable changes:

```text
 No reviewable changes
 main..WORKTREE has no tracked text changes.
```

All reviewed:

```text
 All reviewed
 Approve the feature or keep browsing.
```

Deleted file:

```text
 Deleted file
 Showing removed text only.
```

Invalid CR:

```text
 Invalid change request
 Edit or remove the source comment.
```

### Diff Reveal

Keep the current reveal behavior. It is important. Tighten it:

- reveal selected lines with a margin of 4 rows;
- when a selected CR is outside rendered hunks, expand context and reveal the CR
  anchor;
- preserve scroll position when moving between CRs in the same file where
  possible;
- when a selected scope disappears after refresh, reveal the nearest surviving
  row and show a refresh notice.

### Diff Layout

Default should be `unified`.

Use `split` only when:

- user toggles it;
- terminal is wide enough for useful side-by-side review;
- a later `auto` mode can choose split above a configured width.

The layout indicator belongs in the diff title row, not in the footer hint list.

## Inspector

The context pane should become an inspector. It should answer:

- what am I looking at?
- what comments or problems are attached?
- what can I do next?

Sections:

```text
 Scope
 lib/review/cursor.ml:124 new

 Review
 3 units left
 inherited: unreviewed

 Comments
 CR alice
 Needs a clearer invariant around cursor refresh.

 Actions
 r reviewed   c comment   o open
```

Rules:

- section labels are muted;
- primary values are normal text;
- CR bodies wrap with comfortable padding;
- invalid CRs get a red marker and a concise parse error;
- host-provided semantic context appears between `Scope` and `Comments`;
- when no inspector is visible at normal widths, its one-line summary appears
  in the footer.

Per-scope templates:

Feature:

```text
 Scope
 feature

 Review
 74% reviewed
 3 units left
 approval pending

 Actions
 a approve   s second   f filter
```

File:

```text
 Scope
 lib/review/cursor.ml
 modified

 Review
 3 units left
 1 change request
 inherited: unreviewed

 Actions
 space mark reviewed   c comment   o open
```

Hunk:

```text
 Scope
 lib/review/cursor.ml
 -118,8 +118,14

 Review
 hunk unreviewed
 file 3 left

 Actions
 space mark reviewed   c comment   o open
```

Line:

```text
 Scope
 lib/review/cursor.ml:124 new

 Review
 line unreviewed
 hunk 3 left
 file 8 left

 Comments
 C alice
 Needs a clearer invariant.

 Actions
 space mark reviewed   c comment   o open
```

CR:

```text
 Scope
 lib/review/cursor.ml:124 new

 Change request
 alice
 Needs a clearer invariant.

 Actions
 e edit   d remove   o open
```

Invalid CR:

```text
 Scope
 lib/review/cursor.ml:88 new

 Change request
 invalid source comment
 expected reporter handle

 Actions
 e edit   d remove   o open
```

Template rules:

- omit empty sections rather than rendering placeholders;
- show at most two visible CR bodies before a `+N more` line;
- cap each CR body at 8 rows with an internal scroll or truncation marker;
- disabled actions stay visible only in help/command palette, where they render
  a muted reason;
- when the inspector is hidden, summarize as `line 124, 1 CR`, `hunk 3 left`,
  or `feature complete`.

## Footer

The footer should stop being a permanent command manual.

Default footer:

```text
 /Users/tmattio/Workspace/mosaic     ? / : command        saved
```

When a notice exists:

```text
 /Users/tmattio/Workspace/mosaic     refreshed: 2 new, 1 removed        saved
```

When an error exists:

```text
 error: no current CR                                       esc dismiss
```

When composing a comment:

```text
 comment on lib/review/cursor.ml:124        ctrl+enter submit   esc cancel
```

Rules:

- show at most three command affordances;
- prioritize transient state over generic hints;
- put long errors in a toast/dialog if they do not fit;
- keep repository path left-aligned and status right-aligned on wide screens.

## Command Palette

Sift needs command discoverability, but the main screen should not carry every
shortcut forever.

Open with `?` or `:`. The command palette is the single command discoverability
surface: it replaces a separate help modal unless Sift later grows long-form
manual content. It should be a centered or top-aligned modal: title, muted
close affordance, grouped selectable rows, and no ornamental border.

Capabilities:

- fuzzy search commands;
- show key binding and enabled/disabled state;
- group commands by Review, Navigation, Comments, View, System;
- execute command and close;
- show disabled reason in muted text.
- serve as keyboard help by listing the current shortcuts.

Initial commands:

```text
 Mark reviewed
 Mark unreviewed
 Clear mark
 Add comment
 Remove CR
 Approve feature
 Second feature
 Set pending
 Toggle diff layout
 Quit
```

## Comment Composer

The composer should feel like an action attached to the current scope, not a new
screen.

Preferred default: floating modal or inspector-local composer.

Wide layout:

- if inspector is visible, composer appears inside inspector under `Comments`;
- height 6 to 8 rows;
- title is `Comment on line 124` or `Comment on hunk +118,14`.

Normal/narrow layout:

- composer opens as a centered modal with width min(72, terminal - 8);
- it does not resize the main review surface.

Required behavior:

- autofocus textarea;
- placeholder is short: `Write a CR comment`;
- footer shows `ctrl+enter submit` and `esc cancel`;
- empty submit keeps focus and shows inline error;
- successful submit produces a short success notice and refreshes review if the
  host edits source.

## Refresh and Stale State

Live review is one of Sift's differentiators. Refresh must be visible and
beautiful, not surprising.

Add a refresh notice object in the TUI:

```text
 new review units
 removed review units
 new CRs
 removed CRs
 verdict became stale
 cursor relocated
```

Footer examples:

```text
 refreshed: 2 new units, 1 new CR
 refreshed: selection moved to nearest hunk
 verdict stale after refresh
```

Queue examples:

```text
   S F  feature                       stale  pending
   N M  lib/new.ml                    new
```

State should decay:

- keep refresh notice until next cursor movement or explicit dismiss;
- keep stale verdict until the user records a new verdict;
- keep stale unit badges until the unit is marked reviewed, explicitly
  dismissed, or superseded by another refresh;
- keep new unit badges until the unit is marked reviewed, explicitly dismissed,
  or superseded by another refresh;
- selecting a new or stale unit may soften the footer notice, but it must not
  erase the unit's review state.

## Responsive Behavior

Sift should define breakpoints in the TUI config or view module:

```text
 narrow: < 90 columns
 normal: 90 to 119 columns
 wide: >= 120 columns
```

Behavior:

- wide: queue, diff, inspector;
- normal: queue, diff, inspector drawer;
- narrow: tabbed single-pane;
- very short terminals: hide secondary header row first, then collapse footer
  hints, never hide the selected row or selected diff context.

Minimum viable dimensions:

```text
 width: 80 columns
 height: 24 rows
```

Below that, Sift should remain functional, but it may show compact labels and
hide metadata.

Layout algorithm:

```text
 width >= 120:
   queue      = clamp(32, 36, 38)
   inspector  = clamp(34, 40, 46)
   separators = 2 columns
   diff       = remaining width

 90 <= width < 120:
   queue      = clamp(32, 34, 36)
   diff       = remaining width
   inspector  = overlay drawer only

 width < 90:
   active tab = Queue | Diff | Info
   content    = one active surface

 width < 80 or height < 24:
   hide secondary metadata first
   hide second header row next
   collapse footer to one status cell
```

Drawer rules:

- the inspector drawer must not resize the diff while the user moves through the
  queue;
- selecting a CR may show an inspector summary in the footer, but it must not
  open the drawer automatically if doing so changes layout;
- explicit `i` toggles the drawer;
- closing the drawer restores focus to the previous pane.

Narrow tab rules:

- tab state is `Queue`, `Diff`, or `Info`;
- switching tabs preserves cursor, queue filter, diff reveal key, and scroll
  position where possible;
- `enter` from queue opens the diff tab for the selected scope;
- `esc` from diff or info returns to queue.

## Motion and Feedback

Terminal UI motion is limited, but feedback still matters:

- selection moves instantly;
- refresh and save notices are transient;
- scroll reveal should feel anchored, not jumpy;
- comment submission should show immediate state change;
- long operations should show a spinner or `loading...` in the footer;
- avoid flashing full panels.

## Accessibility and Terminal Compatibility

Required:

- color is never the only signal; markers and labels carry meaning;
- default theme has strong contrast for text and selected rows;
- selected row remains legible in light and dark terminals;
- no reliance on ambiguous glyphs for core state;
- ASCII fallback for all decorative glyphs;
- mouse is optional, never required;
- all actions are keyboard reachable.

Preferred:

- theme can adapt to terminal foreground/background in the future;
- Unicode separators and symbols can be enabled when terminal capability is
  known;
- high-contrast theme exists before first public release.

## Implementation Plan

### Phase 1: Visual Tokens and Layout

- Expand `Sift_tui.Theme.t` into product tokens.
- Define dark, light, and high-contrast token mappings for every semantic state,
  even if only the dark theme is enabled by default.
- Replace pane borders with panel backgrounds and subtle separators.
- Rebuild the header and footer.
- Add responsive layout breakpoints.
- Add golden render checks for `80x24`, `100x30`, and `140x40`.
- Include selected, stale, invalid CR, diff add/remove, and disabled-command
  states in visual fixtures.
- Keep existing review behavior unchanged.

Acceptance:

- default screen has no full outer border;
- diff is the dominant surface;
- active focus is obvious without title stars;
- footer no longer lists every key by default;
- visual fixtures pass in dark, light, and high-contrast token modes.

### Phase 2: Queue and Inspector Polish

- Replace string-concatenated queue labels with structured row rendering.
- Add stable marker, kind, label, and metadata slots.
- Turn context pane into the inspector sections described above.
- Add productized empty states.

Acceptance:

- file, hunk, and CR rows are visually distinct at a glance;
- CR bodies are readable in the inspector;
- long paths truncate without destroying row alignment.

### Phase 3: Modal Infrastructure

- Add explicit modal state.
- Add focus restoration for help, command palette, confirmation, and future
  comment composer modals.
- Add disabled-command rendering with muted reasons.
- Add overlay sizing rules and border tokens.

Acceptance:

- opening and closing a modal never loses queue, diff, or inspector focus;
- composer input is not interrupted by global `:` or `?` shortcuts;
- disabled commands are discoverable without being executable.

### Phase 4: Command Discovery

- Add command palette on `?` and `:`.
- Move most key hints out of the footer.
- Add command groups and search.

Acceptance:

- new users can discover every command from the app;
- experienced users are not shown a permanent manual.

### Phase 5: Comment and Refresh UX

- Move comment composer into inspector or modal form.
- Add refresh notices and stale verdict treatment.
- Add new unit badges and cursor-relocation notice.

Acceptance:

- adding a comment does not feel like the whole app resized;
- after refresh, the user can tell what changed and whether their verdict is
  still fresh.

### Phase 6: Theme Hardening

- Finish default dark and light themes.
- Finish high-contrast theme.
- Expand golden render tests for edge cases and terminal color fallback modes.
- Audit text truncation and wrapping at narrow, normal, and wide widths.

Acceptance:

- all semantic states are visible in dark, light, and high-contrast themes;
- the UI remains coherent at 80x24, 100x30, and 140x40.

## First Redesign Slice

The smallest useful slice is:

1. New header with feature title, range, progress, approval, file/CR counts.
2. New footer with contextual hints and notices.
3. Split review rail: selection, state, kind.
4. Border reduction: queue and inspector as subtle panels, diff unboxed.
5. Structured queue row text with stable slots and truncation.
6. Inspector section formatting for current scope and CR body.
7. Primary review loop: first outstanding selection, `space` advance, and done
   footer.

This slice should make Sift feel materially more polished without changing the
review model, persistence, comment backend, or diff renderer.

## Non-Goals

- Do not add host-specific Spice concepts to Sift core.
- Do not add decorative animation.
- Do not make the default interface a dashboard before one-feature review feels
  excellent.
- Do not hide important review state behind color alone.

## Design Bar

A Sift screen is acceptable only if all of these are true:

- At a glance, the user knows what feature they are reviewing.
- At a glance, the user knows what remains.
- The selected scope is obvious in both queue and diff.
- Selection never hides review state.
- The diff has the most visual weight.
- The footer is useful but quiet.
- There are no unexplained bright colors.
- There are no competing boxes.
- Empty states explain what to do next.
- The app is usable without reading documentation.
- The app remains usable in monochrome mode.
- The screen still looks intentional after a refresh, an error, and an open
  comment composer.
