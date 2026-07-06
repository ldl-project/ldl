# How to Write an LDL Feature

*A self-contained prompt for a coding LLM with no prior knowledge of LDL.
Paste this whole file as context, followed by what feature to build (e.g.
"write an LDL feature for Docker" or "write an LDL feature for
PostgreSQL"). Everything you need to write a correct, idiomatic feature
is below — you should not need to guess at conventions.*

---

## 0. Your task

You will be asked to write **one LDL feature** as a single, self-contained
Common Lisp file. LDL is a declarative Linux home/system configuration
tool written in Common Lisp (SBCL). A "feature" is a named capability
(`:docker`, `:postgresql`, `:krohnkite`, ...) plus one or more
**providers** that turn it into concrete system actions (install this
package, write that config file, enable this service).

Unless told otherwise, assume your output must:

1. Be **one `.lisp` file** the person can drop into any of LDL's six
   conventional project directories (`features/`, `providers/`,
   `catalogs/`, `templates/`, `hooks/`, `profiles/`) — it doesn't matter
   which one, LDL loads all `.lisp` files in all of them.
2. Work **independently** — no other project file should be required for
   it to resolve and plan correctly. If your feature needs another
   feature to exist first (e.g. a desktop environment), define a minimal
   stub for that dependency in the same file, clearly marked as
   deletable if the person's real project already defines it elsewhere.
3. Be **idempotent** — every action you emit must be safe to apply twice.
4. Be **testable without root and without side effects**, via
   `ldl plan` / `ldl check` / `ldl explain` / `ldl validate`, before
   anyone runs `ldl apply` for real.

Read the rest of this document once, fully, before writing anything.

---

## 1. The mental model

LDL resolves and executes a configuration in five steps, after a
discovery pass:

```
0. Discover  -- load every .lisp file in features/, providers/,
                catalogs/, templates/, hooks/, profiles/, plus home.lisp
1. Probe     -- gather Facts about the machine (os, hostname, ...),
                merge in the selected --profile
2. Resolve   -- walk use-feature calls, pick a Provider for each,
                call each provider with facts, collect every action
3. Dedup     -- resolve identity conflicts between actions
4. Order     -- topologically sort by :depends-on
5. Execute   -- run each action's executor (:apply / :check / :remove)
```

The five concepts you're working with:

- **Fact** — a probed or profile-supplied truth about the machine, read
  with `(fact :key)` inside a home definition, or via the `facts`
  argument plist passed to your provider function.
- **Feature** — a named capability with an optional dependency list
  (`:requires`). Declared with `define-feature`.
- **Provider** — a plain function `(lambda (facts) ...)` that returns a
  list of action plists for a feature. Registered with
  `register-provider`. A feature can have more than one provider (e.g.
  `:bash` and `:zsh` for `:shell`); the person selects one with
  `:via`, or you can mark one `:default t` so `(use-feature :shell)`
  works with no `:via` at all.
- **Catalog** — a translation table from a canonical keyword to a
  distro-specific string, consulted by the `:package` executor. Declared
  with `register-catalog` (see §4 for why not `define-catalog`).
- **Action** — a plist `(:action <type> :target <t> ...opts)`. Each type
  has exactly one built-in executor that is responsible for making the
  system match the action, idempotently, in one step. There's no
  separate "current state" model to diff against — every executor
  checks the real system directly.

A full worked example, at the end of this document (§8), ties all of
this together.

---

## 2. Where your registrations live

Every registration form below is a plain top-level Lisp form. Your file
must start with:

```lisp
(in-package :ldl.core)
```

Everything you write — `define-feature`, `register-provider`,
`register-catalog`, `register-pipeline-hook`, `register-fact-prober` —
is called directly, unqualified, because you're in that package.

Two package-name gotchas if you ever write a *home definition* (a
`home.lisp`, not a feature file) rather than just a feature: `package`
and `directory` are DSL macros that shadow `cl:package` and
`cl:directory` inside `:ldl.core`. You won't hit this writing a feature
file, only if you're also asked to write an example `home.lisp` to go
with it.

---

## 3. Defining the feature

```lisp
(define-feature :docker
  :description "Docker container runtime"   ; documentation only
  :tags (:containers :dev)                   ; documentation only
  :provides (:containers)                    ; documentation only
  :requires nil)                             ; the only field that's load-bearing
```

`:requires` is a list of other feature-name keywords that must resolve
first. If your feature genuinely needs another feature (a desktop
environment, a language runtime, etc.), put its name here — and if that
required feature might not already be defined in the person's project,
define a minimal stub for it in your file too (see the Krohnkite example
in §8 for the pattern: a tiny feature + a tiny default provider, clearly
commented as removable).

`:requires nil` is completely valid if you don't depend on anything.

**Do not** invent conditional syntax or control flow here — `:requires`
is just a literal list.

---

## 4. Registering a provider

```lisp
(register-provider :docker-ce :for :docker
  (lambda (facts)
    (declare (ignore facts))
    (list
      '(:action :package :target :docker-ce :via :system)
      '(:action :service :target :docker :enabled t :running t))))
```

Rules:

- The calling convention is exactly `PROVIDER-NAME :for FEATURE-NAME
  FUNCTION-FORM` — a keyword, then `:for`, then the feature keyword, then
  a lambda (or `#'some-function`) as the last argument.
- The function receives one argument, `facts` — a plist. Read it with
  `(getf facts :some-key)`, **not** `(fact :some-key)` — `fact` only
  works inside a home definition's body, not inside a provider function.
- Return a **list of action plists**. Each action not wrapped in a quote
  needs to be built with `(list ...)`, not written as a bare
  parenthesized literal, because a provider body is ordinary Lisp code
  that gets evaluated — see §5, this is the single most common mistake.
- If your feature only makes sense under certain facts, just return
  `nil` from the provider when they don't hold:

  ```lisp
  (register-provider :nvidia-proprietary :for :nvidia-drivers
    (lambda (facts)
      (when (eq (getf facts :gpu) :nvidia)
        (list '(:action :package :target :nvidia-driver :via :system)))))
  ```

- **Mark a provider `:default t`** if your feature has more than one
  provider and you want `(use-feature :your-feature)` to work with no
  `:via` at all:

  ```lisp
  (register-provider :docker-ce :for :docker :default t
    (lambda (facts) ...))
  (register-provider :podman :for :docker
    (lambda (facts) ...))
  ```

  Without a `:default`, LDL refuses to guess between more than one
  provider and signals a clear error listing every candidate — that's
  correct behavior, not a bug, so don't work around it by silently
  picking one yourself; just mark the sensible one `:default t`.

- **Give it a `:description`.** This is the difference between `ldl
  list`/`ldl explain` showing a bare name and showing something a person
  can actually act on. Always include one:

  ```lisp
  (register-provider :docker-ce :for :docker :default t
    :description "Docker CE from the official upstream repository"
    (lambda (facts) ...))
  ```

  Likewise, always give `define-feature` a `:description` — it shows up
  in the same reports (see §11's checklist).

---

## 5. The single most important rule: literal data vs. evaluated code

This is where almost every mistake happens, so read it twice.

**Inside a provider function**, you are writing ordinary Lisp code that
gets evaluated. If you want an action plist to contain a literal
sub-list — like `:depends-on` — you must **quote it**, or Lisp will try
to *call* its first element as a function:

```lisp
;; WRONG -- (:package :system . :git) is not quoted, so evaluating this
;; list tries to call the keyword :PACKAGE as a function. Signals an error.
(list :action :command :target "clone" :run "..."
      :depends-on ((:package :system . :git)))

;; RIGHT -- quote the depends-on value
(list :action :command :target "clone" :run "..."
      :depends-on '((:package :system . :git)))
```

A plain `'(:action :package :target :docker-ce :via :system)` (the whole
action quoted at once) sidesteps this entirely, and is preferable
whenever every value in the action is a constant. Only switch to `(list
:action ... (format nil ...) ...)` for the specific fields that need a
computed value (a path built from a variable, a fact-derived string,
etc.), and remember to quote any literal sub-list among them (most
commonly `:depends-on`, occasionally `:ensure`/`:remove`/`:set`/`:unset`
if you construct one of those actions directly rather than via a home-level convenience macro).

If you are asked to also write an example **home definition** (a
`home.lisp` or a snippet using `use-feature`, `file`, `package`, etc.),
the rule flips: those convenience macros treat their arguments as
**literal data at macroexpansion time**, never evaluated — that's what
lets `:depends-on ((:package :system . "emacs"))` work directly, unquoted,
inside a `(file ...)` or `(package ...)` form. The one deliberate
exception is `use-feature`'s `:via`, which is evaluated, specifically so
things like `(use-feature :editor :via (if (fact :work-p) :emacs :vim))`
work. You are extremely unlikely to need this distinction for a feature
file — it only matters if you're also handed a home-definition-writing
task.

---

## 6. Catalogs: use `register-catalog`, never `define-catalog`

`define-catalog` **replaces the entire catalog** with whatever you pass
it. If the person's project already has a `:packages` catalog defined
elsewhere (it almost certainly does), and your feature file also calls
`define-catalog :packages ...`, you will silently delete every other
package mapping in their project the moment your file loads, purely
because of file-load order. Never do this in a feature file meant to be
dropped into an existing project.

Instead, always use `register-catalog`, which adds entries without
touching anything else already in the catalog:

```lisp
(register-catalog :packages :docker-ce
  '((:fedora . "docker-ce") (:ubuntu . "docker-ce") (:arch . "docker")))
```

If a distro isn't in your alist, LDL gracefully falls back to the
canonical keyword's own name as a string — so you don't need an entry
for every distro, only the ones that spell it differently.

---

## 7. The complete list of built-in action types

Every action is `(:action <type> :target <value> ...opts)`. `:target`
can usually also be written as `:to` for `:copy-file` specifically
(both work; `:to` is the convention providers in the wild actually use).
Every type below supports `:apply`, `:check`, and `:remove` execution
modes automatically — you never write the executor, only the action
plist, unless you are asked to add a brand-new action type (rare; see
§9 if so).

Generic properties, valid on **any** action:

| Key | Meaning |
|---|---|
| `:depends-on` | list of other actions' identities (§9) that must run first |
| `:force` | wins any identity conflict outright, regardless of priority |
| `:disabled` | marks the action for removal (only acted on if the home has the `:prune-explicitly-disabled` trait) |
| `:owner` / `:group` | for file-related actions; default to the invoking user, never root, even under sudo |
| `:priority` / `:source` | set automatically by the pipeline (`:provider` for provider-authored actions) — don't set these yourself |

Dotfile / package / service actions:

| Type | Keys | Notes |
|---|---|---|
| `:package` | `:target`, `:via` (`:system` default, or `:pip`/`:npm`/`:flatpak`), and for `:flatpak` specifically: `:scope` (`:system` default or `:user`), `:remote` (default `"flathub"`), `:remote-url` (required for any non-flathub remote) | resolved through the `:packages` catalog only when `:via :system` -- `:pip`/`:npm`/`:flatpak` use the target string as-is. For `:flatpak`, give the target as a **string**, not a keyword (app IDs are case-sensitive; the reader would uppercase a keyword). `:scope :user` never requires or uses root privileges, even under `sudo ldl apply`. |
| `:copy-file` | `:target`/`:to`, `:from`, `:template`, `:renderer`, `:secrets`, `:mode` | `:from` resolves under the project's `files/` directory |
| `:ensure-dir` | `:target`, `:mode` | |
| `:symlink` | `:target`, `:to` | `ln -sf` semantics |
| `:service` | `:target`, `:enabled`, `:running` | systemd unit |
| `:timer` | `:target`, `:on-calendar` | systemd timer unit |
| `:env-var` | `:target` (var name), `:value`, `:file` | ensures one `export KEY="value"` line |
| `:config-lines` | `:target`, `:ensure` (list), `:remove` (list) | identity includes content, so repeated calls against the same file are additive, never conflicting |
| `:config-ini` | `:target`, `:section`, `:set` (alist), `:unset` (list) | |
| `:config-env` | `:target`, `:set` (alist) | systemd `environment.d` syntax, no section headers |
| `:secret` | `:target`, `:from` (`:pass`/`:vault`/`:file`/`:prompt`), `:path`, `:message`, `:mode` | value resolved fresh at execution time, never persisted in plaintext elsewhere |

System-administration actions:

| Type | Keys | Notes |
|---|---|---|
| `:user` | `:target` (username), `:uid`, `:gid`, `:shell`, `:home`, `:create-home`, `:system`, `:locked`, `:remove-home` | only touches attributes that actually differ |
| `:group` | `:target` (group name), `:gid` | |
| `:authorized-key` | `:target` (username), `:key`, `:comment` | identity includes the key material — multiple keys per user never collide |
| `:permissions` | `:target` (path), `:owner`, `:group`, `:mode`, `:recursive` | metadata only, never creates the path — use this to fix ownership on something a *package* created |
| `:mount` | `:target` (mountpoint), `:device`, `:fstype`, `:options`, `:dump`, `:pass` | ensures the `/etc/fstab` entry *and* that it's actually mounted |
| `:sysctl` | `:target` (key), `:value`, `:file` (default `/etc/sysctl.d/99-ldl.conf`) | persists *and* applies immediately via `sysctl -w` |
| `:kernel-module` | `:target` (module name), `:state` (`:loaded` or `:blacklisted`) | |
| `:hostname` | `:target` (hostname) | sets both `/etc/hostname` and the running hostname |
| `:locale` | `:target` (locale name), `:timezone` | generates the locale if needed, sets it default, optionally sets timezone |
| `:firewall` | `:target` (port), `:protocol` (default `"tcp"`), `:allow` | auto-detects `firewalld` vs `ufw`; identity includes protocol, so tcp/udp on the same port are independent |
| `:cron` | `:target` (job name), `:schedule`, `:command`, `:user` (default `"root"`) | writes `/etc/cron.d/<target>` |
| `:command` | `:target` (a label), `:run`, `:creates`, `:unless`, `:only-if`, `:remove-run` | the escape hatch — give exactly one of `:creates`/`:unless`/`:only-if` so LDL can actually check whether it's needed; with none given it honestly reports "always needs to run" rather than guessing |

If none of these covers what you need, `:command` with the right
idempotency check (`:creates` a marker file/dir, `:unless`/`:only-if` a
shell probe) covers nearly everything else. Only propose a brand-new
custom action type (via `register-action-type`, §9) if the thing you're
automating genuinely needs its own multi-step check/apply/remove logic
that `:command` can't express in one shell idempotency check — e.g. it
needed several distinct idempotent sub-steps with their own dependency
ordering, which is exactly why Krohnkite (§8) uses three separate
`:command` actions chained by `:depends-on` rather than either one
giant shell one-liner or a whole new action type.

---

## 8. A complete worked example

This is the actual Krohnkite (a KWin tiling script) feature, included
here as a template for structure, not for you to copy verbatim unless
you're specifically asked for Krohnkite. Notice: the catalog uses
`register-catalog`; the required feature (`:kde-plasma`) gets a minimal,
clearly-removable stub; each install step is its own `:command` action
with a real idempotency check and an explicit `:depends-on` on the
previous step's identity; and the quoting rule from §5 is followed
exactly (`:depends-on '((:package :system . :git))`, quoted, inside a
`(list ...)` call).

```lisp
(in-package :ldl.core)

;;; 1. Catalog entries -- additive, never clobbers an existing :packages catalog
(register-catalog :packages :plasma-desktop
  '((:fedora . "plasma-desktop") (:arch . "plasma-meta")
    (:debian . "plasma-desktop") (:ubuntu . "kde-plasma-desktop")))
(register-catalog :packages :git
  '((:fedora . "git") (:arch . "git") (:debian . "git") (:ubuntu . "git")))

;;; 2. Minimal stub for the required feature -- delete if already defined elsewhere
(define-feature :kde-plasma :description "KDE Plasma desktop" :requires nil)
(register-provider :plasma-desktop :for :kde-plasma :default t
  (lambda (facts) (declare (ignore facts))
    (list '(:action :package :target :plasma-desktop :via :system))))

;;; 3. The feature itself
(define-feature :krohnkite
  :description "Krohnkite -- dynamic tiling script for KWin"
  :requires (:kde-plasma))

(register-provider :krohnkite :for :krohnkite :default t
  (lambda (facts)
    (declare (ignore facts))
    (let* ((repo "https://github.com/esjeon/krohnkite.git")
           (clone-dir "~/.cache/ldl/krohnkite")
           (script-dir "~/.local/share/kwin/scripts/krohnkite"))
      (list
        '(:action :package :target :git :via :system)
        (list :action :command
              :target "krohnkite: clone source"
              :run (format nil "git clone --depth 1 ~a ~a" repo clone-dir)
              :creates clone-dir
              :depends-on '((:package :system . :git)))
        (list :action :command
              :target "krohnkite: install kwin script"
              :run (format nil "kpackagetool6 --type KWin/Script -i ~a" clone-dir)
              :creates script-dir
              :depends-on '((:command . "krohnkite: clone source")))))))
```

---

## 9. Action identity and `:depends-on` — get this exact or it silently fails

Every action has an **identity**, computed from its type and target, used
both to detect conflicts (two actions, same identity, different content
= error) and to resolve `:depends-on` edges (which are just a list of
other actions' identities). If you write a `:depends-on` entry that
doesn't *exactly* match the shape LDL actually computes for the target
action, the dependency is silently ignored — not an error, just wrong
ordering. Get these exactly right:

| Action type | Identity shape | Example |
|---|---|---|
| `:package` | `(:package <via> . <target>)` | `(:package :system . :git)` |
| `:config-lines` | `(:config-lines (content) <target>)` | rarely referenced directly by `:depends-on`; prefer depending on something else |
| `:authorized-key` | `(:authorized-key <target> <key>)` | rarely referenced directly |
| `:firewall` | `(:firewall <protocol> . <target>)` | `(:firewall "tcp" . 80)` |
| everything else | `(<type> . <target>)` | `(:command . "krohnkite: clone source")`, `(:ensure-dir . "~/.ssh")`, `(:service . :docker)` |

Note the dot before the last element for the two-element forms — these
are **dotted pairs**, not proper lists. `(:ensure-dir . "~/.ssh")` is
correct; `(:ensure-dir "~/.ssh")` (no dot) is a different, non-matching
piece of data and will not match anything.

When in doubt, depend on the simplest thing available — usually the
`:package` action for whatever you installed just before, or a
`:command`/`:ensure-dir`/`:copy-file` action by its plain target string.

---

## 10. Optional: a pipeline hook

If it genuinely adds value (an audit log line, a warning before
something destructive), you can register one:

```lisp
(register-pipeline-hook :after-resolve
  (lambda (facts actions)
    (declare (ignore facts))
    (when (find "some-target" actions :key (lambda (a) (getf a :target)) :test #'equal)
      (ldl.log:info "Doing the thing."))))
```

`:after-resolve` runs right after every action is collected, before
dedup. `:before-execute` runs after ordering, right before anything
actually happens. Don't reach for this unless it's clearly useful —
most features don't need one.

---

## 11. Testing your feature before you're done

Every one of these should work with **no other project files present**
and **no root privileges**:

```sh
mkdir -p test-project/providers
cp your-feature.lisp test-project/providers/
cat > test-project/home.lisp <<'EOF'
(in-package :ldl.core)
(define-home t1 (use-feature :your-feature))
EOF

ldl validate -C test-project   # syntax only
ldl check    -C test-project   # full resolution, no execution -- catches
                                # missing providers, action conflicts, cycles
ldl plan     -C test-project   # prints the resolved, ordered action list
ldl explain  -C test-project   # same, plus the resolved feature list
```

Confirm:

- `ldl plan` lists every action you expect, in a sane order (packages
  before things that need them, clone before install before enable,
  etc.) — if the order looks wrong, re-check §9.
- `ldl check` reports "Configuration resolves cleanly" with no errors.
- If you used `:via` anywhere or multiple providers, try
  `(use-feature :your-feature)` with no `:via` and confirm it either
  works (because you marked one `:default t`) or fails with a clear,
  expected error listing the candidates.
- Nothing in your provider ever touches the filesystem or shells out
  just from being *loaded* — all system interaction must happen inside
  an action's executor, not at provider-registration time.

---

## 12. Quality checklist

Before handing back your feature file, confirm:

- [ ] Starts with `(in-package :ldl.core)`.
- [ ] Every `define-feature` and `register-provider` has a `:description`
      — it's what `ldl list`/`ldl explain` show instead of a bare name.
- [ ] Every catalog registration uses `register-catalog`, never
      `define-catalog`.
- [ ] Any required-but-possibly-missing feature gets a minimal,
      clearly-commented, removable stub.
- [ ] Every provider is a function of one argument (`facts`), reading
      facts via `(getf facts :key)`, never `(fact :key)`.
- [ ] If more than one provider is registered for a feature, exactly one
      is `:default t`, or you've deliberately decided the person must
      always specify `:via`.
- [ ] Every literal sub-list embedded inside a `(list ...)` call (most
      commonly `:depends-on`) is quoted.
- [ ] Every `:depends-on` entry matches the exact identity shape from
      the table in §9 for the action type it targets.
- [ ] Every action is idempotent — re-running `ldl apply` twice should
      be a no-op the second time. For anything not covered by a built-in
      action, this means giving `:command` a real `:creates`/`:unless`/
      `:only-if` check, not omitting one.
- [ ] You tested with `ldl validate` / `check` / `plan` / `explain`
      standalone, per §11, and the output looks correct.
- [ ] A short header comment explains what the feature does and, if
      it's non-obvious, how to test it standalone.
