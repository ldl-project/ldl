# Getting Started

*Part 1 of 4 in the LDL manual — Getting Started | [How I Work](02-how-i-work.md) | [How I Am Built](03-how-i-am-built.md) | [Reference](04-reference.md)*

*Written by LDL, for you.*

Hello. I'm LDL — Lisp Declarative Linux — and this is the manual I wish
someone had handed you on day one. I'm going to talk to you directly
through this whole manual: when I say "I", I mean the tool you're about
to install; when I say "you", I mean the person about to describe their
Linux home directory to me for the first time.

This part gets you from nothing installed to a real `ldl apply` doing
something on your machine. The other three parts are the mental model,
the internals, and the exhaustive reference — you won't need any of them
to finish this one.

---

## Installing me

You need [SBCL](http://www.sbcl.org/) on your `PATH` — nothing else. I
depend only on `asdf` and `uiop`, both bundled with SBCL, so there's no
Quicklisp step and nothing else to pull down.

From the project root, run `build.sh`:

```sh
./build.sh
```

which does exactly this:

```sh
# Most clean installations or new users do have a local bin.
mkdir -p ~/.local/bin/

# Build ldl and store it there.
sbcl \
  --non-interactive \
  --eval '(require :asdf)' \
  --eval '(push #P"./" asdf:*central-registry*)' \
  --eval '(asdf:load-system :ldl :force t)' \
  --eval '(sb-ext:save-lisp-and-die
             "ldl"
             :executable t
             :toplevel
             (lambda ()
               (ldl.core:main (rest sb-ext:*posix-argv*))))' \
&& ln -sf "$PWD/ldl" ~/.local/bin/ldl

# Show ldl's own help, to confirm it worked.
clear
ldl
```

A minute later you have a real, standalone `ldl` executable — no Lisp
image to keep around, no `asdf:load-system` step at runtime — symlinked
into `~/.local/bin`. If nothing prints when you just type `ldl` in a new
shell, make sure `~/.local/bin` is actually on your `PATH` (most distros
add it by default for a login shell; if yours doesn't, add
`export PATH="$HOME/.local/bin:$PATH"` to your shell's rc file).

Confirm it:

```sh
ldl version
ldl --help
```

---

## Building your first home project

Let's actually do this.

### Step 1 — scaffold

```sh
ldl init -C ~/my-home
```

I'll create:

```
~/my-home/
├── home.lisp
├── profiles/
├── features/
├── providers/
├── catalogs/
├── templates/
├── hooks/
└── files/
```

`home.lisp` starts out about as small as it can be:

```lisp
(define-home my-home
  :traits (:prune-explicitly-disabled))
```

Everything else is empty. That's fine — an empty home is a valid home,
it just doesn't do anything yet.

### Step 2 — decide what "shell" means to you

Say you want me to manage your shell. First, tell me it's a *capability*
that exists, in `features/shell.lisp`:

```lisp
(in-package :ldl.core)

(define-feature :shell
  :description "Login shell and dotfiles"
  :requires nil)
```

Then tell me *how* to provide it, in `providers/shell.lisp` (or in the
same file — I don't care which of the six directories a registration form
lives in, as long as it's one of them):

```lisp
(in-package :ldl.core)

(register-provider :bash :for :shell
  (lambda (facts)
    (declare (ignore facts))
    (list
      '(:action :package :target :bash :via :system)
      '(:action :copy-file :to "~/.bashrc" :from "bashrc"))))
```

Drop your actual `.bashrc` content at `files/bashrc` — this is where
every `:from "..."` path in a convenience form resolves, always relative
to `files/` under your project root, never the project root itself.

### Step 3 — teach me your distro's package names

`:target :bash` above is a canonical name, not necessarily a real package
name. Some distros call it something else. Tell me the mapping in
`catalogs/packages.lisp`:

```lisp
(in-package :ldl.core)

(define-catalog :packages
  (:bash (:fedora . "bash") (:ubuntu . "bash") (:arch . "bash")))
```

If I ever hit a canonical name that isn't in the catalog, I don't fail —
I just fall back to using the keyword's name as-is (`:bash` → `"bash"`),
so starting without a catalog entry for every single package is fine.

### Step 4 — wire it into your home

```lisp
;; home.lisp
(define-home my-home
  :traits (:prune-explicitly-disabled)
  (use-feature :shell))
```

Since there's only one provider registered for `:shell` (`:bash`), I'll
use it automatically. Try it:

```sh
ldl plan -C ~/my-home
```

You should see something like:

```
Resolved plan for MY-HOME:
  PACKAGE bash
  COPY-FILE ~/.bashrc
2 action(s).
```

Nothing has touched your filesystem yet — `plan` always runs in check
mode. When you're happy:

```sh
ldl apply -C ~/my-home
```

Don't put `sudo` in front of that. Every action that genuinely needs
root (installing that `bash` package, for instance) escalates on its own
for just that one step and may prompt you for your password right then —
running the whole thing under `sudo` instead would reset `~` to root's
home directory and isn't needed for anything ldl does.

### Step 5 — add a second machine

Say you also want zsh at work. Add a second provider:

```lisp
;; providers/shell.lisp, appended
(register-provider :zsh :for :shell
  (lambda (facts)
    (declare (ignore facts))
    (list
      '(:action :package :target :zsh :via :system)
      '(:action :copy-file :to "~/.zshrc" :from "zshrc"))))
```

Now there are two providers for `:shell`, so I need you to pick one. Do it
with a Fact instead of hard-coding it:

```lisp
;; profiles/machines.lisp
(define-profile :work    '((:work-p . t)))
(define-profile :personal '((:work-p . nil)))
```

```lisp
;; home.lisp
(use-feature :shell :via (if (fact :work-p) :zsh :bash))
```

```sh
ldl plan -C ~/my-home --profile work      # -> zsh
ldl plan -C ~/my-home --profile personal  # -> bash
```

Same `home.lisp`, different outcome, purely from the Fact.

### Step 6 — check before you trust

Two commands exist specifically so you never have to find out about a
mistake via `apply`:

```sh
ldl validate -C ~/my-home   # are the s-expressions even well-formed?
ldl check    -C ~/my-home --profile work   # does everything actually resolve?
```

`validate` catches unbalanced parens before anything else runs, even if a
plugin fails to load. `check` runs the whole resolution pipeline (steps
0–4) and stops before step 5, so you find out about a missing provider, a
conflicting action, or a dependency cycle without any risk to your system.

That's the whole loop. Everything past this point in the manual is
reference material for when you want to do something more specific:
secrets, templates, removal, cross-action dependencies, pipeline hooks,
and so on.

---


---

Next: [How I Work](02-how-i-work.md) is the mental model behind
everything you just did — read it before you build anything more
complicated than what's above. Or jump straight to the
[Reference](04-reference.md) if you already know roughly what you want.
