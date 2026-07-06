# How I Am Built

*Part 3 of 4 in the LDL manual — [Getting Started](01-getting-started.md) | [How I Work](02-how-i-work.md) | How I Am Built | [Reference](04-reference.md)*

The first two parts of this manual are about *using* me to describe a
Linux home environment. This part is different: it's for you if you want
to understand my own source, extend me with a new action type, or just
know why a file lives where it lives before you go digging through it.
If you only ever plan to write `home.lisp` files, you can skip this part
entirely and come back if curiosity strikes.

---

## Source layout

```
ldl/
├── ldl.asd                 # Explicit ASDF :components list
├── src/
│   ├── package.lisp         # The three packages: :ldl.core, :ldl.log, :ldl-templates
│   ├── conditions.lisp      # Every condition class + restart vocabulary
│   ├── log.lisp             # Leveled logging
│   ├── discovery.lisp       # Step 0: directory + ASDF-plugin discovery
│   ├── facts.lisp           # Fact prober registration/probing
│   ├── profiles.lisp        # Named fact-override sets
│   ├── catalogs.lisp        # Canonical name -> distro-string tables
│   ├── features.lisp        # Feature DAG + resolution
│   ├── providers.lisp       # Provider registration/selection
│   ├── actions.lisp         # Identity, dedup, ordering, dispatch
│   ├── secrets.lisp         # :pass/:vault/:file/:prompt resolution
│   ├── templates.lisp       # RENDER-* discovery
│   ├── action-types/        # One file per built-in executor
│   ├── pipeline.lisp        # The five-step Execution Model + hooks
│   ├── privilege.lisp       # Privilege preflight for apply
│   ├── dsl.lisp             # define-home + convenience macros
│   └── cli.lisp             # Argument parsing + dispatch
└── docs/                    # This manual, the spec, and guides
```

Every file starts with a header describing exactly what it does and how
to use it — that header is the fastest way to orient yourself in any
single file, faster than reading this section again.

## The package split

Three packages, one job each:

- **`:ldl.core`** — everything: the DSL, the pipeline, every built-in
  action executor, the CLI. This is where you'll spend nearly all your
  time if you're extending me.
- **`:ldl.log`** — a small leveled-logging facility (`info`, `debug*`,
  `warn*`, `error*`), kept separate so providers and executors can log
  without depending on the rest of the core.
- **`:ldl-templates`** — deliberately empty by default. A home project's
  own `templates/*.lisp` files add `RENDER-*` functions here; I never
  define anything in it myself.

Two symbols are worth knowing about early: `:ldl.core` shadows
`cl:package` and `cl:directory`, because the home-definition DSL wants
`package` and `directory` as macro names. If you're working inside
`:ldl.core` and reach for the standard Lisp functions of those names,
you'll get my macros instead — use `cl:directory`/`cl:package` explicitly
if you ever need the originals.

## The registries

I don't keep a database. Every piece of registered knowledge — every
feature, provider, catalog, fact prober, pipeline hook, and action type —
lives in a plain hash table, held in a special variable:

| Variable                     | Populated by                          | Cleared on every `bootstrap`? |
|------------------------------|---------------------------------------|-------------------------------|
| `*feature-registry*`         | `define-feature`                      | Yes                           |
| `*providers*`                | `register-provider`                   | Yes                           |
| `*catalogs*`                 | `define-catalog` / `register-catalog` | Yes                           |
| `*fact-probers*`             | `register-fact-prober`                | Yes                           |
| `*pipeline-hooks*`           | `register-pipeline-hook`              | Yes                           |
| `*profiles*`                 | `define-profile`                      | Yes                           |
| `*action-types*`             | `register-action-type`                | **No**                        |
| `*action-type-descriptions*` | `register-action-type :description`   | **No**                        |

The first six are populated by **Discovery** (a home project's own
`.lisp` files, loaded fresh on every single command) and are cleared at
the start of every `bootstrap` call specifically so that running more
than one command in a long-lived Lisp image — a REPL, a saved image used
interactively — never silently accumulates stale or duplicate
registrations. A fresh per-invocation process never would have noticed
the difference; a persistent one does, and did, until this was fixed.

The last two are populated once, when the `:ldl` system itself loads
(each `action-types/*.lisp` file registers its own type at the top
level), and never touched by Discovery — they're part of *me*, not part
of any project, so clearing them on every command would just break
every action type after the first call.

## The condition system

Every error path uses a real CLOS condition class from `conditions.lisp`,
not a bare `(error "some string")`. Two conditions go further than that
and carry genuine, named, invokable restarts:

- `action-conflict` offers `USE-FIRST`/`USE-SECOND`.
- `missing-provider` (the ambiguous-multiple-providers case) offers
  `SPECIFY-PROVIDER` (with an `:interactive` clause, so a live debugger
  prompts you for a name) and `SKIP-FEATURE`.

Everything an action executor itself raises is wrapped, at the point of
execution, in `RETRY`/`SKIP`/`ABORT-PROCESSING`. The compiled CLI catches
all of this in one place (`src/cli.lisp`'s `WITH-CLI-ERROR-REPORT`) and
turns it into a one-line message; a live REPL sees the real condition and
its real restarts instead. See `docs/how-to-debug.md` for exactly how to
get the latter.

## Why the core isn't auto-discovered

A home project's `features/`, `providers/`, `catalogs/`, and so on are
loaded automatically — that's the entire point of Discovery. My own
`src/` is not: `ldl.asd` lists every file explicitly, in dependency
order, with `:serial t`. This isn't an oversight; Discovery is
*implemented* in `src/discovery.lisp`, and a system can't bootstrap
itself via a mechanism it hasn't loaded yet. So my own layout is ordinary
ASDF, and a home project's layout is the directory convention Discovery
provides — two different things, on purpose.

## Extension points, summarized

If you're writing a feature for a project (not modifying me), you almost
certainly want `docs/how-to-feature.md` instead of this section — it's a
complete, example-driven guide. This is just the map of what's
extensible and where it's registered:

| To add                                                                | Call                     | Where it typically lives                                               |
|-----------------------------------------------------------------------|--------------------------|------------------------------------------------------------------------|
| A capability                                                          | `define-feature`         | a project's `features/*.lisp`                                          |
| An implementation of a capability                                     | `register-provider`      | a project's `providers/*.lisp`                                         |
| A distro package-name mapping                                         | `register-catalog`       | a project's `catalogs/*.lisp`                                          |
| A new probed fact                                                     | `register-fact-prober`   | a project's `providers/*.lisp`                                         |
| Cross-cutting behavior (audit logging, a confirmation prompt)         | `register-pipeline-hook` | a project's `hooks/*.lisp`                                             |
| A template renderer                                                   | a `RENDER-*` function    | a project's `templates/*.lisp`                                         |
| **A genuinely new action type** (rare — `:command` covers most cases) | `register-action-type`   | a plugin, or a change to `src/action-types/` if it belongs in the core |

That last one is the only extension point that touches me rather than a
project. A new action type is a function of `(action &key mode)` handling
`:apply`/`:check`/`:remove`, plus one `register-action-type` call with a
`:description`. Look at any file in `src/action-types/` as a template —
`command.lisp` is the simplest complete example.

---

Next: the [Reference](04-reference.md) has the exhaustive list of
everything mentioned above, with every option and every variation. Or,
for the practical side of extending or debugging me, see
`docs/how-to-feature.md` and `docs/how-to-debug.md` directly.
