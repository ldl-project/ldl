# LDL — Lisp Declarative Linux

**Describe the Linux machine you want. Get real Lisp instead of YAML.**

LDL is a declarative configuration tool for your Linux home directory (and,
when you want it, the system underneath) — written entirely in Common
Lisp, running on SBCL, with zero non-standard dependencies. You declare
*what* you want; catalogs translate package names across distros,
providers implement the *how*, and every action LDL takes is idempotent
by construction. Run it again tomorrow, or on a different machine
entirely, and it converges to the same result.

```lisp
(define-home my-home
  :traits (:prune-explicitly-disabled)
  (use-feature :editor :via (if (fact :work-p) :emacs :vim))
  (use-feature :shell  :via (if (eq (fact :display-server) :wayland) :zsh :bash))
  (file "~/.gitconfig" :from "gitconfig")
  (package "nano" :disabled t))
```

No templating language bolted onto YAML. No new package manager to
adopt. Just facts, conditionals, and real Lisp — because it already is
one.

---

## Who this is for

You, if:

- You already think in Lisp, or want an excuse to.
- You're tired of YAML pretending to be a programming language —
  Jinja-in-strings, `{{ }}` everywhere, no real conditionals.
- You manage more than one machine (laptop, desktop, a VPS) and want one
  config that reacts correctly to each, without copy-pasted variants.
- You want package installs, dotfiles, services, users, mounts, and
  kernel parameters under one coherent model, not four different tools
  duct-taped together.
- You want errors that are real Common Lisp conditions with real
  restarts, not a wall of red YAML-linter text.

You're probably not the target audience if you need to orchestrate a
fleet of servers over SSH, or want a mature ecosystem of thousands of
pre-built community modules today — see below.

## How LDL stacks up

Every tool on this list is good at what it does. Here's the honest
comparison, not a sales pitch:

| | LDL | Ansible | Nix + home-manager | chezmoi / yadm / dotbot | Puppet / Chef / Salt |
|---|---|---|---|---|---|
| **Config language** | Common Lisp | YAML + Jinja | Nix (functional) | Go templates / YAML / bash | Ruby DSL / YAML+Jinja |
| **Scope** | Home + optional system bits | Whole fleets, remote | Whole system, reproducible | Dotfiles only | Whole fleets, agent/master |
| **Package installs** | Catalog-mapped, your existing package manager | Yes, many modules | Yes, via the Nix store | No | Yes, extensive |
| **Real conditionals/control flow** | Yes — it's Lisp | Limited (Jinja) | Yes — it's Nix | Limited/none | Limited (ERB/Jinja) |
| **Rollback** | No — converge forward, re-run to fix | No | Yes, atomic | N/A | Not typically |
| **Learning curve** | Common Lisp, if you don't know it | Low | Steep — a new package manager and language | Very low | Moderate–steep |
| **Multi-machine orchestration** | Not its job (single machine, multiple profiles) | Its whole job | Possible (nixos-rebuild, flakes) | No | Its whole job |
| **Dependencies** | SBCL only | Python + pip packages | The Nix daemon/store | Single binary | Agent + often a master server |

If you want reproducible, rollback-capable, whole-OS declarative
management and are willing to adopt Nix as your package manager, **Nix +
home-manager** is more mature at that specific job than LDL is. If you're
managing a fleet of remote servers, **Ansible/Puppet/Chef/Salt** are built
for exactly that and LDL isn't trying to compete there. If all you want
is dotfile syncing, **chezmoi/yadm/dotbot** are simpler, single-purpose
tools that do less and do it with less ceremony.

LDL's niche is narrower and specific: one machine (or a few, via
Profiles), your existing distro's package manager, real Lisp instead of
templated YAML, and a feature/provider/catalog model that treats
"install Docker" and "write my `.gitconfig`" as the same kind of thing —
an idempotent action — rather than two different tools' worth of syntax.

---

## Installing

You need [SBCL](http://www.sbcl.org/) on your `PATH`. That's the entire
dependency list — LDL depends only on `asdf` and `uiop`, both bundled
with SBCL, so there's no Quicklisp step.

```sh
./build.sh
```

This builds a standalone `ldl` executable (no Lisp image or ASDF load
step at runtime) and symlinks it into `~/.local/bin`:

```sh
#!/usr/bin/env bash
set -euo pipefail

# Most clean installations or new users do have a local bin.
mkdir -p ~/.local/bin/

# Build ldl and store it here.
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

If `~/.local/bin` isn't already on your `PATH`, add
`export PATH="$HOME/.local/bin:$PATH"` to your shell's rc file.

## Quick start

```sh
ldl init -C ~/my-home       # scaffold profiles/ features/ providers/ catalogs/
                             #   templates/ hooks/ files/ home.lisp
# ...edit ~/my-home/home.lisp and friends...
ldl validate -C ~/my-home   # syntax check only
ldl check -C ~/my-home      # full resolution, no execution
ldl plan -C ~/my-home       # show the resolved, ordered action list
ldl diff -C ~/my-home       # show what would change
ldl apply -C ~/my-home      # execute -- never run this with sudo yourself
```

Never run `ldl` itself as root. Every action that genuinely needs
privilege (installing a package, writing a root-owned system file,
creating a system user) escalates on its own, per action, via `sudo` —
you may see a `sudo` password prompt partway through `apply`, but only
for the specific steps that actually need it. Running `sudo ldl apply`
instead breaks `~` expansion (sudo resets `$HOME` to root's) and is never
necessary.

Every built-in action supports `:apply`, `:check`, and `:remove` modes,
and is idempotent — running `apply` twice is always safe, and `plan`
never touches your system.

## Documentation

Start here, in order:

1. **[Getting Started](docs/01-getting-started.md)** — install, then build
   your first home project step by step.
2. **[How I Work](docs/02-how-i-work.md)** — the mental model: Facts,
   Profiles, Features, Providers, Catalogs, Actions, and the five-step
   pipeline. Read this before anything more complex than the quick start.
3. **[How I Am Built](docs/03-how-i-am-built.md)** — LDL's own internals,
   for when you want to extend it rather than just use it.
4. **[Reference](docs/04-reference.md)** — every keyword, every action
   type, every CLI command and option, with a runnable snippet each.

Plus two task-focused guides:

- **[docs/how-to-feature.md](docs/how-to-feature.md)** — a self-contained
  prompt for writing a new LDL feature (built-in package installs,
  services, users, mounts, and more), usable even by a coding LLM with no
  prior LDL knowledge.
- **[docs/how-to-debug.md](docs/how-to-debug.md)** — debugging LDL or a
  home project from a live SBCL REPL (Emacs + SLIME/SLY, or Lem),
  including how to invoke LDL's real, named condition-system restarts
  interactively.

And the formal language specification: **[docs/specification.md](docs/specification.md)**.

## Requirements

- SBCL, and nothing else to build or run LDL itself.
- Some built-in actions shell out to standard Linux tools that must be on
  `PATH` for the actions that use them: `dnf`/`apt-get`/`pacman`
  (whichever matches your distro), `flatpak`, `systemctl`, `chmod`/
  `chown`, `useradd`/`usermod`/`groupadd`, `firewall-cmd`/`ufw`, and
  (optionally) `pass`/`vault` for secrets.

## Project layout

```
ldl/
├── build.sh                # Builds the standalone executable (see Installing)
├── ldl.asd                 # ASDF system definition
├── src/                     # The engine, DSL, and CLI -- see docs/03-how-i-am-built.md
│   ├── action-types/         # One file per built-in action (22 of them)
│   └── ...
└── docs/                     # This README's linked manual, guides, and spec
```

See **[docs/03-how-i-am-built.md](docs/03-how-i-am-built.md)** for the
full annotated layout and the registries/extension points behind it.

## License

MIT (see `LICENSE`).
