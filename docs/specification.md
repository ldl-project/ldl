# Declarative Linux Home Environment Definition Language Specification (v4.3)

## Why This Specification Exists

This specification defines the language and architecture for Lisp Declarative Linux (LDL), a tool that lets users describe their Linux home environment as structured intent rather than imperative commands.

Without this specification, users must manually track dotfiles, understand distribution-specific package names, and remember the exact commands to enable services.

With this specification, users declare what they want their home environment to contain. Feature authors encode Linux and Common Lisp knowledge so users don't have to. Catalogs handle distribution variations. LDL resolves the user's declarations into a flat, ordered list of actions and executes them.

---

## Design Principles

1. **Users declare intent, authors encode knowledge.** A user writes `(use-feature :emacs)`. An author knows that means installing a package, creating directories, placing configuration files, and enabling a service.
2. **Actions are idempotent by construction.** Every built-in action type (`:package`, `:copy-file`, `:symlink`, `:service`, ...) is implemented so that running it twice produces the same result as running it once. LDL does not maintain a separate state model to diff against — idempotency lives in the action executors themselves.
3. **No DSL variables.** Users never bind or read variables in the configuration language. Machine-to-machine differences are handled entirely through auto-probed **Facts**, optionally overridden by a named **Profile** selected on the command line.
4. **Standard Lisp conditionals over facts, no custom conditional keywords.** Users may use any standard Common Lisp conditional and predicate form over facts — `when`, `unless`, `if`, `cond`, `and`, `or`, and standard predicates such as `eq`, `member`, `not`. No custom conditional macros are introduced, and no user-defined control flow, loops, or variable binding are part of the language. This keeps the parser clean and the cognitive load low without contradicting itself when facts need to be combined into a richer condition (e.g. selecting a provider).
5. **Explicit deletion is opt-in.** LDL does not remove anything the user hasn't explicitly marked for removal.
6. **User owns the state.** If a user manually edits a file managed by LDL, re-running LDL will overwrite those manual changes. It is the user's responsibility to update their LDL configuration to reflect desired manual tweaks.
7. **No post-apply verification, no automatic retry, no rollback.** LDL does not attempt to guarantee a 100% verified installation after applying, does not retry failed actions automatically, and does not support rollback. If an action fails during execution, LDL uses the Common Lisp Condition System to report the failure and offer restarts (retry/skip/abort). Users re-run LDL to converge toward the desired state.
8. **Extensions never modify core.** New features, providers, catalogs, action types, and pipeline hooks are discovered automatically — third-party plugins via standard ASDF conventions, project-local files via directory convention — and registered into the core at load time. No hand-written `load` lists are required in either case.
9. **Flat over hierarchical.** There is one dependency graph (features) and one ordered list (actions). There is no separate compiler pipeline, no intermediate resource graph, and no distinct diff/compare/materialize stages.
10. **Mutable distributions only.** LDL targets mutable Linux distributions (Fedora, Arch, Debian, Ubuntu, etc.) exclusively. Support for immutable/declarative-OS distributions (NixOS, Fedora Silverblue, etc.) is explicitly out of scope — not a current feature and not a planned future extension. Distribution agnosticism means portability across mutable distros via Catalogs, not portability across mutability models.

---

## Core Concepts

```
User Declaration  →  Facts  →  Features  →  Providers  →  Actions (ordered, deduped)
      │                │           │            │               │
  "I want            Auto-      Capability   Plain functions   Flat list,
   Emacs"            probed +   graph node   returning         executed
                     profile                 action plists     in order
```

**Facts** are immutable truths about the environment, probed automatically (e.g. `:os`, `:gpu`, `:laptop-p`, `:display-server`), optionally overridden by a selected Profile.

**Features** are named capabilities with dependency relationships. They form an abstract Directed Acyclic Graph (DAG) that LDL walks to resolve what's needed.

**Providers** are plain functions that map a feature to a list of concrete actions. A provider can return a fixed list or compute one based on facts — there is no separate "static" versus "dynamic" declaration form; both are just functions. Providers are pure functions and thus easily unit-testable by authors.

**Catalogs** are translation tables that map canonical identifiers to distribution-specific strings, consulted by action executors (chiefly `:package`) at execution time.

**Actions** are the atomic units of desired state — a file to place, a package to install, a service to enable. Each action has a type, a target, an identity, and a single built-in executor responsible for making the system match it, idempotently.

---

## The Home Definition

The root of any LDL configuration is a home definition. Exactly one `define-home` form is allowed per project:

```lisp
(define-home my-home
  :traits (:prune-explicitly-disabled)

  ;; Capabilities
  (use-feature :development)
  (use-feature :browser)

  ;; Standard CL conditional over a Fact
  (when (fact :laptop-p)
    (use-feature :battery-management))

  ;; Simple file drops for dotfiles
  (file "~/.gitconfig" :from "gitconfig")

  ;; Secrets
  (secret "~/.ssh/id_ed25519" :from :pass :path "ssh/id_ed25519")

  ;; Explicit removal
  (package "vim" :disabled t))
```

This is the entire user-facing surface of the language: `use-feature`, the home-level convenience forms (`file`, `directory`, `symlink`, `package`, `secret`, `env-var`, `config-lines`, `config-ini`, `config-env`), standard Lisp conditionals over facts, and `direct-action` as an escape hatch for anything uncovered. There are no user-defined variables and no scoped configuration blocks attached to `use-feature`.

### Traits

Traits are global policies that affect how the entire home is managed. LDL ships with one built-in trait:

```lisp
(define-home my-home
  :traits (:prune-explicitly-disabled))   ;; remove actions marked :disabled t
```

Authors may register additional traits via ASDF plugins. Traits are simple flags consulted by providers and by the core removal step — they do not introduce a compiler stage of their own.

### Home Syntax

The home definition uses convenience forms designed for users. Raw action specifications are not available at the home level. For anything not covered by a feature or a convenience form, use the escape hatch:

```lisp
(define-home my-home
  (direct-action
    :reason "No provider exists for :proprietary-tool and I need it tomorrow"
    (:action :package :target "proprietary-tool" :version "1.2.3")))
```

---

## Facts and Profiles

### Facts

Facts are auto-probed system context (e.g. `{:os :fedora, :gpu :nvidia, :laptop-p t}`). They are read with `(fact :key)`. Users rarely need to think about how facts are gathered — they simply react to them with standard Lisp conditionals.

#### Fact Prober Registration

Plugins register fact probers to extend the set of auto-probed facts:

```lisp
(ldl.core:register-fact-prober :gpu
  (lambda ()
    (cond
      ((probe-file "/proc/driver/nvidia/version") :nvidia)
      ((probe-file "/sys/class/drm/card0/device/vendor")
       (let ((vendor (read-vendor-file)))
         (cond ((= vendor #x10de) :nvidia)
               ((= vendor #x1002) :amd)
               (t :unknown))))
      (t :unknown))))
```

Fact probers are called once at startup. **If more than one prober is registered for the same fact key, LDL signals a `fact-prober-conflict` condition and aborts startup** — there is no implicit "first one wins" resolution, since that would depend on fragile ASDF load order. Authors resolve the conflict by ensuring only one plugin registers a given fact key, or by having one plugin depend on and defer to another.

### Profiles

A profile is a named set of fact overrides, used to adapt a single home definition to multiple machines without introducing any variables into the DSL. Profiles cannot extend other profiles — each profile is a complete, independent set of overrides:

```lisp
(define-profile :laptop
  '((:hostname . "thinkpad") (:gpu . :nvidia) (:laptop-p . t)))

(define-profile :desktop
  '((:hostname . "tower") (:gpu . :amd) (:laptop-p . nil)))
```

Selected on the command line:

```sh
ldl apply --profile laptop
```

At startup, LDL probes facts and then merges the selected profile's overrides on top of them. The home definition only ever reads `(fact :key)` — it has no way to distinguish a probed value from a profile-supplied one, and no separate parameter-binding syntax exists.

### Catalogs

Catalogs translate canonical keywords into distribution-specific strings so providers and users remain distro-agnostic:

```lisp
(define-catalog :packages
  (:make  (:fedora . "make") (:void . "gnu-make"))
  (:emacs (:fedora . "emacs") (:ubuntu . "emacs-nox")))
```

If a keyword isn't in the catalog, LDL gracefully falls back to the keyword's symbol name as a string (e.g. `:make` → `"make"`).

---

## Features and Providers

### Features

Features are abstract capabilities forming a DAG. They may include a description for documentation and tags for organization:

```lisp
(define-feature :development
  :description "Core development tools: compilers, debuggers, version control"
  :tags (:dev :core)
  :provides (:compilers :version-control)
  :requires (:editor))
```

Feature dependencies (`:requires`) also serve to express plugin interdependencies. When an author writes a provider for a feature that depends on another feature, LDL ensures the dependency is resolved first.

### Providers

A provider is a plain function from facts to a list of action plists. Providers are pure functions and thus easily unit-testable by authors:

```lisp
;; Fixed list of actions
(register-provider :emacs :for :editor
  (lambda (facts)
    (list
      '(:action :package :target :emacs :via :system)
      '(:action :ensure-dir :target "~/.config/emacs/" :mode #o755)
      '(:action :copy-file :from "emacs/init.el" :to "~/.config/emacs/init.el"))))

;; Actions computed from facts
(register-provider :lsp-auto-install :for :language-support
  (lambda (facts)
    (mapcar (lambda (lang)
              (list :action :package
                    :target (format nil "~a-lsp" lang) :via :system))
            (fact :languages))))
```

A feature may have multiple registered providers. The user selects one with `(use-feature :editor :via :emacs)`; if only one provider is registered for a feature, LDL uses it automatically.

#### Conditional Provider Selection

The `:via` parameter accepts a form evaluated at resolve time. Per Design Principle 4, this form is limited to standard Lisp conditionals and predicates over facts:

```lisp
(use-feature :editor :via (if (fact :laptop-p) :emacs :vim))

(use-feature :editor
  :via (cond
         ((and (fact :work-p) (fact :laptop-p)) :emacs)
         ((fact :work-p) :vscode)
         (t :vim)))
```

This allows users to select different providers for the same feature without requiring authors to create "router" providers, while staying within the same conditional vocabulary allowed elsewhere in the home definition.

---

## Actions

Actions are the atomic units of desired state. Each is a plist of the form `(:action <type> :target <t> ...opts)`. Every action type has exactly one built-in executor responsible for probing and correcting system state in a single idempotent step — there is no separate "current state" representation to compute and compare against.

### Execution Mode

Executors receive a `:mode` parameter that determines their behavior:

- **`:apply`** — Actually make changes to the system
- **`:check`** — Report what would change without making changes (used by `plan`, `check`, `diff`, and `--dry-run`)

```lisp
(defun execute-action (action &key (mode :apply))
  (let ((executor (find-executor (getf action :action))))
    (funcall executor action :mode mode)))
```

All built-in executors must support both modes.

### Identity

Every action has a canonical identity derived from its type and its primary target. Some action types include a qualifier in their identity to distinguish actions that affect the same target through different mechanisms:

```lisp
;; Two-element identities (no qualifier)
(:copy-file . "~/.gitconfig")
(:ensure-dir . "~/.config/emacs/")
(:config-lines . "~/.config/i3/config")

;; Three-element identities (with qualifier)
;; Package identities include :via because :package :emacs :via :pip
;; and :package :emacs :via :system are different actions
(:package :system . :emacs)
(:package :pip . :emacs)
```

### Ordering

Action order is primarily declaration order, refined by explicit `:depends-on` edges:

```lisp
(file "~/.config/starship.toml"
      :from "starship.toml"
      :depends-on ((:package :system . "starship")))
```

LDL performs a single topological pass over these edges to produce the final execution order, checking for cycles and missing dependencies as it goes.

### Deduplication and Conflict Semantics

If multiple actions share the same identity, LDL resolves them by priority:

1. **User-level declarations** (highest priority — `file`, `package`, etc. written directly in `define-home`)
2. **Provider-level actions**

Lower-priority definitions are silently dropped. If two actions of the *same* priority define the same identity with *different* content, LDL signals an `action-conflict` condition rather than attempting to merge them.

An action may force a win regardless of priority:

```lisp
(file "~/.gitconfig" :from "gitconfig" :force t)
```

#### Config-Lines Identity

For `:config-lines` actions, the identity includes the specific content being ensured or removed. This means multiple `:config-lines` actions for the same file do not conflict — they are treated as independent, additive operations:

```lisp
;; These are DIFFERENT identities (no conflict):
(:config-lines (:ensure "bindsym $mod+Return exec emacs") . "~/.config/sway/config")
(:config-lines (:ensure "include ~/.config/sway/local.d/*") . "~/.config/sway/config")

;; These are the SAME identity (would conflict if same priority):
(:config-lines (:ensure "bindsym $mod+Return exec emacs") . "~/.config/sway/config")
(:config-lines (:ensure "bindsym $mod+Return exec emacs") . "~/.config/sway/config")
```

If duplicate `:config-lines` identities are detected at the same priority level, LDL logs a warning and continues execution.

### Generic Action Properties

- **`:depends-on`** — explicitly declares dependencies on other actions.
- **`:force`** — if `t`, this action wins any identity conflict outright.
- **`:disabled`** — marks the action for explicit removal (subject to the `:prune-explicitly-disabled` trait).
- **`:owner`** — file owner (username or UID) for file-related actions. **Defaults to the calling user** (the user invoking `ldl`, not `root`, even when `ldl apply` is run via `sudo`) if omitted.
- **`:group`** — file group (group name or GID) for file-related actions. **Defaults to the calling user's primary group** if omitted.

Actions targeting system paths that require a different owner (e.g. `root`) must set `:owner`/`:group` explicitly, as shown in the NVIDIA Xorg config example later in this document.

### Built-in Action Types

```lisp
(:action :package     :target :emacs :via :system)     ; or :via :pip, :npm, etc.
(:action :ensure-dir   :target "~/.config/emacs/" :mode #o755 :owner "user" :group "user")
(:action :copy-file    :from "emacs/init.el" :to "~/.config/emacs/init.el"
                      :mode #o644 :owner "user" :group "user")
(:action :symlink      :target "~/.emacs.d" :to "~/.config/emacs")
(:action :service      :target :ssh-daemon :enabled t :running t)
(:action :timer        :target "backup-daily" :on-calendar "daily" :unit "backup.service")
(:action :env-var      :target "EDITOR" :value "emacs" :file "~/.profile")
(:action :config-lines :target "~/.config/i3/config"
                        :ensure ("bindsym $mod+Return exec emacs")
                        :remove ("bindsym $mod+Return exec i3-sensible-terminal"))
(:action :config-ini   :target "~/.config/fontconfig/fonts.conf"
                        :section "antialias"
                        :set (("enable" . "true"))
                        :unset ("rgba"))
(:action :config-env   :target "~/.config/environment.d/wayland.conf"
                        :set (("MOZ_ENABLE_WAYLAND" . "1")))
(:action :secret       :target "~/.ssh/id_ed25519" :from :pass :path "ssh/id_ed25519"
                        :mode #o600 :owner "user" :group "user")
```

Each executor is responsible for its own idempotency:

- **`:package`** — resolves the target through the catalog for the current distro, checks whether it's already installed, and installs only if needed. In `:check` mode, reports whether installation is needed. Note: installing packages generally requires elevated permissions. If `ldl apply` includes any `:package` action and the process does not have sufficient privileges to install packages, LDL fails fast before executing any actions, with a clear message (see Condition System Integration).
- **`:copy-file` / `:config-lines` / `:config-ini` / `:config-env`** — compare intended content against what's on disk and write only if different. In `:check` mode, report differences.
- **`:symlink`** — applies `ln -sf` semantics. In `:check` mode, reports if symlink target differs.
- **`:service`** — enables/starts only if not already in the desired state. In `:check` mode, reports current vs desired state.
- **`:ensure-dir`** — creates the directory and sets its mode/ownership only if needed. In `:check` mode, reports if creation or mode change is needed.
- **`:timer`** — creates and enables the timer unit only if needed. In `:check` mode, reports current vs desired state.

Authors register new action types the same way they register providers — a keyword plus an executor function, discovered via ASDF. There is no fixed enum to extend in core.

### Home-Level Convenience Forms

`file`, `directory`, `symlink`, `package`, `secret`, `env-var`, `config-lines`, `config-ini`, and `config-env` are thin macros over the corresponding `:action` plist, usable directly inside `define-home`:

```lisp
(file "~/.gitconfig" :from "gitconfig")
;; expands to
(:action :copy-file :to "~/.gitconfig" :from "gitconfig")
```

### Removal

```lisp
(package "vim" :disabled t)
```

Under the `:prune-explicitly-disabled` trait, the executor for that identity is invoked in "remove" mode instead of "apply" mode. Remove semantics per action type:

| Action Type | Remove Behavior |
|-------------|-----------------|
| `:package` | Uninstall the package |
| `:copy-file` | Delete the file |
| `:symlink` | Delete the symlink |
| `:ensure-dir` | Remove directory recursively |
| `:service` | Disable and stop the service |
| `:timer` | Disable and stop the timer |
| `:env-var` | Remove the line from the target file |
| `:config-lines` | Remove the ensured lines, add back the removed lines |
| `:config-ini` | Unset the set keys, set back the unset keys |
| `:config-env` | Remove the set keys from the target file |
| `:secret` | Delete the secret file |

---

## Secrets

Secrets are first-class action data. Source types include `:pass`, `:vault`, `:prompt`, and `:file`.

### Prompt Source

When using `:from :prompt`, LDL reads a single line from `*terminal-io*` using `read-line`. An optional `:message` provides a prompt string:

```lisp
(secret "~/.config/app/token" :from :prompt :message "Enter API token: ")
```

If LDL detects that it is running in a non-interactive context (no attached terminal, e.g. inside CI or a scripted invocation) and encounters a `:prompt` secret, it signals a `non-interactive-prompt` condition rather than blocking indefinitely on `read-line`:

```text
Error: Cannot prompt for secret ~/.config/app/token — no interactive terminal available.
Restarts:
  0. [SUPPLY-VALUE] Provide the value programmatically for this run
  1. [SKIP] Skip this action and continue
  2. [ABORT] Stop processing
```

Templates receive secrets as keyword arguments alongside facts:

```lisp
(file "~/.config/gh/hosts.yml"
      :from "gh-hosts.tmpl"
      :secrets ((:token :from :pass :path "github/token")))

(defun render-gh-hosts (facts &key token)
  (format nil "host: ~a~%token: ~a" (fact :hostname) token))
```

Secret values are resolved at execution time, immediately before the action that needs them runs, and are never written to any intermediate plan file in plaintext.

---

## Template System

Templates are pure Common Lisp functions. They receive facts and secrets, and return a string.

### Template Discovery

Templates are associated with files using the `:template` flag or an explicit `:renderer` function:

```lisp
;; By convention: files ending in .tmpl are templates with a renderer
;; found by converting the filename to a symbol
;; "gitconfig.tmpl" -> (find-symbol "RENDER-GITCONFIG" :ldl-templates)

(file "~/.gitconfig" :from "gitconfig.tmpl" :template t)

;; Explicit renderer function
(file "~/.gitconfig" :from "gitconfig.tmpl" :renderer #'render-gitconfig)
```

When `:template t` is specified, LDL looks for a renderer function named by converting the base filename to a symbol (e.g., `gitconfig.tmpl` → `render-gitconfig`) in the `:ldl-templates` package. If not found, LDL signals a `missing-template-renderer` condition.

Template renderer function signature:

```lisp
(defun render-gitconfig (facts &key user-name user-email)
  (format nil "[user]
    name = ~a
    email = ~a
    hostname = ~a"
          user-name user-email (fact :hostname)))
```

---

## Execution Model

LDL resolves and executes a home definition in five steps, preceded by discovery:

0. **Discover** third-party `ldl-*` plugins (ASDF convention) and project-local files (directory convention), loading all of them into the global registries. See Discovery.
1. **Probe facts**, then merge in the selected profile's overrides, if any.
2. **Walk the feature graph** starting from each `use-feature` form, recursively resolving `:requires`, and call each selected provider `(funcall provider facts)` to collect its actions. Evaluate any `:via` forms at this point. Collect user-level `file`/`package`/`secret`/... forms directly.
3. **Deduplicate** actions by identity — user-level declarations beat provider-level actions, `:force` wins ties, and same-priority conflicts signal `action-conflict`. For `:config-lines`, warn on duplicates but continue.
4. **Order** the surviving actions topologically, using explicit `:depends-on` edges.
5. **Execute** each action's built-in executor in order, passing the appropriate mode (`:apply` for `ldl apply`, `:check` for `ldl plan`/`ldl check`/`ldl diff`/`--dry-run`). Before this step runs under `:apply` mode, LDL performs a privilege preflight: if the ordered action list contains any `:package` action and the process lacks the privileges to install packages, LDL aborts immediately with a clear error, before any action executes.

If an executor signals an error (e.g. a package repository is down, or a file write fails), LDL does not attempt to verify or retry automatically. It immediately signals a condition via the Common Lisp Condition System, offering the user standard restarts. There is no rollback mechanism — users re-run LDL to converge toward the desired state.

### Pipeline Hooks (Extensibility)

While the five-step pipeline itself is fixed and not user-facing, authors may register hooks at two points without modifying core, satisfying the future-readiness goal for adding cross-cutting behavior (e.g. a security lint, a pre-apply confirmation prompt, audit logging) without a full custom pipeline:

```lisp
(ldl.core:register-pipeline-hook :after-resolve
  (lambda (facts actions)
    "Called after step 2, with the full unordered action list, before deduplication."
    (check-actions-for-known-issues actions)))

(ldl.core:register-pipeline-hook :before-execute
  (lambda (facts ordered-actions)
    "Called after step 4, with the final deduplicated, ordered action list, before execution begins."
    (confirm-destructive-actions ordered-actions)))
```

Multiple hooks may be registered at the same point; they run in registration order. A hook may signal a condition to halt the pipeline (using the standard Condition System restarts of retry/skip/abort), but hooks do not have the ability to alter core pipeline behavior beyond that — they observe and may object, they do not rewrite the action list or reorder execution.

### Testing with `:check` Mode

`:check` mode is the primary seam for testing action executors without touching the real filesystem or system state. Because every built-in executor is required to support `:check` mode and to report what it *would* do rather than doing it, authors can write FiveAM (or Parachute) tests that invoke an executor in `:check` mode against fixture facts and assert on the reported plan, without any side effects:

```lisp
(deftest test-copy-file-executor-detects-change
  (let* ((action '(:action :copy-file :from "gitconfig" :to "/tmp/fixture/.gitconfig"))
         (result (execute-action action :mode :check)))
    (is (eq (getf result :status) :would-change))))
```

Providers, being pure functions of facts, need no special mode to test — they can be called directly with fixture fact plists and their returned action lists asserted on. Action executors, which perform I/O, should be tested primarily through `:check` mode; `:apply` mode execution against a real or containerized filesystem is reserved for integration tests, not unit tests.

---

## Logging

LDL provides configurable logging output controlled by CLI flags:

```sh
ldl apply               # default: progress indicators and errors
ldl apply -v            # verbose: show each action being processed
ldl apply -vv           # debug: show internal details (catalog lookups, etc.)
ldl apply --quiet       # errors only
```

Authors may use the logging facility in providers and action executors:

```lisp
(ldl.log:info "Installing package ~a" package-name)
(ldl.log:debug "Catalog lookup: ~a -> ~a" canonical distro-name)
(ldl.log:warn "Package ~a not in catalog, using fallback name" package-name)
```

---

## Condition System Integration

LDL uses the CL condition system for all error handling.

### Missing Provider
```text
Error: No provider found for feature :EDITOR.
Restarts:
  0. [SPECIFY-PROVIDER] Manually select a provider
  1. [SKIP-FEATURE] Continue without this feature
  2. [ABORT] Stop processing
```

### Action Conflict
```text
Error: Conflicting definitions for (:copy-file . "~/.gitconfig")
  Definition A: provider :git-defaults
  Definition B: provider :dotfiles-extra
Restarts:
  0. [USE-FIRST] Keep definition A
  1. [USE-SECOND] Keep definition B
  2. [ABORT] Stop processing
```

### Insufficient Privileges (Preflight)
Signaled before any action executes, if the resolved plan contains package installs and the process lacks the privileges to perform them:
```text
Error: This plan requires installing packages, but ldl is not running with
sufficient privileges to do so.

  Affected actions: 4 :PACKAGE actions

Run again with: sudo ldl apply

Restarts:
  0. [ABORT] Stop processing
```

### Permission Denied (Package Installation, Mid-Run)
In the rarer case a privilege change occurs mid-run after the preflight check passed (e.g. sudo credentials expire):
```text
Error: Permission denied while executing :PACKAGE "emacs".
  Action required: Install package.

Restarts:
  0. [RETRY-WITH-SUDO] Re-invoke with elevated privileges
  1. [SKIP] Skip this action and continue
  2. [ABORT] Stop processing
```

### Non-Interactive Prompt
```text
Error: Cannot prompt for secret ~/.config/app/token — no interactive terminal available.
Restarts:
  0. [SUPPLY-VALUE] Provide the value programmatically for this run
  1. [SKIP] Skip this action and continue
  2. [ABORT] Stop processing
```

### Fact Prober Conflict
Signaled at startup if more than one plugin registers a prober for the same fact key:
```text
Error: Multiple fact probers registered for :GPU.
  Registered by: LDL-PROVIDER-NVIDIA, LDL-PROVIDER-AMD-DETECT

LDL cannot determine which prober's result to trust and will not guess.
Restarts:
  0. [ABORT] Stop processing
```

### Missing Template Renderer
```text
Error: No renderer found for template "gitconfig.tmpl"
  Expected: RENDER-GITCONFIG in :LDL-TEMPLATES
Restarts:
  0. [SPECIFY-RENDERER] Provide a renderer function
  1. [TREAT-AS-STATIC] Copy file contents without rendering
  2. [SKIP] Skip this action and continue
  3. [ABORT] Stop processing
```

### Execution Failure (General)
```text
Error: Failed to execute :COPY-FILE ~/.config/emacs/init.el
  Error: Filesystem read-only

Restarts:
  0. [RETRY] Try again
  1. [SKIP] Skip this action and continue
  2. [ABORT] Stop processing
```

---

## Discovery

Before facts are probed or any configuration is resolved (i.e. before Execution Model step 1), LDL performs two independent, automatic discovery steps: loading a user's own project files by **directory convention**, and loading third-party plugins by **ASDF convention**. Neither requires a hand-written list of files to load — dropping a new file in the right place is sufficient for LDL to pick it up on the next invocation, satisfying the auto-discovery requirement for both a project author and a plugin author.

Both mechanisms register into the same global registries (`register-provider`, `register-feature`, `register-fact-prober`, `register-pipeline-hook`, ...), so the conflict rules described elsewhere in this specification (e.g. `action-conflict`, `fact-prober-conflict`) apply uniformly regardless of whether the conflicting registration came from a project-local file or a third-party plugin.

### Project-Local File Discovery (Directory Convention)

LDL recognizes a fixed set of conventional subdirectories under the project root (`-C`, default `.`) and automatically loads every `.lisp` file found in them, recursively, before resolving the home definition:

```text
project-root/
├── home.lisp        # Always loaded explicitly, last. Contains define-home
│                     # and, if not placed under profiles/, define-profile forms.
├── profiles/*.lisp   # Auto-loaded. define-profile forms.
├── features/*.lisp   # Auto-loaded. define-feature forms.
├── providers/*.lisp  # Auto-loaded. register-provider forms.
├── catalogs/*.lisp   # Auto-loaded. define-catalog forms.
├── templates/*.lisp  # Auto-loaded. Template renderer defuns.
├── hooks/*.lisp       # Auto-loaded. register-pipeline-hook forms.
└── files/            # NOT loaded as Lisp. Static assets referenced by :from.
```

Discovery rules:

- Any of the six conventional directories (`profiles/`, `features/`, `providers/`, `catalogs/`, `templates/`, `hooks/`) may be absent; an absent directory contributes nothing and is not an error.
- Files within each directory are loaded in alphabetical path order. This gives authors a predictable, low-ceremony way to sequence registrations within a single directory via filename, without introducing an explicit dependency-declaration mechanism for project-local files.
- There is no required ordering *between* the six directories — `define-feature`, `register-provider`, `define-catalog`, `register-fact-prober`, and `register-pipeline-hook` are all pure registration calls with no ordering requirement among themselves, since resolution against the feature graph happens later, at `use-feature` walk time (Execution Model step 2).
- `home.lisp` is always loaded explicitly, after all six conventional directories, since it is the one file expected to reference what the others registered (via `use-feature`, `file`, `package`, etc.).
- New files require no registration step, index file, or explicit `load` form — dropping a `.lisp` file into `features/`, `providers/`, `catalogs/`, `templates/`, `hooks/`, or `profiles/` is sufficient for it to be discovered on the next `ldl` invocation.
- `files/` is never loaded as Lisp; it holds static assets referenced by convenience forms' `:from` argument (e.g. `(file "~/.gitconfig" :from "gitconfig")` resolves to `files/gitconfig`).
- The `tests/` directory, if present, is **not** part of discovery — it is a normal ASDF test system, run explicitly via the project's own test tooling (e.g. `(asdf:test-system :my-home)`), not loaded automatically by `ldl`.

If a discovered file signals an error while loading (a syntax error, an unbound reference, etc.), LDL signals a `file-discovery-load-error` condition identifying the offending path rather than failing silently or aborting the whole discovery pass without explanation:

```text
Error: Failed to load features/broken-feature.lisp during project-local
file discovery.
  Error: ...

Restarts:
  0. [SKIP-FILE] Skip this file and continue discovery
  1. [ABORT] Stop processing
```

### Third-Party Plugin Discovery (ASDF Convention)

To satisfy future-readiness without modifying the LDL core, third-party extensions are discovered via standard ASDF/Quicklisp conventions, independent of and in addition to project-local file discovery.

1. Third-party extensions must be named with the `ldl-` prefix (e.g. `ldl-provider-emacs`, `ldl-catalog-nix`).
2. When LDL starts, it queries ASDF for all systems matching `ldl-*` in the available Quicklisp/local-project paths.
3. LDL loads these systems.
4. At load time, these systems execute top-level forms to register their components into the global registries:

```lisp
;; Inside ldl-provider-emacs.lisp
(ldl.core:register-provider :emacs :for :editor
  (lambda (facts) ...))
(ldl.core:register-catalog :packages :emacs '((:arch . "emacs-git")))
(ldl.core:register-action-type :my-custom-action #'my-executor)
(ldl.core:register-fact-prober :my-custom-fact #'probe-my-fact)
(ldl.core:register-pipeline-hook :after-resolve #'my-audit-hook)
```

Plugin interdependencies are expressed through ASDF's `:depends-on` mechanism, which ensures dependent plugins are loaded first:

```lisp
;; In ldl-provider-sway.asd
(defsystem "ldl-provider-sway"
  :depends-on ("ldl-core" "ldl-provider-wayland-base")
  ...)
```

### Discovery Order

On every `ldl` invocation, discovery runs in this order, before Execution Model step 1:

1. Third-party `ldl-*` systems are located and loaded (ASDF convention).
2. Project-local files are loaded from the six conventional directories, alphabetically within each (directory convention).
3. `home.lisp` is loaded last.

Loading third-party plugins first means a project's own `features/`, `providers/`, etc. may freely build on top of feature keywords or catalog entries a plugin defines (e.g. extending a plugin-provided `:editor` feature with a project-local provider), without any explicit `:depends-on`-style declaration at the project level.

---

## CLI Interface

```text
Usage: ldl <command> [options]

Commands:
  plan        Show the resolved, ordered action list
  apply       Execute the ordered action list (aborts upfront if privileges
              are insufficient for any :PACKAGE action in the plan)
  diff        Show which actions would change something
  validate    Check configuration syntax only (balanced parens, valid forms).
              Does not resolve features or providers.
  check       Fully resolve the configuration (facts, profiles, features,
              providers, actions) without executing anything, and report
              any resolution errors (missing providers, action conflicts,
              cycles, fact prober conflicts) that `validate` cannot catch.
  explain     Print the resolved feature graph and action order
  graph       Print the abstract feature dependency graph
  export      Write the action list as a data s-expression
  list        List registered features, providers, catalogs, action types
  doctor      Diagnose the environment and provider coverage
  init        Scaffold a new project
  version     Print the LDL version

Options:
  -C, --root DIR        Project root (default .)
  -p, --platform NAME   Target platform (default: auto-detect)
      --profile NAME    Select a defined profile (fact overrides)
      --provider T=P    Prefer provider P for feature T
  -n, --dry-run         Show changes without executing them
      --continue        Keep going after a failed action
  -o, --output FILE     Write output to FILE (export)
  -v, --verbose         Increase verbosity (can be repeated)
      --quiet           Only show errors
```

### Path Resolution

All `:from` paths in convenience forms are relative to the project root (specified by `-C` or defaulting to `.`).

### Validation vs. Checking

`validate` and `check` are deliberately separate commands with distinct scopes:

- **`validate`** is purely a syntax check: are the s-expressions well-formed, are parentheses balanced, are recognizable top-level forms used correctly. It does not touch facts, features, or providers, and runs even if plugins fail to load.
- **`check`** runs discovery and the full resolution pipeline (steps 0–4 of the Execution Model) without step 5 (execution), surfacing semantic problems — a `file-discovery-load-error`, an unresolvable feature, an action conflict, a dependency cycle, a `fact-prober-conflict` — before any system state would be touched by `apply`.

---

## Note on this implementation

This codebase implements the specification above with two deliberate,
documented deviations.

**First:** `:from` paths in convenience forms resolve under the
project's `files/` directory (`<root>/files/<from>`), matching the worked
example in the Discovery section (`files/gitconfig`), rather than directly
under the project root as a literal reading of the "Path Resolution"
paragraph might suggest. The two sections are in tension in the source
specification; `files/` as a dedicated, non-Lisp-loaded static-asset
directory only makes sense if `:from` resolves into it.

**Second:** the CLI Interface section above shows `apply` "aborts upfront
if privileges are insufficient for any :PACKAGE action in the plan,"
implying the whole `ldl` process needs to run as root before applying
(e.g. via `sudo ldl apply`). The implementation deliberately does not do
this. Instead, every action that genuinely needs privilege escalates on
its own, per action, via `sudo` — `ldl` itself is never run as root.
Running the whole process under `sudo` breaks `~` expansion (`sudo`
resets `$HOME` to root's home directory), which is a real, previously
observed bug this design avoids entirely. `apply` logs an informational
notice up front if the plan contains actions likely to prompt for a
password, but never aborts or requires pre-existing privilege.
