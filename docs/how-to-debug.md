# How to Debug LDL (and Your Home Project)

This is for debugging LDL itself, or a home project built on it, from
inside a live Lisp image — SBCL, driven from Emacs (SLIME or SLY) or from
Lem — rather than only reading error messages the compiled `ldl`
executable prints. The payoff is real: LDL signals actual Common Lisp
conditions with actual restarts, and a live REPL lets you catch one
mid-flight, inspect exactly what triggered it, and resolve it
interactively instead of just reading a one-line error and guessing.

---

## 1. Prerequisites

- **SBCL** on your `PATH`.
- **Emacs** with **SLIME** or **SLY** installed, *or* **Lem** (which
  speaks a SWANK-compatible protocol out of the box, no separate
  slime/sly package needed).
- The `ldl` source tree somewhere on disk — this guide assumes
  `~/Projects/ldl/` and, for the worked example, a home project at
  `~/Projects/my-home/`. Adjust paths to match your own layout.

You do not need Quicklisp for this — LDL depends only on `asdf` and
`uiop`, both bundled with SBCL.

---

## 2. Setting up the editor side

### Emacs + SLIME

If you don't already have it, install SLIME (via `package-install slime`
if you're using a package archive like MELPA, or via `straight.el` /
`use-package` if that's your setup):

```elisp
(use-package slime
  :config
  (setq inferior-lisp-program "sbcl"))
```

Start it with `M-x slime`. This launches an inferior SBCL process and
connects to it, opening a REPL buffer (`*slime-repl sbcl*`).

### Emacs + SLY

SLY is a maintained fork of SLIME with a similar keybinding surface;
install it (`package-install sly`, or your package manager's
equivalent):

```elisp
(use-package sly
  :config
  (setq sly-lisp-implementations '((sbcl ("sbcl")))))
```

Start it with `M-x sly`.

### Lem

Lem ships its own Lisp integration (`lem-lisp-mode`) built on a
SWANK-compatible protocol, so there's nothing extra to install for basic
use. Open or create a `.lisp` file, and start/connect a Lisp process
from within Lem (consult `M-x lem-lisp-mode:` command prefix, or your
Lem version's own documentation for the exact start/connect commands —
these have moved around between Lem releases). Once connected, the
workflow described below — compiling forms, inspecting variables,
handling conditions interactively — works the same way, since it's the
same underlying protocol family as SLIME/SLY.

Everything past this point refers to SLIME's default keybindings; SLY's
are close enough to be interchangeable in almost every case (occasionally
`slime-foo` is just `sly-foo` under the hood). Where Lem differs, its own
in-editor help (`C-h` equivalents / `M-x describe-key`) will show you the
locally-bound command.

---

## 3. Loading LDL into the REPL

In the REPL buffer (or via `C-x C-e`/`sly-eval-last-expression` from any
Lisp buffer), register the project and load it:

```lisp
(require :asdf)
(push #P"~/Projects/ldl/" asdf:*central-registry*)
(asdf:load-system :ldl)
```

**The one gotcha that will bite you eventually:** if you've built the
project before, edited a source file outside this Lisp image (in an
editor, via `git pull`, by re-extracting an archive over the same
directory), and ASDF's fasl cache still thinks the old compiled version
is up to date, your edits silently won't take effect. If something you
just changed doesn't seem to be happening, force a full rebuild:

```lisp
(asdf:load-system :ldl :force t)
```

This has a known, concrete history in this project — see
`docs/04-reference.md` §26 — so if you ever see behavior from a version
you thought you'd already fixed, this is the first thing to try.

---

## 4. Driving a home project from the REPL, bypassing the CLI

This is the important part. `ldl.core:main` wraps every command in a
`handler-case` that catches LDL's conditions, prints a one-line message,
and exits — that's the right behavior for a compiled CLI tool, and the
wrong behavior for debugging, because it means you never actually see
the interactive debugger (SLDB in SLIME/SLY) when something goes wrong.

Instead, call the pipeline's own internal functions directly. Everything
here lives in the `:ldl.core` package; either prefix each call with
`ldl.core:` (or `ldl.core::` for internal, unexported symbols) from
`common-lisp-user`, or switch your REPL's current package:

```lisp
(in-package :ldl.core)
```

**Careful if you do the latter:** `:ldl.core` shadows `cl:package` and
`cl:directory` (its own DSL uses those names for the `package`/`directory`
home-definition forms). If you're in that package and try to use
`cl:directory` to list files, you'll get LDL's macro instead. Either stay
in `cl-user` and use `ldl.core::` prefixes, or just remember the shadow
is there.

Now walk the pipeline by hand, one step at a time:

```lisp
;; Step 0: discovery. Safe to call repeatedly -- it resets every
;; project-scoped registry first (features, providers, catalogs, fact
;; probers, pipeline hooks), so re-running this after editing a project
;; file always reflects the current state, not stale accumulation.
(reset-project-registries)
(default-fact-probers)
(discover-plugins)
(discover-project "~/Projects/my-home")

;; Step 1: facts + profile.
(probe-all-facts)
(apply-profile :work-laptop)      ; or NIL for no profile
(fact :os)                        ; sanity-check a value
*facts*                           ; inspect the whole plist

;; Step 2: run the home definition's body now that facts exist, and see
;; exactly what it captured.
(defparameter *home* (run-current-home-thunk))
(getf *home* :use-features)
(getf *home* :actions)

;; Resolve provider actions. If a provider signals an error, or
;; missing-provider fires because a feature is ambiguous, THIS is where
;; you'll drop into the debugger, with a real backtrace into the
;; provider's own lambda.
(defparameter *provider-actions* (collect-actions-from-features (getf *home* :use-features)))

;; Combine, then dedup -- this is where action-conflict fires if two
;; actions of the same priority collide.
(defparameter *all-actions* (append (getf *home* :actions) *provider-actions*))
(defparameter *deduped* (dedup-actions *all-actions*))

;; Order -- this is where dependency-cycle fires.
(defparameter *ordered* (order-actions *deduped*))

;; Execute one action at a time, in :check mode first, so nothing
;; touches the real system while you're debugging.
(dolist (a *ordered*) (print (execute-action a :mode :check)))
```

Every one of these is an ordinary function call. If any of them signals
a condition, SLDB (or SLY's equivalent debugger buffer) opens right
there, with the full backtrace and, where LDL defines them, real
restarts you can click or press a number to invoke — see §6.

---

## 5. Inspecting global state

These special variables hold everything the pipeline has registered or
resolved. All are in `:ldl.core`:

```lisp
*facts*              ; current resolved fact plist
*feature-registry*    ; hash-table: feature name -> FEATURE struct
*providers*           ; hash-table: feature name -> list of (name fn default-p)
*catalogs*            ; hash-table: catalog name -> hash-table of entries
*profiles*            ; hash-table: profile name -> override alist
*pipeline-hooks*       ; hash-table: hook point -> list of hook functions
*action-types*         ; hash-table: action type -> executor function
*current-home-name*    ; name from the most recently run define-home
*current-home-traits*  ; its :traits
*current-home-actions* ; raw user-level actions captured by the last thunk run
*current-home-use-features* ; raw use-feature requests from the same run
```

Useful one-liners:

```lisp
;; What providers exist for a feature, and which is default?
(find-providers-for :editor)
;; => ((:VIM #<FUNCTION ...> NIL) (:EMACS #<FUNCTION ...> T))

;; What does a specific feature require?
(feature-requires (feature-by-name :development))

;; What would a provider return, in isolation, for made-up facts?
(funcall (second (assoc :emacs (find-providers-for :editor))) '(:os :fedora))

;; What's the computed identity of an action, and does it match your
;; :depends-on entry exactly? (Mismatches here are silent, not errors --
;; see docs/how-to-feature.md §9 for the exact shape per action type.)
(action-identity '(:action :package :target :git :via :system))
;; => (:PACKAGE :SYSTEM . :GIT)
```

---

## 6. Working with the condition system interactively

This is the actual payoff of doing this from a REPL instead of the CLI.
Here's exactly what's real today, per condition (some conditions only
offer a plain abort right now — this list is honest about which):

| Condition | Restarts you can actually invoke |
|---|---|
| `action-conflict` | `USE-FIRST` (keep the existing action), `USE-SECOND` (keep the new one) |
| `missing-provider` (ambiguous, 2+ providers, no default) | `SPECIFY-PROVIDER` (prompts for a provider name), `SKIP-FEATURE` (continue as if the feature resolved to no actions) |
| `missing-provider` (feature not registered at all) | none yet — plain abort |
| `dependency-cycle` | none yet — plain abort |
| everything signaled from inside `execute-action` (`execution-failure`, and anything an executor itself raises) | `RETRY`, `SKIP`, `ABORT-PROCESSING` |

When one of these fires in SLIME/SLY, the debugger buffer lists the
restarts by name and number, e.g.:

```
0: USE-FIRST   Keep definition A (the existing action)
1: USE-SECOND  Keep definition B (the new action)
2: ...         (further restarts SBCL/SLIME always offer, e.g. "Return to top level")
```

Press the number, or put point on the restart and hit `Enter`
(`sldb-invoke-restart`) in SLIME, or the SLY-equivalent in the SLDB
buffer. For `SPECIFY-PROVIDER`, invoking it interactively prompts you in
the minibuffer/REPL for a provider name — that's wired up via the
restart's `:interactive` clause, not something you need to supply
yourself.

You can also drive this without the interactive debugger at all, from
code, which is what you want when you're scripting a reproduction rather
than clicking through it live — `handler-bind` lets you pick a restart
programmatically:

```lisp
(handler-bind ((action-conflict (lambda (c) (invoke-restart 'use-second))))
  (dedup-actions (list action-a action-b)))
```

Once you're inside SLDB for *any* condition (restart-equipped or not),
you get the usual tools for free:

- `v` on a backtrace frame — jump to the source location.
- `e` — evaluate an expression in that frame's lexical environment (so
  you can inspect a local variable exactly as the failing code saw it).
- `i` (or `M-x slime-inspect` / `sly-inspect`) on any object printed in
  the REPL or backtrace — browse its slots/structure interactively.
- `q` — quit the debugger (equivalent to invoking the standard `ABORT`
  restart).

---

## 7. Editing and reloading

Once connected, you don't need to restart the REPL to pick up a change.

- **A single function**, in a `.lisp` file open in your editor: put
  point in or after the `defun`/`defmacro` and press `C-c C-c`
  (`slime-compile-defun` / `sly-compile-defun`). Redefinitions take
  effect immediately for anything called after that point — including
  code already running interactively at the REPL.
- **A whole file**: `C-c C-k` (`slime-compile-and-load-file` /
  `sly-compile-and-load-file`) compiles and loads the file you're
  visiting. This is the fast path while iterating on one file — no need
  to go through ASDF at all.
- **The whole system**, after structural changes (new files, changed
  `ldl.asd`, or if you're not sure what's stale): `(asdf:load-system
  :ldl :force t)` from the REPL.
- **A project file loaded via Discovery** (something under `features/`,
  `providers/`, etc. in a *home project*, not LDL's own source): either
  `C-c C-k` it directly if it's open in your editor, or just call
  `(discover-project "path/to/project")` again from the REPL — it's
  cheap and safe to re-run (see §4's note on `reset-project-registries`).

---

## 8. Debugging one action executor in isolation

You don't need a whole project to test one executor. Build the action
plist by hand and call it directly:

```lisp
(execute-action '(:action :copy-file :target "/tmp/test.txt" :from "test.txt"
                   :project-root "/path/to/some/project")
                :mode :check)
;; => (:STATUS :WOULD-CHANGE :TARGET "/tmp/test.txt")
```

To watch a function's calls and return values without stepping through
manually, `trace` it:

```lisp
(trace select-provider)
(trace execute-action)
;; ... drive the pipeline as in §4 ...
(untrace)  ; turn all tracing back off when you're done
```

To debug a provider function you're writing, `trace` it by whatever
symbol it's bound to, or just call it directly with a hand-built facts
plist, exactly as shown in §5's one-liners — providers are plain
functions, so there's no pipeline machinery you need to stand up just to
exercise one.

---

## 9. Turning up logging

LDL's own log levels are controlled by `ldl.log:*verbosity*` (0 = quiet,
1 = default, 2 = verbose, 3 = debug). At the REPL:

```lisp
(setf ldl.log:*verbosity* 3)
```

This makes `ldl.log:debug*` calls (catalog lookups, and anything else an
executor or provider logs at debug level) print, which is often useful
alongside `:check`-mode dry runs.

---

## 10. A worked example

Say `ldl apply` on some project fails with an `action-conflict` you don't
understand, and you want to see exactly which two definitions are
colliding and why, then decide interactively which one should win.

```lisp
(require :asdf)
(push #P"~/Projects/ldl/" asdf:*central-registry*)
(asdf:load-system :ldl :force t)
(in-package :ldl.core)

(reset-project-registries)
(default-fact-probers)
(discover-plugins)
(discover-project "~/Projects/my-home")
(probe-all-facts)
(apply-profile :work-laptop)

(defparameter *home* (run-current-home-thunk))
(defparameter *all-actions*
  (append (getf *home* :actions)
          (collect-actions-from-features (getf *home* :use-features))))

(dedup-actions *all-actions*)
```

That last call is where it fires. In the SLDB buffer you'll see the
condition's report — the exact identity, and both source labels
(`"provider for feature SHELL"`, `"user"`, or whatever produced each
side) — plus `USE-FIRST`/`USE-SECOND` as real, invokable restarts. Pick
one, and `dedup-actions` returns normally with your choice reflected,
letting you continue driving the rest of the pipeline (`order-actions`,
then `execute-action` in `:check` mode) to confirm the rest of the plan
looks right before ever touching `ldl apply` for real.

If you'd rather see the two colliding actions directly instead of just
their labels, they're right there in `*all-actions*` — filter for the
matching identity:

```lisp
(remove-if-not (lambda (a) (equal (action-identity a) '(:copy-file . "~/.gitconfig")))
                *all-actions*)
```
