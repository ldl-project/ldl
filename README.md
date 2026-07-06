# Lisp Declarative Linux (LDL)

*A Declarative home environment manager for Linux, written in Common Lisp.*

---

## Hey, so — why does this exist?

I kept doing the same thing on every new machine: install the same twenty packages, copy the same dotfiles from somewhere, remember the one `systemctl enable` command I always forget, and then two months later have no idea which of my four laptops has the "real" version of my config.

I looked at the usual answers — a pile of shell scripts, Ansible, Nix — and none of them felt right for what I actually wanted, which was small and boring: *tell the computer what I want, in one place, and have it make that true.* Not a build system. Not a new package format. Not a new operating system philosophy. Just: "I want Emacs, I want my `.gitconfig`, I want this SSH key," and then it happens, on Fedora or Arch or Debian, without me thinking about `dnf` vs `pacman` ever again.

That's LDL. You write down what you want. Someone (maybe you, maybe someone else who's already done the work) has written the Linux-specific knowledge of *how* to get it. You never have to know the difference between `emacs` on Fedora and `emacs-nox` on Ubuntu — the catalog knows that for you.

I'm building it in Common Lisp because I wanted a real, restartable condition system when something goes wrong halfway through (not just a stack trace and a shrug), and because a small, composable Lisp DSL felt like the right size for "declare a home directory," not the size of a general-purpose infrastructure tool.

## Okay, but why not just use Nix or Guix?

Fair question, I asked myself the same thing before starting. Here's the honest answer:

**Nix and Guix are magnificent, and they ask a lot of you.** They replace your package manager, your build model, and often your whole OS with something built around a store of immutable, content-addressed derivations. That buys you incredible reproducibility — and it comes with a real cost: a new language to learn, a new mental model for *everything* (including packages that "just exist" as `/nix/store/hash-name`), and, if you go all the way, a new operating system (NixOS, Guix System) instead of the Fedora or Arch box you already have set up the way you like it.

LDL doesn't try to replace any of that. It's deliberately smaller:

- **Your distro stays your distro.** LDL calls `dnf`, `pacman`, `apt` — whatever you already have — through a provider. It doesn't introduce a parallel package store.
- **No new build model.** There's no derivation graph, no content-addressed store, no rebuild-from-source-by-default philosophy. An "action" in LDL is just "make this one small thing true" — copy a file, install a package, enable a service — and it's idempotent because the action itself is careful, not because there's a hash-addressed universe underneath it.
- **No rollback, on purpose.** Nix's atomic generations are one of its best features, and also part of why it's a big piece of machinery. LDL doesn't attempt that. It applies forward, honestly, and if something's wrong you fix your declaration and run it again. Smaller promise, smaller system.
- **You don't have to leave.** You can adopt LDL for your dotfiles and packages on the distro you already run, this afternoon, without repartitioning anything or learning a new OS.

If you want bit-for-bit reproducible builds and full-system atomic rollbacks, Nix or Guix are the right tool, genuinely — go use them. If you want "describe my home directory once, reuse it across my machines, and stop thinking about which distro I'm on," that's the itch LDL is scratching.

## How LDL stacks up

Every tool on this list is good at what it does. Here's the honest
comparison, not a sales pitch:

|                                    | LDL                                             | Ansible               | Nix + home-manager                         | chezmoi / yadm / dotbot    | Puppet / Chef / Salt          |
|------------------------------------|-------------------------------------------------|-----------------------|--------------------------------------------|----------------------------|-------------------------------|
| **Config language**                | Common Lisp                                     | YAML + Jinja          | Nix (functional)                           | Go templates / YAML / bash | Ruby DSL / YAML+Jinja         |
| **Scope**                          | Home + optional system bits                     | Whole fleets, remote  | Whole system, reproducible                 | Dotfiles only              | Whole fleets, agent/master    |
| **Package installs**               | Catalog-mapped, your existing package manager   | Yes, many modules     | Yes, via the Nix store                     | No                         | Yes, extensive                |
| **Real conditionals/control flow** | Yes — it's Lisp                                 | Limited (Jinja)       | Yes — it's Nix                             | Limited/none               | Limited (ERB/Jinja)           |
| **Rollback**                       | No — converge forward, re-run to fix            | No                    | Yes, atomic                                | N/A                        | Not typically                 |
| **Learning curve**                 | Common Lisp, if you don't know it               | Low                   | Steep — a new package manager and language | Very low                   | Moderate–steep                |
| **Multi-machine orchestration**    | Not its job (single machine, multiple profiles) | Its whole job         | Possible (nixos-rebuild, flakes)           | No                         | Its whole job                 |
| **Dependencies**                   | SBCL only                                       | Python + pip packages | The Nix daemon/store                       | Single binary              | Agent + often a master server |

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

# Most clean installations or new users do not have a local bin.
mkdir -p ~/.local/bin/

# Build ldl and create a symlink to the executable in ~/.local/bin/
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

# Show ldl's own help, to confirm it works.
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
sudo ldl apply -C ~/my-home # execute (packages need root)
```

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
