# Sift

Sift is a Git-native code review TUI for the moment before code leaves your
machine.

It is for work that is still local, moving, and worth reading carefully before
it becomes a pull request. It lets you review a dirty worktree with the care you
would give a PR, without creating one.

It reviews one feature at a time: the diff from a base revision to a tip
revision. The tip can be `HEAD`, a branch, a commit, or the current worktree.
Sift gives that diff a stable review surface: a queue, a focused diff, an
inspector, local review marks, a feature verdict, and code-anchored CRs.

Sift is not a pull-request client. It is the review layer before that: your own
uncommitted work, another local branch, or agent-produced changes that are still
being shaped.

```text
 sift  main..WORKTREE                         82% reviewed  pending

 outstanding                  lib/review/cursor.ml
 > ! M  lib/review/cursor.ml  120 | let move ...
   ! H  +118,14               121 | ...
   CR  alice  please rename   122 | - old
                                123 | + new

 /Users/.../mosaic            refreshed: +2 units        saved
```

```sh
sift
```

By default, Sift opens the tracked uncommitted changes in the current Git
worktree against `HEAD`.

```sh
sift --base main --tip HEAD
```

Explicit ranges review `base..tip`. If you write source CRs while reviewing an
explicit range, Sift edits the worktree and refreshes the review as
`base..WORKTREE`.

## Review Loop

Read the queue. Inspect the selected diff. Mark the smallest useful scope. Leave
CRs where the code needs work. Refresh when the worktree changes. Approve only
when the visible feature is the feature you mean to accept.

Sift keeps the local state that matters:

- reviewed and unreviewed marks;
- cursor position;
- whole-feature verdict;
- refresh notices;
- inline source CRs.

When the diff changes, Sift preserves orientation where it can and tells you
what changed. A verdict recorded for older content cannot silently look fresh.

## Inline CRs

Sift's first comment backend is intentionally simple: CRs live in source
comments. They are Git-native, inspectable in any editor, and work without a
server.

Recognized forms:

```text
CR [recipient]: body
CR-soon [recipient]: body
XCR [resolver] for [recipient]: body
```

Examples:

```ocaml
(* CR alice: document why this branch is unreachable. *)
(* CR-soon alice: this can move to a helper later. *)
(* XCR bob for alice: handled by the empty-input case. *)
```

`CR` is unresolved. `CR-soon` is a non-blocking follow-up. `XCR` records that a
CR was addressed while preserving the trail.

From the TUI:

```text
c   add a CR
e   edit the selected CR
d   remove the selected CR
R   resolve the selected CR as XCR
```

The standalone runner writes these as inline source edits, then reloads the
review and keeps the affected CR or nearby scope selected.

## Essential Keys

```text
j/k    move
space  mark reviewed and advance
c/e    add or edit a CR
d/R    remove or resolve a CR
a/s    approve or second
?      help
q      quit
```

## Model

Sift has a small core:

```text
feature content = diff(base, tip)
review surface = current scope + context + available actions
```

The core review model is pure. Git loading, persistence, and source mutation
live at the edges. That makes Sift usable on its own and suitable as the review
component for hosts such as Spice.

## Built For

Sift owns local diff review:

- pre-PR review of your own work;
- local review of another branch;
- supervision of agent-produced changes;
- review state that survives refreshes.

It does not own Git hosting, CI, issue tracking, branch policy, agent execution,
or OCaml semantic analysis.

Current local worktree review intentionally ignores untracked files. Add a new
file to the Git index when you want it reviewed.

Sift is under active development. The standalone local review loop is usable;
editor integration and first-release polish are still moving.

## Acknowledgements

Sift's inline CR model is compatible with the CR syntax used by
[crs](https://github.com/mbarbin/crs) and is inspired by Jane Street's
[Iron](https://github.com/janestreet/iron) review comments.
