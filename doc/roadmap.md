# Sift roadmap

This roadmap is the technical implementation companion to `doc/spec.md` and
`doc/model.md`. The spec is the product contract, `model.md` preserves the
detailed behavior contracts, and this file turns them into milestones and likely
module work.

The goal is not to clone Iron immediately. The goal is to ship a small,
excellent feature-diff review tool whose design can grow toward
Jane-Street-style review memory and Spice live-agent supervision without
changing the core shape.

## Status

Current phase: help and command discoverability.

Overall state:

- [x] Core feature/diff/review model exists.
- [x] Standalone worktree review opens uncommitted tracked changes by default.
- [x] TUI has queue, diff, context, source CR add/edit/remove/resolve, and
  OCaml diff highlighting.
- [x] Standalone CLI persists marks, verdict, and cursor.
- [x] Refresh UX clearly reports changed review units and stale verdicts.
- [x] CR edit and resolve workflows are complete.
- [x] Standalone worktree review watches and refreshes by default.
- [ ] Command discovery and help surface exists and is complete.
- [ ] First-version polish is complete.

Milestone progress:

- [x] Milestone 1: Persistent standalone review.
- [x] Milestone 2: Refresh and checkpoint UX.
- [x] Milestone 3: Comment action abstraction.
- [x] Milestone 4: Live worktree refresh.
- [ ] Milestone 5: Help and command discoverability.
- [ ] Milestone 6: Review sequence and queue ordering.
- [ ] Milestone 7: Open current scope in real files.
- [ ] Milestone 8: First release hardening.

Immediate next work:

1. Make the `?` help or command palette complete and accurate for the current
   command surface.
2. Add command discoverability for refresh, comment, verdict, and navigation
   actions.
3. Add release-hardening coverage for CR edit/resolve reload-and-focus behavior.

Known blockers:

- none that should block the first usable milestone.

## North star

Sift is a feature-diff review layer.

The central invariant is:

```text
feature content = diff(base, tip)
review surface = current review scope + surrounding context + available actions
```

For v1, Sift should make base-to-tip review fast and useful in a terminal:

- review uncommitted worktree changes by default;
- keep mutable worktree reviews current as source changes;
- review an explicit `base..tip` feature when requested;
- navigate a deliberate review queue;
- add, inspect, edit, remove, and resolve CR feedback;
- mark feature/file/hunk scopes reviewed or unreviewed;
- record a whole-feature verdict;
- preserve state when the feature refreshes.

Spice should be able to use the same review model by repeatedly replacing the
feature tip with live agent checkpoints.

## Current state

Already implemented:

- `sift.diff`: unified diff parsing and computed text diffs.
- `sift.feature`: base/tip feature wrapper over a diff.
- `sift.crs`: inline CR parsing and source edits.
- `sift.review`: review state, cursor, marks, whole-feature approval/verdict,
  refresh.
- `sift.git`: Git feature loading, including uncommitted tracked worktree
  changes.
- `sift.store`: JSON-ish persistent review records.
- `sift.tui`: queue/diff/context review screen, comment action events,
  refresh notices, OCaml diff syntax highlighting, visible approval/verdict
  state.

Important current limitations:

- comments are implemented through inline source CRs only;
- queue ordering mostly follows diff order;
- the TUI has no open-in-editor event;
- CR edit/resolve needs CLI-adjacent reload-and-focus hardening coverage;
- help and command discoverability are still incomplete;
- there is no checkpoint model, review memory, ddiff, or path scrutiny engine.

## Design principles

Keep `Sift_review.t` as the waist. New work should either feed it, render it,
persist it, or derive actions from it.

Prefer derived data over durable concepts. For example, "review slice" can be a
TUI-derived view of a cursor, not a public core type, until persistence or host
integration needs it.

Keep Sift language-agnostic at the review model. Language-specific context
belongs in host-provided context panes or optional render integrations.

Keep agent concepts outside the Sift core. Sift should understand refreshed
features and checkpoints; Spice should own agent sessions, prompts, and task
execution.

Support inline source CRs as the first comment backend because they make Sift
standalone and Git-native. Do not hardwire the TUI to source mutation; route
comment actions through events so a metadata backend can be added later.

## First version

The first version should be a useful standalone review tool for one local Git
worktree.

Before the full first version, Sift should reach a first usable milestone:

- standalone CLI persists marks, verdict, and cursor;
- standalone worktree review keeps itself current as source changes;
- refresh shows what changed and preserves orientation;
- CR add, edit, and remove work reliably through the inline source backend;
- the TUI has a command discovery and help surface;
- Sift remains useful without Spice.

This smaller milestone validates the local review loop before adding review
sequencing and editor integration polish.

### User promise

From a Git repository, `sift` opens the current uncommitted tracked changes and
keeps the review current as the worktree changes. The reviewer can read the
diff, leave CRs, remove CRs, mark work reviewed, record a whole-feature verdict,
and let Sift refresh after edits without losing orientation.

Explicit ranges should still work:

```sh
sift --base main --tip HEAD
```

V1 should distinguish read-only tree review from mutable worktree review. When
the reviewer writes a source CR during an explicit range review, Sift should
edit the worktree, switch the live review surface to `base -> worktree`, and
make that transition visible. Once in worktree review, refresh is live by
default.

### V1 scope

Ship these capabilities before expanding the product model:

1. Persist review state.
2. Make refresh/checkpoint UX robust.
3. Complete CR actions: add, remove, edit, and resolve.
4. Add live worktree refresh.
5. Add command discovery and help.
6. Improve review queue ordering and labels.
7. Add open-in-editor/source-location events.
8. Stabilize standalone CLI behavior and documentation.

## Milestone 1: Persistent standalone review

The standalone CLI uses `sift.store` as the durable source for marks, verdict,
cursor, and local review state.

Implement:

- derive a stable store key from repository root, base revision, and review mode;
- use repository + base + tip for explicit feature reviews unless a stronger
  feature id exists;
- use repository + base + worktree mode for live worktree review, because the
  tip is intentionally moving;
- load store state on startup;
- merge store state with freshly loaded feature input using `Sift_review.refresh`;
- persist on every `Review_changed`;
- persist cursor, verdict, and verdict freshness;
- handle explicit range review and worktree review separately enough that marks
  do not cross-contaminate unrelated reviews.

Suggested files:

- `sift/bin/main.ml`: wire store load/save.
- `sift/lib/store/*`: adjust record shape only if necessary.
- `sift/test/test_store.ml`, `sift/test/test_git.ml`: add CLI-adjacent store
  behavior through library-level tests where possible.

Acceptance:

- mark a hunk reviewed, quit, reopen, mark is still there;
- approve or second, quit, reopen, verdict is still visible in the feature row;
- adding/removing a CR reloads the review without dropping persisted marks that
  still map to current scopes.

## Milestone 2: Refresh and checkpoint UX

`Replace_review` is currently too quiet. Spice and live worktree review both
need refresh to be an explicit review event.

Implement a UI-local refresh summary:

```ocaml
type refresh_notice = {
  new_review_units : int;
  removed_review_units : int;
  new_crs : int;
  removed_crs : int;
  verdict_reset : bool;
  stale_verdict : bool;
}
```

This should be derived inside `sift.tui` when replacing the review, not computed
by the host.

Add:

- `Replace_review` preserves cursor when possible;
- `Replace_review_and_select` remains the path for comment writes;
- status/footer shows a concise refresh notice;
- feature row and footer make stale verdicts visible;
- command to jump to first new review unit;
- tests for stale cursor clamp, new CR count, and verdict freshness visibility.

Define review-unit identity enough for v1 refresh:

- files by path;
- hunks by content-derived identity when possible, with range-derived fallback;
- lines by path, side, line number, and nearby context when available;
- CRs by parsed identity and source range.

When confidence is low, treat the unit as new and unreviewed.

Keep this local to the TUI until the store or Spice needs the data.

Acceptance:

- while reviewing a file, refresh keeps the same file/hunk if still valid;
- when the selected scope disappears, cursor moves to the nearest useful visible
  queue row, not always feature top;
- after an agent/checkpoint update, the user sees what changed;
- a verdict recorded for an older tip cannot look fresh after content changes.

## Milestone 3: Comment action abstraction

The TUI should not know how comments are stored. It should emit actions. The
standalone runner can continue implementing those actions by editing source CRs.

Keep or add events like:

```ocaml
type event =
  | Comment_submitted of comment
  | Cr_removed of cr
  | Cr_edited of cr * string
  | Cr_resolved of cr
```

Implement:

- edit CR body with `e`;
- remove CR with `d`;
- resolve CR with `R`;
- document and test the v1 inline CR grammar:

  ```text
  CR [recipient]: body
  CR-soon [recipient]: body
  XCR [resolver] for [recipient]: body
  ```

- status/error feedback when command is unavailable;
- CR row label includes reporter, status, priority, and body snippet;
- context pane shows full CR body and available actions.

For inline source CRs:

- `add` uses `Sift_crs.Edit.attach`;
- `edit` uses `Sift_crs.Edit.replace`;
- `remove` uses `Sift_crs.Edit.remove`;
- `resolve` means "addressed"; it should preserve history when the backend
  supports that, for example by converting `CR` to `XCR`. If the inline source
  backend cannot represent resolution yet, removal is an acceptable temporary
  implementation detail, not the product semantics.

`sift.tui` must never call `Sift_crs.Edit` directly. Source mutation belongs to
the standalone runner or another comment backend.

Acceptance:

- a reviewer can add, edit, and remove a CR without leaving Sift;
- after each action, Sift reloads and focuses the affected CR or nearby scope;
- CR rows are readable enough to scan without opening context.

## Milestone 4: Live worktree refresh

Standalone Sift should be live by default for mutable worktree review. The user
should not need to remember to refresh after an editor save, formatter run, or
agent checkpoint.

Keep watching out of `sift.review` and `sift.tui`. It belongs in the standalone
runner or host layer and should feed refreshed review input through the same
`Sift_review.refresh` and `Replace_review` path as manual refresh and Spice
checkpoints.

Implement:

- watch tracked worktree source changes by default in `sift`;
- debounce change bursts before reloading;
- reload `base -> WORKTREE` and scan CRs from changed worktree files;
- preserve marks, cursor, CR focus, and verdict freshness through
  `Sift_review.refresh`;
- dispatch `Replace_review` for ordinary watched refreshes;
- keep `Replace_review_and_select` for comment writes that should focus an
  affected CR;
- keep the old review visible if reload fails and report the error as a
  non-destructive UI notice;
- avoid adding an external watcher dependency to Sift core.

Acceptance:

- saving a tracked changed file refreshes the review without restarting Sift;
- repeated save/formatter bursts produce one visible refresh notice;
- while reviewing a still-valid scope, refresh preserves the current cursor;
- when the selected scope disappears, refresh moves to a nearby useful row;
- stale verdicts remain visible after watched content changes;
- reload errors do not blank or replace the current review;
- explicit `base..tip` review remains read-only until a source-mutating action
  transitions it to live `base..WORKTREE`.

## Milestone 5: Help and command discoverability

Add a `?` help surface. The preferred direction is a command palette opened by
both `?` and `:`, as described in `doc/command-palette-next.md`, but an overlay
is acceptable as an intermediate shape while the command model settles.

It should show:

- navigation commands;
- mark commands;
- verdict commands;
- comment commands;
- refresh/open commands;
- what each command applies to.

Keep it as explicit TUI state:

```ocaml
type overlay =
  | No_overlay
  | Help
  | Command_palette of { query : string; selected : int }
```

Acceptance:

- pressing `?` opens help or the command palette;
- pressing `:` opens the command palette when that surface exists;
- `Esc` closes the surface and restores the previous focus;
- footer advertises the command discovery surface, preferably as
  `? / : command`.

## Milestone 6: Review sequence and queue ordering

The spec’s strongest UX correction is that Sift should be review-sequence-first,
not raw-file-order-first.

Add a derived queue ordering module:

```text
sift/lib/tui/review_sequence.ml
sift/lib/tui/review_sequence.mli
```

This module should classify files and produce a reading order. Start with
heuristics:

- public interfaces before implementations for OCaml when both changed;
- implementation/source files before tests;
- tests before generated, lock, vendored, or mechanical files;
- CR rows adjacent to their file or hunk;
- binary files last unless they are the only changes.

Do not make this policy durable yet. It is a UI-derived ordering strategy.

Acceptance:

- queue order is deterministic;
- tests show main files before tests and generated files last;
- users can still see all files and CRs;
- no public core model changes are needed.

## Milestone 7: Open current scope in real files

The spec is right that one-keystroke jump to a real workspace file is essential.

Add a host-owned event:

```ocaml
type open_target = {
  path : string;
  line : int option;
  side : Sift_review.Scope.side option;
}

type event += Open_requested of open_target
```

Or, without extending public types too much, start with:

```ocaml
| Open_requested of Sift_review.Cursor.t
```

and let the runner derive path and line from the current review.

Standalone behavior:

- read `$EDITOR` or `$VISUAL`;
- support `editor +line file` for common CLI editors;
- show error if no editor is configured.

Spice behavior:

- open the file in Spice's worktree pane or editor integration.

Acceptance:

- pressing Enter or `o` from a file/hunk/line/CR opens the corresponding source
  file;
- CR opens at the CR line;
- hunk opens at the first new-side line when available.

## Milestone 8: First release hardening

Before the first release:

- document CLI modes in `sift/README.md`;
- document read-only tree review vs mutable worktree review;
- document that mutable worktree review watches and refreshes by default;
- document inline CR syntax and known limitations;
- document review marks, feature verdicts, and stale verdict semantics;
- add a small demo fixture or screenshot;
- ensure `dune build @install` and relevant tests pass;
- document that untracked files are intentionally excluded from v1 worktree
  review unless added to the Git index;
- add a no-reviewable-changes empty state that shows repository, mode,
  base/tip, help, and quit commands;
- avoid any dependency on Spice for standalone usefulness.

First release non-goals:

- full brain/ddiff review memory;
- path scrutiny policy;
- hierarchical features;
- server sync;
- PR integration;
- agent tasking.

## Post-v1: Spice integration

Spice should treat Sift as the review layer, not as the agent runtime.

Required Sift APIs:

- replace current review from a new feature/checkpoint;
- preserve orientation and show refresh notice;
- emit comment/open/action events;
- accept host-rendered context pane or context section;
- expose current cursor/scope/path/line/CR for Spice semantics.

Spice owns:

- agent sessions;
- worktree lifecycle;
- checkpoint creation policy;
- semantic OCaml context;
- tasking agents to address CRs.

Checkpoint semantics:

- a checkpoint is a refreshed feature input plus metadata;
- Sift does not need an `Agent_session` type;
- Sift may eventually expose a `Checkpoint` wrapper if refresh metadata becomes
  durable.

## Post-v1: Review memory and ddiff

The long-term differentiator is review memory.

Prototype after v1:

- store reviewed content, not only reviewed scopes;
- compute outstanding review as a ddiff between reviewed delta and current
  `diff(base, tip)`;
- carry confidence across refresh/rebase;
- expose “rereview from current” escape hatch.

Likely implementation options:

- patch algebra over normalized file diffs;
- tree-based matching for moved code;
- hybrid patch anchors with confidence-scored fallback.

Do not commit to the representation before prototyping. The public requirement
is clear; the best Git-native representation is not.

## Post-v1: Policy and scrutiny

Path-sensitive scrutiny should be a policy layer over the review model.

Start with a repo config:

```text
path pattern
required verdict
required seconder count
owner requirement
allow follow-up
```

The output should be derived obligations:

- feature needs seconder;
- path needs owner review;
- blocking CR prevents approved or seconded verdict;
- scrutiny increase requires rereview.

Keep `Obligation` as a derived policy result until real persistence needs force a
durable representation.

## First version checklist

- [x] Persist review marks, cursor, and verdict in standalone CLI.
- [x] Improve refresh notices and cursor preservation.
- [x] Surface stale verdicts after content changes.
- [x] Add CR edit and resolve workflows.
- [x] Add live watched worktree refresh.
- [ ] Add command discovery and help.
- [x] Improve CR labels and context pane.
- [ ] Add review sequence ordering.
- [ ] Add open-current-source action.
- [ ] Add no-reviewable-changes empty state.
- [x] Document CLI and CR workflows.
- [ ] Run `dune build @install` and focused Sift tests.
