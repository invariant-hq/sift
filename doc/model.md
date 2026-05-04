# Sift model and behavior reference

This document preserves the detailed product model and behavior contracts behind
`spec.md`. The product spec should stay concise enough to guide decisions. This
file carries the deeper model notes that are useful during implementation.

Related documents:

- `spec.md`: product contract and release scope.
- `roadmap.md`: implementation milestones.
- `ui-design.md`: detailed TUI design direction.
- `spice-integration.md`: host integration contract for Spice.

## Core Invariant

```text
feature content = diff(base, tip)
review surface = current review scope + surrounding context + available actions
```

For V1, the outstanding review is the set of changed review units that are not
marked reviewed.

Longer term, outstanding review becomes:

```text
outstanding_review = ddiff(reviewer_brain, diff(base, tip))
```

where the reviewer brain remembers reviewed content rather than only reviewed
line scopes.

## Feature

A feature is the reviewable unit:

```text
Feature = repository + base revision + tip revision + diff(base, tip) + metadata
```

Required V1 metadata:

- optional title or description;
- base revision;
- tip revision;
- diff summary.

Future metadata:

- owner;
- parent feature;
- review-enabled state;
- scrutiny profile;
- checkpoint summary;
- risk tags;
- evidence artifacts.

Sift treats revision identifiers as opaque strings. Git support resolves those
strings. Hosts such as Spice may provide synthetic identifiers like `WORKTREE`
or `checkpoint-17`.

## Review Modes

Sift has two important local review modes:

- read-only tree review: review `base -> tip`, where `tip` is a commit, branch,
  or host-provided checkpoint;
- mutable worktree review: review `base -> worktree`, where comment actions may
  edit files in the current workspace.

Mutable worktree review is live in the standalone CLI. Sift keeps the review
current by watching the worktree, debouncing change bursts, reloading
`base -> worktree`, and feeding the refreshed feature through
`Sift_review.refresh` and the TUI replacement path.

Watching is runner or host policy, not part of `Sift_review.t`. The core model
receives refreshed review inputs and preserves state conservatively.

Source-mutating actions require mutable worktree review. If the user performs a
source-mutating action, such as adding an inline CR, while reviewing an explicit
`base..tip` feature, the standalone CLI should transition the review surface to
`base -> worktree` after the edit, make that transition visible, and then keep
the worktree review live.

Hosts may implement the same distinction differently. For example, Spice can map
mutable review to an agent worktree or checkpoint branch. Sift only needs the
resulting refreshed feature input.

## Review State

A review is local reviewer state for one feature:

- current feature;
- CR items indexed from the current feature content;
- reviewed or unreviewed marks;
- whole-feature verdict state;
- current cursor;
- UI-local orientation where appropriate.

`Sift_review.t` is the waist of the system. New producers should feed it. New
views should render it. New stores should persist it. New hosts should observe
events from it.

## Scopes

A scope identifies a review target:

- whole feature;
- file;
- hunk;
- old-side changed line;
- new-side changed line.

Scopes are the units for marks and navigation. Broader marks cover narrower
scopes. A reviewed file covers its changed lines unless a narrower unreviewed
mark overrides it.

Language-level targets such as OCaml functions, values, modules, or signatures
do not belong in Sift core. A host can derive those from the selected path and
line and display them in the context pane.

## Review Units

A review unit is the concrete changed thing that may need review:

```ocaml
type review_unit =
  | Feature
  | File of path
  | Hunk of path * hunk_id
  | Line of path * side * line_number
  | Cr of cr_id
```

This type is conceptual. V1 does not need to expose it as public API if
`Sift_review.Scope.t` already covers the required targets.

Refresh must identify review units conservatively:

- files are identified by path;
- hunks should use content-derived identity when possible, falling back to
  range-derived identity only when confidence is acceptable;
- lines are anchored by path, side, line number, and nearby context when
  available;
- CRs are identified by their source range and parsed CR identity.

If identity confidence is low, Sift should treat the unit as new and unreviewed.
It is better to ask for rereview than to silently carry review state onto
changed code.

## Review Marks

Marks record local review progress:

- reviewed;
- unreviewed;
- no explicit mark.

Marks are not verdicts. A verdict is a whole-feature decision. A feature can
have reviewed scopes while still pending a verdict, and the verdict can be
pending even when all scopes are reviewed.

When a feature refreshes, Sift must preserve marks conservatively:

- unchanged review units keep their effective review state;
- new review units are unreviewed;
- broad reviewed marks must not silently cover newly introduced lines;
- the feature verdict becomes stale or resets to pending when feature content
  materially changes.

## Feature Verdict

A feature verdict is local review state:

- pending;
- approved;
- seconded.

`approved` means the reviewer accepts the current feature state. `seconded` is
stronger: the reviewer has reviewed the whole feature, not only selected scopes.
In V1, this is local review state. It is not a merge gate, release gate, or
policy decision.

The queue must make the verdict visible in the feature row. The verdict must
also be visible in the footer or header.

The UI must also make verdict freshness visible. A reviewer should never wonder
whether their verdict applies to the currently visible code:

```ocaml
type verdict_freshness =
  | Fresh
  | Stale of { previous_tip : rev; current_tip : rev }
```

For V1, Sift may implement stale verdicts by resetting the verdict to pending
and showing a refresh notice. The product requirement is that a stale verdict is
visible and cannot be mistaken for acceptance of the current feature content.

## CR Feedback

A CR is code-anchored review feedback.

V1 uses inline source CRs as the first storage backend because they are simple,
Git-native, inspectable, and make Sift useful without a server:

```ocaml
(* CR reviewer: explain the invariant here. *)
(* CR-soon reviewer: this can follow after the main fix. *)
(* XCR author for reviewer: fixed by checking the empty case. *)
```

Recognized inline CR syntax for V1:

```text
CR [recipient]: body
CR-soon [recipient]: body
XCR [resolver] for [recipient]: body
```

The parser should produce at least:

```ocaml
type cr_kind =
  | Blocking
  | Soon
  | Resolved

type cr_item = {
  id : cr_id;
  kind : cr_kind;
  path : path;
  line_anchor : line_anchor;
  reporter : string option;
  recipient : string option;
  resolver : string option;
  body : string;
  raw_range : source_range;
}
```

Inline syntax names the CR recipient and, for resolved CRs, the resolver. The
reporter can come from the backend, Git/user configuration, or host context.

The syntax above is the subset Sift promises to understand. Jane-Street-style CR
syntax can grow additional conventions later, but V1 should keep the recognized
grammar small and documented.

The TUI must not depend on source mutation directly. It emits comment events:

- add comment;
- edit CR;
- remove CR;
- resolve CR.

The standalone CLI handles those events by editing source comments. A future
metadata backend can handle the same events without writing CRs into source.
`sift.tui` must never call `Sift_crs.Edit` directly.

Removing and resolving are different product actions:

- remove deletes the CR from the current backend;
- resolve marks the CR addressed while preserving history when the backend
  supports that;
- for the inline source backend, V1 should resolve by converting `CR` or
  `CR-soon` to an addressed form such as `XCR`.

The original draft allowed resolving by removal if no addressed representation
was available. Keep that only as historical context: product behavior should
not make resolve indistinguishable from remove.

CRs should be displayed inline in the review UI near their code context. CR rows
should include enough information to scan:

- status;
- priority or kind;
- reporter;
- recipient, if present;
- path and line;
- short body snippet.

The context pane should show the full CR body and available actions.

## Feature Refresh

A feature can change while it is being reviewed. This is normal for both human
authors and agents.

Refresh replaces the current feature input while preserving local review state
where safe:

```ocaml
Sift_review.refresh old_review ~feature:new_feature ~cr_items:new_crs
```

Refresh behavior:

- preserve cursor when the cursor still points at a valid target;
- otherwise move to the nearest useful visible queue row;
- preserve marks for still-present reviewed units;
- make the feature verdict stale or reset it to pending if the feature content
  changed;
- replace the CR index with CRs scanned from the new feature content;
- surface a refresh notice in the UI.

Watched refresh uses the same behavior as manual or host-driven refresh. The
watcher must not mutate UI state directly; it reloads review input, refreshes
the current `Sift_review.t`, and sends the replacement review to the TUI.

The TUI should derive a refresh notice:

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

The host should not need to compute this notice for V1. It is UI-derived from
the old and new review.

When a reviewer writes a CR during explicit `base..tip` review, the review-mode
transition described above applies: the standalone CLI edits the worktree,
reloads `base -> worktree`, and preserves review state through refresh.

## TUI Product Shape

The main review screen has four stable areas:

```text
Header:  feature title, base..tip, verdict, refresh status

Queue:   feature, files, hunks, CRs, unreviewed work
Viewer:  selected file/hunk/line/CR code context
Context: feature details, CR details, host-provided context

Footer:  progress, errors, notices, key hints
```

The UI is scope-centric, not file-centric, CR-centric, or agent-centric. Files,
hunks, lines, CRs, and host semantic context are all ways to inspect or act on
the current review scope.

The detailed visual design lives in `ui-design.md`.

## Queue

The queue answers:

- what am I reviewing now?
- what remains?
- where are the CRs?
- what is the feature verdict?

V1 queue rows:

- feature row;
- file rows;
- hunk rows for the expanded file;
- CR rows adjacent to their file or hunk.

The feature row must show:

- review mark;
- remaining work;
- verdict and freshness.

CR rows must be visible near the relevant file. A reviewer should not have to
scroll to a disconnected global CR list after adding a comment.

Queue navigation moves through visible queue rows. Line scopes are still valid
review targets, but they are not necessarily visible queue rows. Exact line
selection can come from diff interactions, CR focus, or host integrations.

## Review Code Viewer

The main code pane is a review code viewer with adaptive context. It defaults
to the compact diff because changed code is the primary review workload, but it
must always render the selected review target. The user should never select a
queue row and see an unrelated or stale code view.

Adaptive context is not a separate user-facing mode. It is the amount of file
context the viewer chooses to show. By default the viewer shows only the diff.
It expands automatically when the selected target would otherwise be invisible,
for example a CR anchored outside the rendered hunks. The user can also request
more surrounding file context explicitly.

Expected behavior:

- file cursor: show the file diff from top;
- hunk cursor: reveal and highlight the hunk in diff context;
- changed line cursor: reveal and highlight the line in diff context;
- CR cursor inside a rendered hunk: reveal and highlight the CR anchor in diff
  context;
- CR cursor outside rendered hunks: expand enough file context to reveal and
  highlight the CR anchor, preserving diff and CR markers where possible;
- user-expanded context: show more surrounding file content, up to the full
  current source file, with review markers and CR anchors;
- binary or empty text diffs: show concise state.

Unchanged source lines can be valid CR anchors without becoming review units.
Review marks still apply to feature, file, hunk, and changed-line scopes. Extra
file context exists to explain and act on anchors, not to redefine review
progress.

Sift should support syntax highlighting where the render stack supports it.
OCaml `.ml` and `.mli` highlighting are important because Spice is OCaml-first.

## Context Pane

The default Sift context pane shows:

- current scope;
- file or hunk summary;
- CR body and metadata;
- available actions.

Hosts may provide richer context. Spice can show:

- enclosing OCaml definition;
- signature and implementation;
- references;
- tests;
- build diagnostics;
- agent state.

Sift should not store or understand this semantic context.

## Footer and Help

The footer should show:

- verdict;
- progress;
- CR count;
- latest notice or error;
- compact key hints.

Sift should also provide a `?` help or command discovery surface with commands
and the target each command applies to. `ui-design.md` and
`command-palette-next.md` describe the stronger command-palette direction; a
separate overlay is acceptable only as an intermediate implementation shape.

## Required V1 Commands

Navigation:

- `j` / `k`: next or previous visible queue row;
- arrow down / up: same as `j` / `k`;
- `J` / `K`: next or previous file;
- `n` / `p`: next or previous CR;
- `g` / `G`: first or last visible queue row;
- `tab`: cycle panes.

Review marks:

- `space`: mark the current smallest useful scope reviewed and advance;
- `r`: mark current scope reviewed;
- `u`: mark current scope unreviewed;
- `x`: clear explicit mark.

Feature verdict:

- `a`: approve feature;
- `s`: second feature;
- `P`: return verdict to pending.

CR actions:

- `c`: add comment at current scope;
- `e`: edit selected CR;
- `d`: remove selected CR;
- `R`: resolve selected CR.

Workspace:

- `enter` or `o`: open current scope in the real file.

Other:

- `l`: toggle unified/split diff;
- `?`: help or command palette;
- `:`: command palette, if implemented separately from `?`;
- `q`: quit.

## Review Sequence

Sift should be review-sequence-first. Raw diff order is a fallback, not the
final product.

V1 should add a derived review ordering layer. It should not be durable policy
yet.

Initial heuristics:

- public interfaces before implementations when useful;
- main source before tests;
- tests before generated or mechanical files;
- generated, vendored, lock, and bulk mechanical changes last;
- CR rows adjacent to their file or hunk;
- binary files last unless they are the only changes.

The review sequence must remain deterministic and transparent. Users should be
able to see all files even if Sift suggests an order.

## Standalone CLI

Default command:

```sh
sift
```

Behavior:

- discover the Git repository from the current directory;
- load uncommitted tracked worktree changes against `HEAD`, including staged
  changes and modifications to tracked files;
- scan CRs from changed worktree files;
- load persisted local review state;
- open the TUI;
- watch the mutable worktree by default and refresh the review after debounced
  source changes.

Watched refreshes must preserve review state through `Sift_review.refresh`.
They should coalesce editor-save and formatter bursts, keep the old review
visible if reload fails, and report reload errors as non-destructive UI notices.

Untracked files are intentionally out of scope for V1 worktree review. Users
must add new files to the Git index before Sift reviews them. A later
`--include-untracked` mode can make untracked-file review explicit.

If there are no reviewable changes, Sift should open a polished empty-state
screen rather than failing cryptically. The empty state should show:

- repository root;
- selected review mode and base/tip;
- that no changed files were found;
- useful commands, including quit and help.

Explicit feature review:

```sh
sift --base main --tip HEAD
```

Behavior:

- compute `diff(base, tip)`;
- scan CRs from the tip tree;
- load persisted review state for that feature;
- open the TUI.

When the reviewer writes source CRs, the runner edits files in the worktree,
reloads `base -> worktree`, preserves review state through refresh, and then
continues as a live watched worktree review.

## Persistence

V1 must persist:

- review marks;
- verdict and freshness;
- cursor;
- feature key;
- local metadata needed to refresh safely.

The minimum refresh metadata is:

- repository identity;
- base revision;
- review mode;
- marks;
- verdict;
- cursor;
- last known feature summary.

Persistence should be local-first. A later sync service can share review state,
but local review must work without a server.

Store keys should distinguish:

- explicit feature review: repository, base revision, and tip revision, unless a
  stronger feature id is provided;
- worktree review: repository, base revision, and worktree mode, because the tip
  is intentionally moving;
- future feature id: if present, it should dominate revision-derived keys.

The store should avoid storing full source files or full diffs unless review
memory later requires a deliberate content representation.

## Comment Storage Strategy

V1 default: inline source CR backend.

Rationale:

- works without a server;
- survives normal editor workflows;
- is visible in Git;
- makes standalone Sift immediately useful;
- matches Jane-Street-style CR habits closely enough to validate the workflow.

Future backend: structured metadata rendered inline.

Rationale:

- avoids source churn;
- can support richer threaded state;
- can integrate with PR systems;
- can preserve comments across rewrite using stronger anchors.

The TUI event API should make both backends possible.

## Spice Integration Summary

Spice uses Sift as a review component.

Sift provides:

- `Sift_review.t` model;
- refresh behavior;
- queue/diff/context TUI;
- comment action events;
- open-current events;
- current cursor/scope/path/line/CR accessors;
- optional host context hook.

Spice provides:

- worktree management;
- agent sessions;
- checkpoint policy;
- OCaml semantic context;
- build and test diagnostics;
- tasking agents to address CRs.

Sift should not review every raw filesystem twitch. Spice should refresh Sift at
meaningful checkpoints:

- agent finishes a subtask;
- public interface changes;
- protected path changes;
- dependencies change;
- tests are added or removed;
- build state changes;
- conflict resolution finishes;
- user asks for a review refresh.

A checkpoint is conceptually:

```text
feature input + summary + evidence + risk digest
```

For V1, Sift only needs the refreshed feature input. Checkpoint metadata can be
host-rendered in the context pane.

The full host integration contract lives in `spice-integration.md`.

## Review Memory

Review memory is post-V1 but central to the long-term product.

The current V1 model remembers reviewed scopes. That is useful but not enough
for robust rereview after rebases, merges, or moved code.

The long-term model should remember reviewed content:

- reviewed delta;
- anchor mappings;
- confidence of mappings after refresh;
- unresolved comment context.

Sift should then show the reviewer only what changed relative to that reviewed
content.

Required behavior:

- trivial rebase should not force rereview;
- moved unchanged code should not force rereview when confidence is high;
- changed reviewed code should surface as new outstanding review;
- messy transformations should expose "discard my review memory and rereview
  from current".

The implementation representation is not decided. Candidate approaches:

- patch algebra;
- tree-based matching;
- hybrid patch anchors with confidence-scored fallback.

## Policy and Scrutiny

Path-sensitive scrutiny is post-V1.

It should be a policy layer over the review model, not a core assumption baked
into review state.

Policy inputs:

- path pattern;
- required seconder count;
- required file reviewer count;
- owner requirement;
- whether follow-ups may be deferred;
- whether scrutiny increase forces rereview;
- risk tags that elevate scrutiny.

Policy outputs:

- derived obligations;
- gate status;
- visible explanation for why a feature is not complete.

Do not make `Obligation` a durable first-class object until the policy layer
needs persistence.

## Performance

Review interactions are latency-sensitive.

Target behavior:

- queue movement feels instant;
- opening next review slice feels instant;
- adding/removing/editing CRs gives immediate feedback;
- refresh notices appear quickly;
- syntax highlighting must not block navigation.

Longer operations should be explicit and visible. A slow review tool will
collapse back into "wait for the PR".
