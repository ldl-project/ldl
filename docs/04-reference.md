# Reference

*Part 4 of 4 in the LDL manual — [Getting Started](01-getting-started.md) | [How I Work](02-how-i-work.md) | [How I Am Built](03-how-i-am-built.md) | Reference*

Every keyword, every option, every variation, each with a runnable
snippet. This is the part you'll come back to.

---


### 1 `define-home`

The root of your project. Exactly one per project.

```lisp
(define-home my-home
  :traits (:prune-explicitly-disabled)
  ...)
```

- `:traits` is optional. Right now I ship exactly one trait,
  `:prune-explicitly-disabled` — without it, `:disabled t` actions are
  simply never run at all (not applied, not removed); with it, they're run
  in `:remove` mode.
- Without `:traits` at all:

  ```lisp
  (define-home my-home
    (use-feature :editor :via :emacs))
  ```

Everything else inside the body is one of the forms below, or a standard
Lisp conditional wrapping them.

### 2 `use-feature`

Pulls a Feature into your home and (optionally) picks a Provider for it.

**Plain — let me auto-select the provider** (only works if exactly one is
registered):

```lisp
(use-feature :version-control)
```

**Explicit provider:**

```lisp
(use-feature :editor :via :emacs)
```

**Computed provider — any Lisp conditional over facts:**

```lisp
(use-feature :editor :via (if (fact :work-p) :emacs :vim))

(use-feature :editor
  :via (cond
         ((and (fact :work-p) (fact :laptop-p)) :emacs)
         ((fact :work-p) :vscode)
         (t :vim)))
```

**With an explicit ordering dependency** (rare — most ordering is handled
by feature `:requires`, not this):

```lisp
(use-feature :editor :via :emacs :depends-on ((:package :system . "emacs")))
```

**Wrapped in a conditional** (this is just ordinary Lisp — `use-feature`
doesn't have its own conditional form):

```lisp
(when (fact :laptop-p)
  (use-feature :power-management))

(unless (fact :work-p)
  (use-feature :gaming)
  (use-feature :media))
```

### 3 `file`

Copies (or renders) a file to a target path. Expands to a `:copy-file`
action.

**Plain:**

```lisp
(file "~/.gitconfig" :from "gitconfig")
```

**With mode / owner / group:**

```lisp
(file "~/.ssh/config" :from "ssh/config" :mode #o600)

(file "/etc/X11/xorg.conf.d/10-nvidia.conf"
      :from "nvidia/10-nvidia.conf"
      :mode #o644 :owner "root" :group "root")
```

If you omit `:owner`/`:group`, I default them to *you* — the user who
invoked `ldl`, even under `sudo`, never `root`. For anything under a
system path that genuinely needs `root:root`, set it explicitly, as above.

**With an explicit dependency:**

```lisp
(file "~/.config/starship.toml"
      :from "starship.toml"
      :depends-on ((:package :system . "starship")))
```

**Forcing a conflict win:**

```lisp
(file "~/.gitconfig" :from "gitconfig" :force t)
```

**Templated** (see §22 for the renderer side):

```lisp
(file "~/.gitconfig" :from "gitconfig.tmpl" :template t)

;; or with an explicit renderer function instead of by-convention lookup
(file "~/.gitconfig" :from "gitconfig.tmpl" :renderer #'render-gitconfig)
```

**Templated with secrets threaded in as keyword arguments:**

```lisp
(file "~/.config/gh/hosts.yml"
      :from "gh-hosts.tmpl" :template t
      :secrets ((:token :from :pass :path "github/token")))
```

### 4 `directory`

Ensures a directory exists with the right mode. Expands to `:ensure-dir`.

```lisp
(directory "~/.ssh" :mode #o700)

(directory "~/.config/emacs" :mode #o755)

;; system path needing non-default ownership
(directory "/etc/X11/xorg.conf.d" :mode #o755 :owner "root" :group "root")
```

### 5 `symlink`

Applies `ln -sf` semantics. Expands to `:symlink`.

```lisp
(symlink "~/.emacs.d" :to "~/.config/emacs")
```

### 6 `stow`

`(stow "fish")` mirrors `files/fish/**` onto a target root (default `~`),
GNU-Stow style — no dependency on the `stow` binary itself. It folds a
whole directory into a single symlink when nothing exists at the target
yet, and falls back to merging file-by-file when the target already
exists for real, recursing as deep as it needs to:

```lisp
;; files/fish/.config/fish/config.fish -> ~/.config/fish/config.fish
;; (folds the highest untaken directory -- if ~/.config doesn't exist
;; either, ~/.config itself becomes the symlink, not just ~/.config/fish)
(stow "fish")
```

**A different target root than `~`:**

```lisp
(stow "skel-fish" :to "/etc/skel")
```

**Source directory name different from the package's identity** (rarely
needed — mostly for when two profiles want different variants of the
same logical package):

```lisp
(stow "fish-work" :from "fish")
```

If two `stow` calls' packages both reach into the same subdirectory —
say, `fish` and `starship` both touch `~/.config` — the first one to run
folds `~/.config` into a single symlink; the second one *unfolds* it back
into a real directory containing both packages' files individually,
exactly like real GNU Stow does when two packages' trees overlap. You
never have to think about ordering these by hand.

**Marked for removal** (only acted on with `:prune-explicitly-disabled`):
removes exactly the symlinks this package created, then prunes any
directory left empty by that removal — but never anything that still
has unrelated content in it, and never the target root itself:

```lisp
(stow "fish" :disabled t)
```

An existing *real* file or an unrelated symlink blocking a path this
package needs is a conflict, reported clearly rather than silently
overwritten — same as real stow's own safety behavior.

### 7 `package`

Declares a package should be installed (or, with `:disabled t`,
uninstalled once pruned). Expands to `:package`, defaulting `:via` to
`:system`.

**Plain (goes through your catalog + system package manager):**

```lisp
(package "vim")
```

**Via a language-specific manager instead of the system one:**

```lisp
(package "black" :via :pip)
(package "typescript" :via :npm)
```

**Via Flatpak.** Flatpak app IDs are already the same across every
distro, so unlike `:via :system`, this never consults your catalog — the
string you give is used exactly as written. Give it as a **string, not a
keyword** — app IDs are case-sensitive (`"org.videolan.VLC"` really does
have a capital `VLC`), and a bare keyword would get uppercased by the
Lisp reader and silently stop matching:

```lisp
(package "org.videolan.VLC" :via :flatpak)
```

By default this installs system-wide (`:scope :system`, needs root, like
any other `:via :system` package) from the `flathub` remote, adding that
remote automatically if it isn't configured yet. Both are overridable:

```lisp
;; install into your own home directory instead -- never needs root,
;; and I never run this one under sudo even if you invoked ldl that way
(package "com.spotify.Client" :via :flatpak :scope :user)

;; a non-default remote needs its URL, since I can't guess a third-party
;; remote's location the way I can flathub's
(package "com.example.App" :via :flatpak :remote "my-remote" :remote-url "https://example.com/repo")
```

A plan containing only `:scope :user` Flatpak installs never triggers the
"needs root" preflight check that a `:system`-scope package would — I
only ask for privileges I actually intend to use.

**Marked for removal:**

```lisp
(package "vim-tiny" :disabled t)
(package "nano" :disabled t)
```

Remember: removal only actually *happens* if your home has the
`:prune-explicitly-disabled` trait. Without it, this line is inert —
useful if you want to document intent before you're ready to act on it.

### 8 `secret`

Writes a secret value to a target file. Expands to `:secret`. The value
is fetched fresh, immediately before the file is written, and never
persisted anywhere in plaintext along the way.

**From the `pass` password manager:**

```lisp
(secret "~/.ssh/id_ed25519" :from :pass :path "ssh/id_ed25519")
```

**From HashiCorp Vault:**

```lisp
(secret "~/.config/app/db-password" :from :vault :path "secret/data/db#password")
```

**From another file on disk:**

```lisp
(secret "~/.config/app/license" :from :file :path "/mnt/private/license.txt")
```

**Interactively prompted:**

```lisp
(secret "~/.config/app/api-key"
        :from :prompt
        :message "Enter API key for app: ")
```

If I'm running somewhere with no attached terminal (CI, a script, a cron
job) and I hit a `:prompt` secret, I won't hang waiting for input — I'll
stop and tell you there's no interactive terminal available, with the
option to supply the value programmatically, skip, or abort.

**With explicit mode:**

```lisp
(secret "~/.ssh/id_ed25519" :from :pass :path "ssh/id_ed25519" :mode #o600)
```

### 9 `env-var`

Ensures a single `export KEY="value"` line exists in a target file.
Expands to `:env-var`.

```lisp
(env-var "EDITOR" :value "emacs" :file "~/.profile")
```

### 10 `config-lines`

Ensures specific lines are present, and specific lines are absent, in a
target file — leaving everything else in that file untouched. Expands to
`:config-lines`. Note: identity for this action type includes the actual
content, so multiple `config-lines` calls against the *same file* never
conflict with each other — they're additive.

```lisp
(config-lines "~/.config/i3/config"
  :ensure ("bindsym $mod+Return exec emacs")
  :remove ("bindsym $mod+Return exec i3-sensible-terminal"))
```

**Ensure-only:**

```lisp
(config-lines "~/.config/emacs/init.el"
  :ensure ("(setq initial-buffer-choice t)"))
```

**Remove-only:**

```lisp
(config-lines "~/.bashrc" :remove ("alias rm='rm -i'"))
```

### 11 `config-ini`

Sets/unsets keys within a named `[section]` of an INI-style file. Expands
to `:config-ini`.

```lisp
(config-ini "~/.config/fontconfig/fonts.conf"
  :section "antialias"
  :set (("enable" . "true"))
  :unset ("rgba"))
```

**Set-only:**

```lisp
(config-ini "~/.gtkrc-2.0" :section "Settings" :set (("gtk-theme-name" . "Adwaita-dark")))
```

### 12 `config-env`

Sets `KEY=value` pairs in a systemd `environment.d`-style file (no section
headers). Expands to `:config-env`.

```lisp
(config-env "~/.config/environment.d/wayland.conf"
  :set (("MOZ_ENABLE_WAYLAND" . "1")
        ("QT_QPA_PLATFORM" . "wayland")
        ("XDG_CURRENT_DESKTOP" . "sway")))
```

### 13 `direct-action`

The escape hatch. For anything a feature or convenience form doesn't
cover. You always need to say why.

```lisp
(direct-action
  :reason "No provider exists for :proprietary-tool and I need it tomorrow"
  (:action :package :target "proprietary-tool" :version "1.2.3"))
```

You can pass more than one action plist in one `direct-action`:

```lisp
(direct-action
  :reason "Custom cleanup not covered by convenience forms"
  (:action :copy-file
           :from "custom/cleanup.sh"
           :to "~/.local/bin/cleanup.sh"
           :mode #o755)
  (:action :ensure-dir :target "~/.local/bin" :mode #o755))
```

`direct-action` entries always win identity conflicts outright — reaching
for the escape hatch is a deliberate act on your part, so I trust it.

### 14 Facts

**Reading one:**

```lisp
(fact :laptop-p)
(fact :os)
```

**Combining facts with ordinary predicates** (this is the whole
vocabulary — no custom conditional macros exist):

```lisp
(and (fact :work-p) (fact :laptop-p))
(member (fact :gpu) '(:nvidia :amd))
(eq (fact :display-server) :wayland)
(not (fact :laptop-p))
```

**Registering a new fact prober** (typically in `providers/*.lisp`):

```lisp
(register-fact-prober :gpu
  (lambda ()
    (cond
      ((probe-file "/proc/driver/nvidia/version") :nvidia)
      (t :unknown))))
```

If two different files register a prober for the *same* key, I won't
guess which one to trust — I'll stop at startup and tell you both
registrants, so you can remove one or make one depend on and defer to the
other.

### 15 Profiles

**Defining one:**

```lisp
(define-profile :laptop
  '((:hostname . "thinkpad") (:gpu . :nvidia) (:laptop-p . t)))
```

**Defining several, side by side** (profiles never extend each other —
each one is a complete, independent override set):

```lisp
(define-profile :work-laptop
  '((:hostname . "work-thinkpad") (:gpu . :intel) (:laptop-p . t) (:work-p . t)))

(define-profile :personal-desktop
  '((:hostname . "home-tower") (:gpu . :nvidia) (:laptop-p . nil) (:work-p . nil)))
```

**Selecting one:**

```sh
ldl plan -C ~/my-home --profile work-laptop
```

**Running with no profile at all** is completely valid — you just get
whatever the fact probers found, with no overrides:

```sh
ldl plan -C ~/my-home
```

### 16 Catalogs

**Defining one:**

```lisp
(define-catalog :packages
  (:emacs (:fedora . "emacs") (:ubuntu . "emacs-nox") (:arch . "emacs")))
```

**A catalog entry with fewer distros than you support** — this is fine,
distros that aren't listed just fall back to the keyword's own name:

```lisp
(define-catalog :packages
  (:htop (:fedora . "htop")))   ; on :arch, resolves to "htop" anyway
```

**Extending an existing catalog from a plugin, without redefining the
whole thing:**

```lisp
(register-catalog :packages :emacs '((:void . "emacs-nox")))
```

### 17 Features

```lisp
(define-feature :development
  :description "Core development tools: compilers, debuggers, version control"
  :tags (:dev :core)
  :provides (:compilers :version-control)
  :requires (:editor))
```

- `:description` and `:tags` are documentation only — I don't act on them,
  but `ldl list`/`ldl doctor` can surface them.
- `:requires` is the real mechanism: when you `use-feature :development`,
  I make sure `:editor` is resolved first.

**A feature with no dependencies at all:**

```lisp
(define-feature :shell :requires nil)
```

### 18 Providers

```lisp
(register-provider :emacs :for :editor
  (lambda (facts)
    (list
      '(:action :package :target :emacs :via :system)
      '(:action :ensure-dir :target "~/.config/emacs/" :mode #o755)
      '(:action :copy-file :from "emacs/init.el" :to "~/.config/emacs/init.el"))))
```

**A provider that computes its actions from facts, instead of returning a
fixed list:**

```lisp
(register-provider :lsp-auto-install :for :language-support
  (lambda (facts)
    (mapcar (lambda (lang)
              (list :action :package
                    :target (format nil "~a-lsp" lang) :via :system))
            (getf facts :languages))))
```

**Giving a provider a description**, so `ldl list` and `ldl explain` show
something more useful than just its name:

```lisp
(register-provider :emacs :for :editor :description "GNU Emacs with a minimal, fast-starting config"
  (lambda (facts) ...))
```

**A provider that conditionally returns nothing** (useful when the
provider itself should only apply under certain facts, independent of
whether the feature was requested):

```lisp
(register-provider :nvidia-proprietary :for :nvidia-drivers
  (lambda (facts)
    (when (eq (getf facts :gpu) :nvidia)
      (list '(:action :package :target :nvidia-driver :via :system)))))
```

**Marking a provider as the default**, so `(use-feature :shell)` doesn't
force you to specify `:via` when several providers exist for a feature —
I'll only auto-select the sole provider when there's exactly one *or*
exactly one is marked `:default t`:

```lisp
(register-provider :bash :for :shell :default t
  (lambda (facts) (declare (ignore facts))
    (list '(:action :package :target :bash :via :system)
          '(:action :copy-file :to "~/.bashrc" :from "bashrc"))))

(register-provider :zsh :for :shell
  (lambda (facts) (declare (ignore facts))
    (list '(:action :package :target :zsh :via :system)
          '(:action :copy-file :to "~/.zshrc" :from "zshrc"))))
```

With that in place, both of these work:

```lisp
(use-feature :shell)              ; -> bash, since it's the default
(use-feature :shell :via :zsh)    ; -> zsh, explicit override still wins
```

If nobody registers a default and more than one provider exists, I still
stop and ask you to disambiguate — same as always, just with a message
that now lists every candidate by name so you can see exactly what you're
choosing between. If more than one provider claims `:default t` for the
same feature, that's also an error — a default has to be unambiguous too.

Because a provider is just a function, you (or a provider author writing
tests) can call it directly with a fixture fact plist and assert on the
list it returns — no special test mode needed for providers, unlike
executors.

### 19 The built-in Action types, directly

You'll mostly reach these through the convenience forms above, but every
one of them is a plain plist you can also write yourself (inside a
provider, or via `direct-action`):

```lisp
(:action :package     :target :emacs :via :system)
(:action :ensure-dir   :target "~/.config/emacs/" :mode #o755 :owner "user" :group "user")
(:action :copy-file    :from "emacs/init.el" :to "~/.config/emacs/init.el" :mode #o644)
(:action :symlink      :target "~/.emacs.d" :to "~/.config/emacs")
(:action :service      :target :ssh-daemon :enabled t :running t)
(:action :timer        :target "backup-daily" :on-calendar "daily")
(:action :env-var      :target "EDITOR" :value "emacs" :file "~/.profile")
(:action :config-lines :target "~/.config/i3/config"
                        :ensure ("bindsym $mod+Return exec emacs")
                        :remove ("bindsym $mod+Return exec i3-sensible-terminal"))
(:action :config-ini   :target "~/.config/fontconfig/fonts.conf"
                        :section "antialias" :set (("enable" . "true")) :unset ("rgba"))
(:action :config-env   :target "~/.config/environment.d/wayland.conf"
                        :set (("MOZ_ENABLE_WAYLAND" . "1")))
(:action :secret       :target "~/.ssh/id_ed25519" :from :pass :path "ssh/id_ed25519" :mode #o600)
(:action :stow         :target "fish" :to "~")
```

Thirteen more built-in types — `:user`, `:group`, `:authorized-key`,
`:permissions`, `:mount`, `:sysctl`, `:kernel-module`, `:hostname`,
`:locale`, `:firewall`, `:cron`, `:command`, `:clone` — cover system
administration and other tasks beyond a single home directory. They have
their own convenience forms too (`user`, `group`, `authorized-key`, ...);
see §21 for every one of them with example variations.

**`:service`, specifically** — enables/starts a systemd unit only if it
isn't already in the desired state:

```lisp
(:action :service :target :tlp :enabled t :running t)
```

**`:timer`, specifically** — creates and enables a systemd timer unit:

```lisp
(:action :timer :target "backup-daily" :on-calendar "daily")
```

**Registering a brand-new action type** (for when even `direct-action`
plus the built-ins don't cover what you need — an author-level
extension):

```lisp
(register-action-type :my-custom-action
  (lambda (action &key mode)
    (case mode
      (:check (list :status :would-change :target (getf action :target)))
      (:apply (list :status :changed :target (getf action :target)))
      (:remove (list :status :removed :target (getf action :target))))))
```

### 20 Generic action properties

These work on *any* action, whether written via a convenience form or
directly:

```lisp
;; Run only after another action, by identity
(file "starship.toml" :from "starship.toml"
      :depends-on ((:package :system . "starship")))

;; Win any identity conflict outright
(file "~/.gitconfig" :from "gitconfig" :force t)

;; Mark for removal (only acted on with :prune-explicitly-disabled)
(package "nano" :disabled t)

;; Explicit ownership for a system path
(file "/etc/foo.conf" :from "foo.conf" :owner "root" :group "root")
```

### 21 System administration actions

The built-in types in §19 cover dotfiles, packages, and services. A
separate class of task shows up once you're managing more than your own
home directory — system users, mounts, kernel parameters, the firewall —
and deserves its own dedicated, idempotent executors rather than being
bent out of shape from `:config-lines` or a raw shell command. Here they
are, one by one.

**`user`** — creates or modifies a system user; only touches what's
actually different (an existing user with matching attributes is left
alone):

```lisp
(user "deploy" :shell "/bin/bash" :create-home t)

(user "postgres" :system t :create-home nil :shell "/usr/sbin/nologin")

;; lock or unlock the account
(user "deploy" :locked t)

;; remove it (only acted on with :prune-explicitly-disabled)
(user "old-service-account" :disabled t :remove-home t)
```

**`group`** — creates or modifies a system group:

```lisp
(group "docker")
(group "docker" :gid 999)
(group "sudo" :disabled t)
```

**`authorized-key`** — manages one entry in a user's
`~/.ssh/authorized_keys`, without touching any other key already there.
Re-declaring the same key with a different comment updates it in place
rather than creating a duplicate line, and I enforce the strict `700`/
`600` permissions SSH requires on the directory and file:

```lisp
(authorized-key "deploy" :key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI...")

(authorized-key "deploy"
  :key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..."
  :comment "ci-bot@github-actions")

;; remove just this one key, leaving every other key in the file alone
(authorized-key "deploy" :key "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAI..." :disabled t)
```

**`permissions`** — fixes owner/group/mode on a path that already exists,
without creating it and without touching its content. This is the tool
for paths a *package* created (`/var/lib/mysql`, `/var/www`), which
`file`/`directory` only ever set ownership on at creation time:

```lisp
(permissions "/var/lib/mysql" :owner "mysql" :group "mysql" :mode #o750)

(permissions "/var/www" :owner "www-data" :group "www-data" :recursive t)
```

**`mount`** — ensures a persistent `/etc/fstab` entry exists *and* the
filesystem is actually mounted right now, not just on next boot:

```lisp
(mount "/mnt/data" :device "/dev/sdb1" :fstype "ext4")

(mount "/mnt/data" :device "/dev/sdb1" :fstype "ext4" :options "defaults,noatime")

;; a bind mount
(mount "/srv/containers/app/data" :device "/mnt/data/app" :fstype "none" :options "bind")

;; unmount and drop the fstab entry
(mount "/mnt/data" :device "/dev/sdb1" :disabled t)
```

**`sysctl`** — sets a kernel parameter, persists it under
`/etc/sysctl.d/`, and applies it to the *running* kernel immediately, so
you don't need a reboot to see the effect:

```lisp
(sysctl "net.ipv4.ip_forward" :value 1)

(sysctl "vm.swappiness" :value 10 :file "/etc/sysctl.d/60-swap.conf")
```

**`kernel-module`** — loads a module now and persists that decision via
`/etc/modules-load.d/`, or blacklists one via `/etc/modprobe.d/`:

```lisp
(kernel-module "nfs" :state :loaded)
(kernel-module "usb-storage" :state :blacklisted)
```

**`hostname`** — sets the hostname at runtime *and* writes `/etc/hostname`
so it survives a reboot; setting only one or the other is a common
half-fix this avoids:

```lisp
(hostname "app-server-01")
```

**`locale`** — generates a locale if it isn't already, sets it as the
system default, and optionally sets the timezone (which involves
re-pointing the `/etc/localtime` symlink, not just editing a config file):

```lisp
(locale "en_US.UTF-8")
(locale "en_US.UTF-8" :timezone "America/New_York")
```

**`firewall`** — opens or closes a port through whichever of
`firewalld`/`ufw` is actually installed, so your home config doesn't have
to hard-code one:

```lisp
(firewall 80 :protocol "tcp" :allow t)
(firewall 22 :protocol "tcp" :allow t)

;; close a port
(firewall 8080 :protocol "tcp" :allow nil)
```

**`cron`** — manages one entry under `/etc/cron.d/`, for the minimal
installs (Alpine, Debian-minimal, older RHEL) that still lean on cron
instead of systemd timers:

```lisp
(cron "nightly-backup" :schedule "0 2 * * *" :command "/usr/local/bin/backup.sh")

(cron "cleanup-tmp"
  :schedule "*/15 * * * *"
  :command "/usr/bin/find /tmp -mtime +1 -delete"
  :user "root")
```

**`command`** — the escape hatch beneath the escape hatch: a raw shell
command, but with an idempotency check so it doesn't just re-run blindly
every time. Give me exactly one of `:creates`, `:unless`, or `:only-if`:

```lisp
;; run only if this path doesn't exist yet
(command "install oh-my-zsh" :run "sh install-oh-my-zsh.sh --unattended"
         :creates "~/.oh-my-zsh")

;; run only if this shell command currently fails (exits non-zero)
(command "install rustup" :run "curl https://sh.rustup.rs -sSf | sh -s -- -y"
         :unless "command -v rustup")

;; run only if this shell command currently succeeds
(command "restart flaky service" :run "systemctl restart flaky.service"
         :only-if "systemctl is-failed --quiet flaky.service")
```

If you give me none of the three, I can't reason about whether the
command is needed — I'll say so honestly (`:would-change` under `plan`,
and I'll run it on every `apply`) rather than pretend I checked something
I didn't. That's a signal to add a check, not a bug to work around.

(Cloning a git repo specifically has its own dedicated type, `:clone`,
just below — prefer it over `command` + `git clone` when that's all
you need, since it actually checks the repo's real state on a repeat
run instead of just a marker file's presence.)

Give `:sudo t` when `:run` (and `:remove-run`, if present) itself needs
root:

```lisp
(command "set timezone" :run "timedatectl set-timezone America/New_York"
         :unless "timedatectl show --property=Timezone | grep -q America/New_York")
```

```lisp
(command "write sysctl override" :run "echo 1 > /proc/sys/net/ipv4/ip_forward"
         :only-if "test $(cat /proc/sys/net/ipv4/ip_forward) != 1"
         :sudo t)
```

Every other built-in action type escalates on its own, per-command, only
if a plain attempt actually fails — `:command` is the one exception,
because I can't safely guess whether an arbitrary shell string needs
root, and re-running it after a failed plain attempt could leave things
half-done. So for `:command` specifically, `:sudo t` is how you tell me
up front; I still skip `sudo` itself if the whole process already happens
to be running as root (see §21's general escalation note and
`docs/03-how-i-am-built.md`).

**`clone`** — ensures a git repository is checked out at `:target`,
requires the `git` binary. Unlike `command` + a `:creates` marker, a
repeat run actually looks at the repo's real state: it checks the
checked-out repo's `origin` remote against the declared `:url`, not just
whether the directory happens to exist:

```lisp
(clone "~/.dotfiles" :url "https://example.com/dotfiles.git")

(clone "~/.cache/ldl/krohnkite" :url "https://github.com/esjeon/krohnkite.git"
       :branch "main" :depth 1)
```

- Target missing → clones it.
- Target exists, `origin` matches `:url` → `:unchanged` — I never re-clone
  or re-fetch on every run.
- Target exists but isn't a git repository at all → a clear
  `execution-failure`, refusing to clone over whatever's actually there,
  the same conflict-detection philosophy as `:stow`.
- Target exists, is a git repo, but `origin` doesn't match the declared
  `:url` → also a clear `execution-failure` — a real contradiction on
  disk, not something I'll silently re-point.
- `:branch` given, but a *different* branch is currently checked out → I
  only warn about it; I never auto-switch branches, since that could
  discard a dirty working tree.
- `:depth` only affects the initial clone — I don't re-verify it
  afterward (git doesn't cheaply expose "was this a shallow clone of
  depth N" for me to check against).

I never escalate for `:clone` itself (you're cloning into your own
directories); `:remove` deletes the whole checked-out tree, falling back
to a privileged `rm -rf` only if the plain delete fails, same as every
other filesystem-removing built-in.

### 22 Templates

A template renderer is a plain Common Lisp function returning a string,
living in `templates/*.lisp`, in the `:ldl-templates` package.

**By-convention discovery** — `gitconfig.tmpl` looks for
`RENDER-GITCONFIG`:

```lisp
;; templates/renderers.lisp
(in-package :ldl-templates)

(defun render-gitconfig (facts &key signing-key work-email)
  (format nil "[user]
    name = ~a
    email = ~a
    signingkey = ~a"
          (getf facts :user-name)
          (if (getf facts :work-p) work-email "personal@example.com")
          (or signing-key "")))
```

Used from `home.lisp` as:

```lisp
(file "~/.gitconfig" :from "gitconfig.tmpl" :template t
      :secrets ((:signing-key :from :pass :path "git/signing-key")
                (:work-email :from :pass :path "git/work-email")))
```

If I can't find a matching `RENDER-*` function, I'll stop and tell you the
exact symbol name I looked for, with the option to supply a renderer,
treat the file as static instead, skip, or abort.

**Explicit renderer, skipping by-convention lookup entirely:**

```lisp
(file "~/.gitconfig" :from "gitconfig.tmpl" :renderer #'render-gitconfig)
```

### 23 Pipeline hooks

Two extension points, for cross-cutting behavior that doesn't belong in
any single provider:

**`:after-resolve`** — runs right after step 2, before deduplication, with
every collected action:

```lisp
(register-pipeline-hook :after-resolve
  (lambda (facts actions)
    (declare (ignore facts))
    (dolist (action actions)
      (when (eq (getf action :action) :secret)
        (ldl.log:info "Secret action targets ~a" (getf action :target))))))
```

**`:before-execute`** — runs right after step 4, with the final ordered
list, before anything is actually executed:

```lisp
(register-pipeline-hook :before-execute
  (lambda (facts ordered-actions)
    (declare (ignore facts))
    (let ((removals (remove-if-not (lambda (a) (getf a :disabled)) ordered-actions)))
      (when removals
        (ldl.log:warn "This run will remove ~d resource(s)." (length removals))))))
```

Multiple hooks at the same point run in the order you registered them. A
hook can signal a condition to halt the run, but it can't rewrite the
action list or reorder execution — it observes and may object, nothing
more.

### 24 The CLI, command by command

```
ldl plan       -C DIR [--profile NAME]
ldl apply      -C DIR [--profile NAME] [-n] [--continue]
ldl diff       -C DIR [--profile NAME]
ldl validate   -C DIR
ldl check      -C DIR [--profile NAME]
ldl explain    -C DIR [--profile NAME]
ldl graph      -C DIR [--profile NAME]
ldl export     -C DIR [--profile NAME] [-o FILE]
ldl list       -C DIR
ldl facts      -C DIR [--profile NAME]
ldl doctor     -C DIR [--profile NAME]
ldl init       -C DIR
ldl version
```

**`plan`** — resolve everything, print the ordered action list, touch
nothing:

```sh
ldl plan -C ~/my-home --profile work-laptop
```

**`apply`** — actually execute. Never run this one under `sudo` yourself:
whichever individual actions in the plan genuinely need root (a package
install, a root-owned system file) escalate on their own, one command at
a time, and may prompt you for your `sudo` password right at that step:

```sh
ldl apply -C ~/my-home --profile work-laptop

# dry-run: see exactly what apply would have done, touches nothing
ldl apply -C ~/my-home --profile work-laptop -n
```

**`diff`** — check mode, but focused on reporting only what would
actually change:

```sh
ldl diff -C ~/my-home --profile work-laptop
```

**`validate`** — syntax only, doesn't touch facts/features/providers at
all, runs even if a plugin is broken:

```sh
ldl validate -C ~/my-home
```

**`check`** — full resolution (steps 0–4), no execution — catches missing
providers, action conflicts, dependency cycles, fact-prober conflicts:

```sh
ldl check -C ~/my-home --profile work-laptop
```

**`explain`** — prints which provider was actually chosen for each
feature you used (not just the feature name), each with its description,
plus the final numbered action order, for when `plan`'s output isn't
detailed enough:

```sh
ldl explain -C ~/my-home --profile work-laptop
```

**`graph`** — prints the abstract feature dependency graph (not the
action list), with each feature's description alongside it:

```sh
ldl graph -C ~/my-home --profile work-laptop
```

**`export`** — writes the resolved action list out as a Lisp
s-expression, to a file if you want one:

```sh
ldl export -C ~/my-home --profile work-laptop -o /tmp/plan.sexp
```

**`list`** — every registered feature, provider, catalog, and action
type, as aligned tables, each with whatever description you gave it (in
`:description` on `define-feature`, `register-provider`, or a built-in
action type's own documentation). Features get a combined view showing
every provider registered for them in one row:

```sh
ldl list -C ~/my-home
# Features:
#   FEATURE   DESCRIPTION              PROVIDERS
#   --------  -----------------------  --------------------
#   editor    Text editor capability   emacs (default), vim
#   shell     Login shell and dotfiles bash, zsh
#
# Providers:
#   PROVIDER  FOR FEATURE  DEFAULT  DESCRIPTION
#   --------  -----------  -------  ----------------------------------------
#   emacs     editor       yes      GNU Emacs with a minimal, fast-starting config
#   vim       editor                Vim with sane defaults, no plugin manager
#
# Action types:
#   TYPE       DESCRIPTION
#   ---------  --------------------------------------
#   copy-file  Copy or render a file to a target path
#   ...
```

**`facts`** — print every resolved fact, after probing and merging your
selected `--profile`, one per line, aligned. This is the fastest way to
answer "why did I pick that provider on this machine" without re-deriving
it from probes yourself:

```sh
ldl facts -C ~/my-home --profile work-laptop
#   DISPLAY-SERVER  :WAYLAND
#   GPU             :INTEL
#   HOSTNAME        "work-thinkpad"
#   LAPTOP-P        T
#   OS              :DEBIAN
#   WORK-P          T
```

**`doctor`** — sanity-checks your environment against your home: OS,
hostname, privileges, a table of exactly how each `use-feature` resolves
(the chosen provider, or a clear diagnosis — no provider registered,
ambiguous with no default, a `:via` that doesn't exist), and a count of
how many package installs in the plan will actually need root:

```sh
ldl doctor -C ~/my-home --profile work-laptop
```

**`init`** — scaffold a brand-new project (see Part 2, Step 1):

```sh
ldl init -C ~/my-home
```

**Global options, usable on (almost) any command:**

```
-C, --root DIR        Project root (default .)
-p, --platform NAME    Target platform (default: auto-detect)
    --profile NAME     Select a defined profile
    --provider T=P     Prefer provider P for feature T
-n, --dry-run          Show changes without executing them (apply)
    --continue         Keep going after a failed action
-o, --output FILE      Write output to FILE (export)
-v, --verbose          Increase verbosity (repeat for more: -v, -vv)
    --quiet            Only show errors
-h, --help             Show help and exit
```

### 25 Getting help

I try never to leave you guessing about what a command accepts.

**Running me with no arguments, or `ldl --help`,** prints every command
with a one-line description, aligned into a column, followed by every
global option:

```sh
ldl --help
# Usage: ldl <command> [options]
#
# Commands:
#   plan      Show the resolved, ordered action list
#   apply     Execute the ordered action list
#   ...
```

**Adding `--help` after any specific command** shows that command's own
usage line, description, exactly the options *it* accepts (not every
option I support globally — `init` doesn't take `--profile`, for
instance, and I won't pretend it does), and a couple of runnable
examples:

```sh
ldl apply --help
# Usage: ldl apply [options]
#
# Execute the ordered action list
#
# Options:
#   -C, --root DIR  Project root (default ".")
#   --profile NAME  Select a defined profile (fact overrides)
#   -n, --dry-run   Show changes without executing them
#   --continue      Keep going after a failed action
#   -v, --verbose   Increase verbosity (repeatable: -v, -vv)
#   --quiet         Only show errors
#   -h, --help      Show this command's help and exit
#
# Examples:
#   ldl apply -C ~/my-home --profile work-laptop   # sudo (if needed) is per-action
#   ldl apply -C ~/my-home --profile work-laptop -n   # dry run
```

**If you pass a flag I don't recognize, or leave a flag missing its
required value,** I won't silently ignore it or crash with a raw stack
trace — I print that command's help (so you can see immediately what it
does accept) and exit non-zero:

```sh
ldl apply --bogus-flag
# [error] Unknown or malformed option(s) for 'apply': --bogus-flag
#
# Usage: ldl apply [options]
# ...
```

### 26 When I stop and ask you something

I use the Common Lisp Condition System for every error, not exceptions in
the exception-handling sense. That means every failure comes with
concrete restarts, not just a stack trace. Every command — not just
`apply` — catches these cleanly and prints a one-line error instead of an
SBCL backtrace. Here's the full list of conditions I can signal, and what
your options are at each one:

| Condition | When it happens | Your restarts |
|---|---|---|
| `missing-provider` | You `use-feature`d something with no matching (or ambiguous) provider | specify a provider / skip the feature / abort |
| `action-conflict` | Two same-priority actions claim the same identity with different content | keep definition A / keep definition B / abort |
| `non-interactive-prompt` | A `:prompt` secret was hit with no attached terminal | supply the value / skip / abort |
| `fact-prober-conflict` | Two different registrations claim the same fact key | abort (fix one of the registrations) |
| `missing-template-renderer` | `:template t` but no matching `RENDER-*` function exists | specify a renderer / treat as static / skip / abort |
| `file-discovery-load-error` | One of your project's `.lisp` files failed to load | skip that file / abort |
| `dependency-cycle` | Your `:depends-on` edges form a loop | abort (fix the cycle) |
| `execution-failure` | An executor's underlying operation failed (disk full, network down, a privileged command's sudo prompt failed or was declined, ...) | retry / skip / abort |

I never require you to run me as root. Every action that genuinely needs
privilege escalates on its own, per action, via `sudo` — a package
install, a write to a root-owned system file, creating a system user.
Everything else never touches `sudo` at all. If a privileged step
genuinely fails (wrong password, no TTY, cancelled), that's a real
`execution-failure`, not something silently treated as "nothing needed to
change."

I never retry automatically, and I never roll back. Re-running me after
you've fixed the underlying problem is always the right move — every
built-in executor is idempotent, so re-running is cheap and safe.

### 27 A note on stale builds

If you build me as a standalone executable with `save-lisp-and-die` and
you ever update your `ldl` checkout in place (pull a fix, re-extract a
new copy over an old directory, etc.), make sure ASDF actually recompiles
from the new sources before you re-save the image. If you reuse an old
project directory, or your fasl cache still has compiled output from a
previous build, ASDF can decide nothing's changed based on file
timestamps and silently reuse stale compiled code — you'll see behavior
from a version you thought you'd already fixed. The reliable fix is to
force a full rebuild:

```lisp
(asdf:load-system :ldl :force t)
```

I'd rather you hit this note once here than debug it from a cryptic error
a second time.

---

That's everything. If you made it this far: go build something. Start
small — one feature, one provider, one file — and grow it. That's how I'm
meant to be used.

---

That's the complete reference. If something here doesn't match what you
see when you run it, start with [How I Work](02-how-i-work.md) to
re-check the mental model, or [How I Am Built](03-how-i-am-built.md) if
you're trying to understand *why* rather than *what*.
