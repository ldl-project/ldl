# How I Work

*Part 2 of 4 in the LDL manual — [Getting Started](01-getting-started.md) | How I Work | [How I Am Built](03-how-i-am-built.md) | [Reference](04-reference.md)*

This is the mental model: Facts, Profiles, Features, Providers, Catalogs,
Actions, and the five-step pipeline that ties them together. If you read
nothing else in this manual, read this part — everything else is detail
on top of what's here.

---

## The one-sentence version

### The pipeline, in order

Every time you run me — `ldl plan`, `ldl apply`, `ldl check`, whatever —
I do the same five things, in the same order, preceded by a discovery pass:

```
0. Discover   -- find and load your project's .lisp files, and any
                 third-party ldl-* plugins
1. Probe      -- figure out facts about this machine, then apply your
                 chosen --profile on top
2. Resolve    -- walk your use-feature calls, find the right provider
                 for each, run each provider, collect every action
                 (yours and the providers')
3. Deduplicate -- if two actions want to touch the same thing, decide
                 which one wins (or complain, if I can't tell)
4. Order      -- sort the surviving actions so dependencies run first
5. Execute    -- run each action's executor, in order
```

I want to walk through each of these once, slowly, because understanding
this order will save you a lot of head-scratching later.

#### Step 0: Discovery

Before I know anything about your machine, I go looking for code. I look
for two kinds:

- **Your project's own files.** I have six subdirectories I always check:
  `profiles/`, `features/`, `providers/`, `catalogs/`, `templates/`,
  `hooks/`. Any `.lisp` file in any of them, at any depth, gets loaded —
  alphabetically, so you can control ordering within a directory just by
  naming files `00-first.lisp`, `01-second.lisp` if you ever need to. Then,
  last of all, I load `home.lisp` from your project root.
- **Third-party plugins.** Any ASDF system whose name starts with `ldl-`
  gets loaded too, before your own files, so your project can build on top
  of whatever a plugin registers.

Nobody writes a manifest file listing what to load. You just drop a
`.lisp` file in the right directory and I'll find it next time you run me.

One thing that trips people up: **`home.lisp` is loaded, but not run,**
during discovery. Your `define-home` body only actually executes later, in
step 2, once I know real facts about the machine. I'll explain why in a
moment — it's the reason `(when (fact :laptop-p) ...)` works at all.

#### Step 1: Facts and Profiles

A **Fact** is something true about the machine you're running on:
`:os`, `:hostname`, `:laptop-p`, `:display-server`, and anything else a
provider author decided to probe for (`:gpu` is a common one). I gather
these automatically, once, at the start of every run. You read them with
`(fact :key)`.

A **Profile** is a named override list you select with `--profile`. It
doesn't replace fact-probing — it runs *after* it, and just overwrites
whichever keys it mentions. This is how one `home.lisp` describes your
laptop, your desktop, and your server: the facts differ, the file doesn't.

```lisp
(define-profile :laptop
  '((:hostname . "thinkpad") (:gpu . :nvidia) (:laptop-p . t)))
```

Once probing + profile merging is done, I hand you a flat plist of facts.
`(fact :key)` is the only way you ever read one. There's no way to tell,
from inside your `home.lisp`, whether a value came from a prober or a
profile — and that's deliberate. It keeps the language simple: you never
have to reason about layers, only about the final value.

#### Step 2: Resolving the feature graph

This is where your `home.lisp` body actually runs. I already have facts;
now I execute your `define-home` form top to bottom, exactly like ordinary
Common Lisp code — because that's exactly what it is. `when`, `unless`,
`if`, `cond`, `and`, `or` — I don't reinvent any of these. If you can write
it as a standard Lisp conditional over `(fact ...)`, it works.

Every `(use-feature :something ...)` you write gets queued up. Once your
whole body has run, I:

1. Take every feature name you asked for, and recursively pull in whatever
   they `:requires`, building a dependency-ordered list.
2. For each feature, pick the right **Provider**. If you said
   `:via :emacs`, I use the provider registered under that name. If you
   didn't say `:via` and there's exactly one provider registered for that
   feature, I use it automatically. If there's more than one and you
   didn't disambiguate, I stop and tell you.
3. Call each selected provider with the current facts. A provider is just
   a function from facts to a list of actions — nothing more. It can
   return a fixed list, or compute one; I don't care which.
4. Collect everything: the actions your providers returned, plus every
   `file`, `package`, `secret`, ... form you wrote directly in
   `define-home`.

#### Step 3: Deduplication

Now I might have two actions that both want to manage
`~/.gitconfig` — say, a provider ships a default one, and you also wrote
`(file "~/.gitconfig" :from "gitconfig")` yourself because you wanted
something different. I resolve this by **identity** and **priority**:

- Every action has an identity — usually just its type plus its target,
  like `(:copy-file . "~/.gitconfig")`.
- Things you wrote directly in `define-home` outrank things a provider
  returned.
- If two actions of the *same* priority claim the same identity with
  *different* content, I stop and ask you to sort it out — I never
  silently merge or guess.
- You can force a specific action to win outright with `:force t`,
  regardless of priority.

#### Step 4: Ordering

I sort what's left into an execution order. Mostly that's just the order
things appeared, but if you wrote `:depends-on` on an action, I make sure
its dependency runs first. I do one topological pass over the whole set —
if you've built a cycle, I'll tell you exactly which actions are involved.

#### Step 5: Execution

Finally, I run each action's executor, one at a time, in that order.
Every executor understands three modes:

- **`:apply`** — actually change the system.
- **`:check`** — tell me what *would* change, and touch nothing. This is
  what powers `ldl plan`, `ldl check`, `ldl diff`, and `--dry-run`.
- **`:remove`** — undo the action. This only ever runs when you've marked
  an action `:disabled t` *and* your home has the
  `:prune-explicitly-disabled` trait — deletion is always something you
  opt into, never a side effect.

Every built-in executor is written to be **idempotent**: running it twice
produces the same result as running it once. I don't keep a separate
"what did I do last time" state file to diff against — each executor
simply checks the real system and only acts if something's actually wrong.
That also means there's no rollback. If something fails partway through, I
stop, tell you exactly what broke, and you fix it and run me again. I
converge you toward the goal; I don't try to undo history.

### Why the ordering (0→1→2) actually matters

Here's the thing that confuses almost everyone once: `home.lisp` gets
*loaded* in step 0, before facts exist, but its body only *runs* in step 2,
after facts exist. That's because `define-home` doesn't evaluate its body
immediately — it wraps it up and hands it to me to run later. So this is
completely safe, even though it looks like it shouldn't be:

```lisp
;; home.lisp -- loaded in step 0, when no facts exist yet
(define-home my-home
  (when (fact :laptop-p)          ; not evaluated until step 2
    (use-feature :power-management)))
```

By the time that `when` actually runs, I've already probed facts and
merged your profile. You never have to think about this consciously —
just know that if you see `home.lisp` being *loaded* early in verbose
output, that's normal, and it's not a bug.

### What I will never ask you to do

- **No variables.** You never bind or `setf` anything in the DSL. State
  comes from Facts (and Profiles), full stop.
- **No custom control flow.** `when`/`unless`/`if`/`cond` and friends are
  the entire vocabulary. I don't add a `ldl-if` or a `ldl-loop`.
- **No silent deletion.** I only ever remove something you explicitly
  marked `:disabled t`, and only if your home opted into
  `:prune-explicitly-disabled`.
- **No rollback.** I converge forward. Re-running me is always safe and
  is always the answer when something goes wrong mid-run.

---


---

Next: [How I Am Built](03-how-i-am-built.md) goes one level deeper, into
the actual source layout and extensibility points behind this model. Or
skip straight to the [Reference](04-reference.md) for every keyword and
CLI option.
