# Sift and Spice integration

This document defines how Spice should use Sift as its review layer.

It is not a full Spice product spec. It is the integration contract: what Sift
owns, what Spice owns, how data crosses the boundary, and how the combined user
experience should feel.

## Product Intent

In Spice, Sift should not feel like a separate product. The user should not
feel that they have left Spice and entered "the Sift app". Review is one Spice
screen, with Spice navigation, Spice status, Spice semantic context, and Spice
agent state.

Sift supplies the review mechanics:

- feature diff model;
- review queue;
- changed-code navigation;
- CR indexing;
- review marks;
- whole-feature verdicts;
- refresh behavior;
- comment/open/action events.

Spice supplies the coding-agent environment:

- project and module graph;
- semantic OCaml targets;
- agent sessions;
- worktree and checkpoint lifecycle;
- dune/build diagnostics;
- source mutation policy;
- CR-to-agent tasking;
- Spice shell, commands, keymap, and visual style.

The narrow waist is still:

```text
Sift_review.t
```

Spice produces refreshed reviews. Sift renders and updates them. Spice reacts to
Sift events.

## Boundary Rule

Sift must stay a review component. Spice must stay the host.

Sift must not own:

- Spice agents;
- OCaml semantic lookup;
- dune RPC or build watching;
- filesystem watching;
- agent checkpoints;
- source mutation inside the embedded TUI;
- Spice task policy.

Spice must not duplicate:

- diff review state;
- review marks;
- feature verdicts;
- queue/diff review mechanics;
- CR rendering and navigation rules.

The standalone `sift` binary may edit source CRs directly through its runner.
Embedded `sift.tui` must not. In Spice, comment actions are emitted as events
and handled by Spice's semantic runtime.

## Integration Shape

Spice embeds Sift as a Mosaic/TEA child component, not as a subprocess.

Conceptually:

```ocaml
type review_host = {
  review : Sift_tui.t;
  spice_context : Spice_context.t;
  active_agent : Agent_instance.t option;
  checkpoint : Checkpoint.t option;
}
```

Spice owns the outer application model:

```ocaml
type screen =
  | Chat
  | Agent_panel of Agent_instance.t
  | Review of review_host
  | Project
```

Sift receives:

- current `Sift_review.t`;
- host-rendered context pane content;
- host action handlers;
- replacement reviews after checkpoints.

Sift emits:

- review state changed;
- cursor changed;
- comment requested;
- CR edit/remove/resolve requested;
- open current target requested;
- quit or leave review requested.

Spice interprets those events in its own model and command loop.

## Data Flow

### From Spice to Sift

Spice constructs a Sift feature from the active worktree or checkpoint:

```text
base revision + checkpoint/worktree tip + diff(base, tip) + metadata
```

Then Spice scans CRs in the same scope and creates:

```ocaml
Sift_review.make ~feature ~cr_items
```

For live agent work, Spice does not push every filesystem twitch to Sift. It
replaces the review at meaningful checkpoints:

- agent finishes a target;
- public interface changes;
- a CR is added, edited, removed, or resolved;
- build diagnostics change;
- user asks to refresh;
- agent run completes or is cancelled.

### From Sift to Spice

Sift events are requests, not side effects.

Examples:

```ocaml
type event =
  | Review_changed of Sift_review.t
  | Cursor_changed of Sift_review.Cursor.t
  | Comment_requested of Sift_review.Scope.t
  | Cr_edit_requested of Sift_crs.Item.t
  | Cr_remove_requested of Sift_crs.Item.t
  | Cr_resolve_requested of Sift_crs.Item.t
  | Open_requested of Sift_review.Cursor.t
  | Leave_review_requested
```

Spice handles these by:

- persisting review state if needed;
- mapping cursor/scope to a semantic OCaml target;
- opening prompts or editors;
- mutating CRs transactionally;
- tasking an agent when a CR is addressed to that agent;
- refreshing Sift with a new review.

## Comment and CR Ownership

Spice should use one CR grammar across agents and Sift. If Spice keeps a
separate `crs` foundation library, it must provide a small adapter to
`Sift_crs.Item.t`; the product must not expose two CR dialects.

Sift sees CRs as review items. Spice sees CRs as workflow state.

That means:

- Sift can navigate, display, classify, and request actions on CRs;
- Spice decides whether a CR action edits source, updates metadata, or starts an
  agent task;
- Spice enforces docstring-safe CR placement;
- Spice keeps handles fresh after mutation;
- Spice rescans and refreshes Sift after every CR mutation.

For the doc agent, the common workflow is:

```text
CR spice-doc: plan: ...
XCR spice-doc for user: draft: ...
CR user for spice-doc: feedback: ...
```

Sift should not understand those prefixes as core concepts. Spice can render
them richly in the context pane and use them to drive agent queues.

## Spice UX Shape

Spice has one shell and multiple screens:

- chat;
- agent panel;
- review;
- project/status screens.

The review screen uses Sift's queue/diff/review model, but it is visually and
behaviorally a Spice screen.

### UX Principles

Spice review should follow these rules:

- review is reachable at any time with `/review` or a global review hotkey;
- leaving review returns to the previous Spice screen, not to a standalone Sift
  lifecycle;
- the active agent remains visible while reviewing through header/footer status;
- chat remains part of Spice, even if the review screen chooses not to show the
  full chat transcript;
- build, parse, and agent state use Spice wording and Spice status colors;
- Sift refresh notices are presented as Spice checkpoint notices;
- errors explain the host action that failed, such as "could not attach CR to
  @foo.Bar.fold", not only the low-level file operation;
- help is contextual: it shows review keys plus any Spice global keys available
  from the review screen.

### Shared Layout

The review screen should keep the Sift three-pane structure:

```text
Header:  Spice workspace, active agent, checkpoint, verdict, build state

Queue:   review sequence, changed files, hunks, CRs, agent-produced drafts
Diff:    selected code or doc change
Context: OCaml target, signature, implementation, references, diagnostics

Footer:  Spice command hints, agent status, refresh notices, errors
```

The header and footer belong to Spice. The queue and diff behavior belong to
Sift. The context pane is host-provided by Spice, with a Sift default fallback.

### Visual Consistency

Spice should own:

- theme tokens;
- key hint format;
- status wording;
- active-agent badges;
- build status presentation;
- modal/overlay style;
- error and warning language.

Sift should expose enough configuration for the embedded review screen to use
those tokens without forking the review UI.

The embedded screen should not show standalone-product language such as
"Sift review" as the primary title. It should read like:

```text
Spice review  /doc @mylib  checkpoint 12  build ok
```

### Navigation

Spice should preserve Sift's core review keys where possible:

- `j` / `k`: next or previous review row;
- `J` / `K`: next or previous file;
- `n` / `p`: next or previous CR;
- `r` / `u` / `x`: mark reviewed, unreviewed, clear mark;
- `a` / `s` / `P`: approve, second, pending;
- `c`: comment;
- `e`: edit selected CR or current artifact;
- `d`: remove selected CR;
- `R`: resolve selected CR;
- `o` or `enter`: open current target;
- `?`: help.

Spice may add global shell keys, but review movement and review actions should
not change between standalone Sift and embedded Spice unless there is a strong
reason.

## Spice Workflows

### Reviewing Agent-Produced Code

1. User starts an agent, for example:

   ```text
   /doc @mylib
   ```

2. Spice resolves the semantic scope and starts the agent.
3. The agent writes plan CRs or produces code/doc edits.
4. Spice creates a checkpoint and refreshes Sift with `diff(base, worktree)`.
5. User enters the Spice review screen.
6. User reviews changed code, with or without CRs.
7. User accepts, rejects, edits, marks reviewed, or leaves comments.
8. Spice turns user feedback into CRs or direct edits.
9. The agent observes CRs addressed to it and retries.
10. Spice refreshes Sift after each meaningful checkpoint.

The user can review while the agent continues working. Refresh must preserve
orientation and make new work visible without stealing focus unnecessarily.

### Reviewing Plan CRs

Plan review is still review. It should not require a separate planner UI unless
the plan has no stable code anchor.

For the doc agent:

- normal item plans are written as CRs near semantic targets;
- Sift shows those CRs in the queue;
- Spice context explains the semantic target and why the agent plans to act;
- user can remove, edit, or comment on plan CRs before execution.

If there is no stable anchor yet, such as generating a new `.mli`, Spice may use
a temporary in-memory plan view. Once the file exists, durable state should move
back into code and Sift.

### Reviewing Drafts

Drafts are normal changed code plus review-pending CRs.

For a doc draft, the review context should show:

- the selected signature item;
- old and new docstring when applicable;
- implementation evidence;
- references and call sites;
- build or parse status;
- the `XCR spice-doc for user` body.

Actions:

- accept: remove the review-pending CR;
- reject: replace it with `CR user for spice-doc: feedback: ...`;
- edit: open the artifact, then remove or update the CR according to user
  intent;
- skip: leave the CR and move on.

### Reviewing Code Without CRs

Spice must preserve Sift's non-CR review workflow. Agent-produced code is
reviewable even if no CR exists on a line.

The queue should include changed files and hunks. CRs add workflow meaning, but
they are not required for review.

This matters for:

- agent edits that produce ordinary diffs;
- user edits made during review;
- refactors where not every changed hunk has an agent note;
- live worktree review before any agent has posted CRs.

### Agent Reviewers

Agents can also review code.

In that workflow:

1. Spice runs a reviewer agent over the current Sift review scope.
2. The reviewer agent emits CRs in source or metadata.
3. Spice refreshes Sift.
4. Human user reviews those CRs in the same queue.
5. User can accept the reviewer CR, reject it, edit it, or task another agent
   to address it.

Sift does not need an "agent reviewer" concept. It only sees new CRs and new
diff content.

## Host Context

The context pane is the main place where embedded Sift becomes Spice-native.

For a selected Sift cursor, Spice derives:

```ocaml
type semantic_context = {
  target : Ocaml_ref.t option;
  signature : string option;
  implementation : string option;
  references : Reference.t list;
  crs : Cr.t list;
  diagnostics : Diagnostic.t list;
  agent : Agent_context.t option;
}
```

Spice should compute this from the current Sift cursor:

- path;
- side;
- line;
- selected CR;
- selected hunk.

If semantic lookup fails, the context pane should degrade gracefully to Sift's
default file/hunk/CR details and show why the semantic view is unavailable.

## Checkpoints and Refresh

Spice owns checkpoint policy. Sift owns refresh behavior.

A checkpoint is a meaningful review boundary, not a filesystem event:

```text
checkpoint = refreshed feature input + optional host metadata
```

Sift only needs the refreshed feature input. Spice keeps metadata such as:

- agent step;
- summary;
- build result;
- affected semantic targets;
- risk notes;
- provenance and confidence.

Refresh UX requirements:

- preserve cursor when possible;
- keep the user in the same semantic target when possible;
- show new review units and CRs;
- make stale verdicts visible;
- avoid jumping to unrelated files after comment actions;
- offer a command to jump to new work.

## Persistence

Sift persists local review state for standalone use. Spice may also persist
review state inside its own session model, but it should not fork the semantics.

The source tree remains the durable coordination channel for CR workflows.

Spice may persist:

- active agent session summary;
- last checkpoint id;
- Sift review marks and verdict via Sift store or a Spice bridge;
- UI orientation;
- semantic snapshot metadata.

Spice should not rely on hidden session state for correctness. Restarting Spice
must be able to recover useful workflow state from:

- Git/worktree contents;
- CRs in source or metadata;
- Sift's persisted review marks where available.

## API Requirements for Sift

To support Spice cleanly, Sift needs these embeddable capabilities:

- construct a TUI model from `Sift_review.t`;
- replace the review with a refreshed `Sift_review.t`;
- preserve/clamp cursor on replacement;
- expose current cursor, scope, path, line, file, and CR;
- accept a host context renderer;
- emit comment, CR action, open, and leave-review events;
- allow host-owned key handling around the Sift component;
- accept theme/status configuration from the host;
- avoid performing source mutation inside `sift.tui`.

The minimum embedding shape should feel like:

```ocaml
module Embedded : sig
  type t
  type msg

  type config = {
    context : t -> msg Mosaic.t option;
    theme : Theme.t option;
    on_event : event -> msg;
  }

  val make : config -> Sift_review.t -> t
  val update : msg -> t -> t * msg list
  val view : t -> msg Mosaic.t
  val replace_review : Sift_review.t -> t -> t
  val current_context : t -> Review_context.t
end
```

The exact module names can differ. The important part is the shape: inert review
state in, TEA messages out, host context and actions supplied from outside.

## What Not To Do

Do not:

- launch the standalone `sift` binary from Spice;
- make Spice scrape Sift's rendered UI;
- build a second Spice-only review queue;
- add OCaml semantic concepts to Sift core;
- add agent concepts to Sift core;
- let embedded `sift.tui` write source files directly;
- make CRs mandatory for reviewing agent-produced code;
- hide refreshes that invalidate a verdict;
- make the user learn separate Sift and Spice review modes.

## First Integration Milestone

The first useful integration should support one complete doc-agent loop:

1. `/doc @scope` starts the doc agent.
2. Agent writes plan or draft CRs and source edits.
3. Spice constructs `base -> worktree` review input for Sift.
4. Review screen opens inside Spice with Spice header/footer and Sift
   queue/diff mechanics.
5. Context pane shows OCaml semantic target, implementation evidence, CR body,
   and diagnostics.
6. User can accept, reject, edit, skip, comment, mark reviewed, and approve.
7. Spice mutates CRs transactionally and refreshes Sift without losing
   orientation.
8. Agent picks up feedback CRs and retries.
9. Workflow is recoverable after quitting and reopening Spice.

That milestone proves the boundary: Sift remains independently useful, and
Spice gets a native-feeling review workflow without reimplementing review.
