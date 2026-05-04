# Sift product specification

Sift is a Git-native, terminal-first code review layer for local worktrees and
live agent-produced changes.

Sift reviews features: the diff from a base revision to a tip revision. The tip
may be a commit, branch head, worktree snapshot, or host-provided checkpoint.
Reviewers navigate a stable review queue, inspect diffs with context, leave
code-anchored CR feedback, mark scopes reviewed, and record a whole-feature
verdict.

Sift is also intended to be the review layer for Spice, a TUI coding agent
specialized for OCaml. Spice owns agents, worktrees, OCaml semantic context, and
agent tasking. Sift owns diff review, CR indexing, review state, persistence,
and the review UI.

This document is the product contract. Detailed model and behavior notes live in
`model.md`. UI direction lives in `ui-design.md`. Spice integration details live
in `spice-integration.md`. The implementation plan lives in `roadmap.md`.

## Status

Stage: first-release hardening.

Current focus:

- complete help and command discoverability;
- finalize deterministic review queue ordering;
- open the current review target in a real editor;
- harden CR edit, resolve, reload, and focus behavior;
- keep standalone Sift useful without Spice.

V1 starts directly in one feature review. A later dashboard can list reviewable
features, agent checkpoints, assigned CRs, and stale verdicts.

## Product Bet

Sift is not a pull-request client. Pull requests are an integration target.
Sift's native environment is the local or host-managed workspace where code is
still changing.

Sift should feel useful in three situations:

- a human reviews their own uncommitted work before publishing it;
- a human reviews another branch or feature in a local worktree;
- a human supervises code produced by an agent while that agent is still
  working.

The first released version should be excellent for a single local Git worktree.
The longer-term product should support Jane-Street-style incremental review:
review memory, diff-of-diffs, path-sensitive scrutiny, and stacked features.

## Users

Primary user: a developer who wants to review a local feature before publishing
it. They need fast navigation, stable orientation, local persistence, and a way
to leave code-anchored feedback without leaving the terminal.

Secondary user: a reviewer inspecting another branch or fixed tip locally. They
need a deliberate queue, clear verdict state, and confidence that source edits
or refreshes do not make their review state misleading.

Host integrator: Spice or another tool that embeds Sift as a review component.
The host needs to replace feature inputs, provide richer context, receive
comment and open-current events, and keep ownership of agents, semantics, and
workspace policy.

## Principles

- Feature diffs are the review unit. Sift reviews `diff(base, tip)`, not a PR,
  task, issue, agent session, or raw filesystem stream.
- Local first. Sift must be useful with only Git, a terminal, and local storage.
- Stable orientation matters. Refreshes should preserve cursor and marks when
  safe, and make new or stale work visible.
- Review marks are not verdicts. Marks track local progress through scopes. A
  verdict records whole-feature acceptance state.
- CR feedback is useful but optional. Reviewing ordinary changed code without
  existing CRs is a first-class workflow.
- Sift owns review, not hosting. Git hosting, CI, issue tracking, branch policy,
  release management, agent execution, and OCaml semantic analysis belong to
  integrations.
- The core model stays small. Hosts may add context, policy, and tasking without
  pushing those concepts into Sift's durable review state too early.

## Core Model

The central invariant is:

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

The detailed product model is in `model.md`, including feature metadata, review
modes, scopes, review units, marks, verdict freshness, inline CR grammar,
refresh behavior, persistence keys, review memory, policy, and performance
expectations.

## Milestones

### First Usable Milestone

Before the full V1 release, Sift should validate the core local review loop:

- standalone CLI persists marks, verdict, and cursor;
- standalone worktree review refreshes automatically as the worktree changes;
- refresh shows what changed and preserves orientation;
- CR add, edit, remove, and resolve work reliably through the inline source
  backend;
- the TUI has a command discovery and help surface;
- Sift remains usable without Spice.

This milestone is intentionally smaller than V1. It validates the core local
review loop before adding review sequencing and editor integration polish.

### V1 Standalone Local Review

V1 ships a standalone local review TUI that can:

- open and keep current uncommitted tracked worktree changes by default;
- open an explicit `base..tip` feature when requested;
- show a stable review queue, diff pane, and context pane;
- add, inspect, edit, remove, and resolve CR feedback;
- mark feature, file, hunk, or line scopes reviewed or unreviewed;
- record a whole-feature verdict;
- persist review marks, verdict, cursor, and local state;
- refresh after source changes without losing orientation;
- open the current review target in a real editor;
- expose host events so Spice can replace the review and provide OCaml context.

### V1.5 Spice Embedding

After the standalone loop is solid, Spice should be able to use Sift as its
review component:

- Spice provides worktrees, agent sessions, checkpoints, OCaml semantic context,
  build and test diagnostics, and CR-to-agent tasking.
- Sift provides the review model, refresh behavior, queue/diff/context UI,
  comment action events, open-current events, cursor/scope accessors, and a host
  context hook.
- Spice refreshes Sift at meaningful checkpoints instead of every raw
  filesystem change.

The full contract is in `spice-integration.md`.

### Long-Term Product

Sift should eventually support:

- review memory and ddiff-based rereview;
- live agent checkpoints;
- checkpoint refresh notices and risk summaries;
- path-sensitive scrutiny policy;
- stacked or parent/child features;
- CR-to-agent tasking through Spice;
- optional metadata-backed comment storage;
- local-first shared review sync.

## Core Workflows

### Dirty Worktree Review

`sift` discovers the current Git repository, loads uncommitted tracked changes
against `HEAD`, scans CRs from changed worktree files, loads persisted local
state, opens the TUI, and watches the mutable worktree by default.

The review includes staged changes and modifications to tracked files. Untracked
files are intentionally out of scope for V1. Users must add new files to the Git
index before Sift reviews them. A later `--include-untracked` mode can make
untracked-file review explicit.

### Explicit Feature Review

`sift --base BASE --tip TIP` computes `diff(base, tip)`, scans CRs from the tip
tree, loads persisted state for that feature, and opens the same review UI.

If the reviewer writes source CRs while reviewing an explicit fixed tip, the
standalone runner edits files in the worktree, transitions the review surface to
`base -> worktree`, preserves state through refresh, and continues as a live
watched worktree review.

### Refresh

Refresh replaces the current feature input while preserving local review state
where safe:

- preserve cursor when the cursor still points at a valid target;
- otherwise move to the nearest useful visible queue row;
- preserve marks for still-present reviewed units;
- treat new review units as unreviewed;
- make the feature verdict stale or reset it to pending if the feature content
  materially changed;
- replace the CR index with CRs scanned from the new feature content;
- surface a refresh notice in the UI.

Watched, manual, and host-driven refreshes use the same behavior. Reload errors
must be non-destructive: keep the old review visible and report the error as a
notice.

### CR Feedback

V1 uses inline source CRs as the default storage backend because they are
Git-native, inspectable, local, and close enough to Jane-Street-style CR habits
to validate the workflow.

The TUI must not edit source directly. It emits comment action events:

- add comment;
- edit CR;
- remove CR;
- resolve CR.

The standalone CLI handles those events by editing source comments. Future
metadata-backed comments should handle the same events without changing the TUI
contract.

The recognized inline CR grammar, parsed fields, remove/resolve behavior, and
storage tradeoffs are specified in `model.md`.

### No-Change State

If there are no reviewable changes, Sift opens a polished empty-state screen
rather than failing cryptically. The empty state shows:

- repository root;
- selected review mode and base/tip;
- that no changed files were found;
- useful commands, including quit and help.

## UI Requirements

The main review screen has four stable areas:

```text
Header:  feature title, base..tip, verdict, refresh status

Queue:   feature, files, hunks, CRs, unreviewed work
Viewer:  selected file/hunk/line/CR code context
Context: feature details, CR details, host-provided context

Footer:  progress, errors, notices, key hints
```

The UI is scope-centric. Files, hunks, lines, CRs, and host semantic context are
all ways to inspect or act on the current review scope.

V1 must provide:

- a queue with feature, file, hunk, and adjacent CR rows;
- a review code viewer that always renders the selected target;
- adaptive context for CR anchors outside rendered hunks;
- visible review progress, verdict, freshness, CR count, notices, and errors;
- syntax highlighting where the render stack supports it, with OCaml `.ml` and
  `.mli` important for Spice;
- `?` help or command palette with every command and the target each command
  applies to.

The detailed visual direction and screen layout live in `ui-design.md`.

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

## Acceptance Criteria

The first version is ready when:

- `sift` opens current uncommitted tracked changes by default;
- default worktree review stays current after tracked source changes;
- `sift --base BASE --tip TIP` opens an explicit feature;
- review marks, verdict, and cursor persist across restarts;
- feature row shows verdict state and freshness;
- CRs can be added, edited, removed, and resolved from the TUI;
- CR rows are visible near their file or hunk;
- refresh preserves orientation and shows what changed;
- stale verdicts are visible after feature content changes;
- no-change repositories show a useful empty state;
- current scope can be opened in a real file;
- `?` shows help or the command palette;
- queue order is deterministic and review-oriented;
- Sift remains usable without Spice;
- Spice can host Sift by replacing reviews and rendering extra context.

## Non-Goals

Sift does not own:

- Git hosting;
- issue tracking;
- CI orchestration;
- branch policy;
- agent execution;
- OCaml semantic analysis;
- release management.

Sift should integrate with those systems, not become them.

Do not block V1 on:

- ddiff brain implementation;
- path scrutiny engine;
- parent/child feature graph;
- server sync;
- PR integration;
- agent controls;
- metadata-backed comments;
- reviewer assignment;
- release gates.

These are important, but they compound on a solid local review loop.

## Open Questions

- Should the `approved` and `seconded` verdict names stay as product language,
  or should the UI use plainer terms while keeping those states internally?
- Should the default queue show all changed files, only unreviewed work, or a
  hybrid that keeps reviewed files visible but compressed?
- What is the right first interaction for selecting exact changed-line scopes in
  the viewer?
- When should Sift grow explicit untracked-file review, and should it be opt-in
  per invocation or sticky per repository?
- What minimum host API is needed before Spice embedding becomes a supported
  milestone rather than an internal integration?

## Reference Documents

- `model.md`: detailed model and behavior contracts preserved from the original
  product spec.
- `roadmap.md`: implementation milestones and current progress.
- `ui-design.md`: detailed TUI design direction.
- `spice-integration.md`: host integration contract for Spice.
- `command-palette-next.md`: next-step command discovery direction.
- `../README.md`: user-facing overview and current usage.
