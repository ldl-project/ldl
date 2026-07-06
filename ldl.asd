;;;; ldl.asd
;;;;
;;;; ASDF system definition for the LDL core: an explicit :components list,
;;;; not the directory-convention auto-discovery LDL itself implements for a
;;;; user's home project. The core can't bootstrap via its own Discovery
;;;; mechanism, so its own file layout is ordinary, hand-listed ASDF.
;;;;
;;;; Usage:
;;;;   Register this directory and load the system from any Lisp image:
;;;;
;;;;     (push #P"/path/to/ldl/" asdf:*central-registry*)
;;;;     (asdf:load-system :ldl)
;;;;
;;;;   Force a full rebuild after pulling changes or editing files outside
;;;;   the running image (see docs/user_manual.md):
;;;;
;;;;     (asdf:load-system :ldl :force t)

(defsystem "ldl"
  :description "Lisp Declarative Linux -- declarative Linux home environment management"
  :version "4.3.0"
  :depends-on ("asdf" "uiop")
  :serial t
  :components
  ((:module "src"
    :serial t
    :components
    ((:file "package")
     (:file "conditions")
     (:file "log")
     (:file "discovery")
     (:file "facts")
     (:file "profiles")
     (:file "catalogs")
     (:file "features")
     (:file "providers")
     (:file "actions")
     (:file "secrets")
     (:file "templates")
     (:module "action-types"
      :serial t
      :components
      ((:file "package")
       (:file "helpers")
       (:file "copy-file")
       (:file "ensure-dir")
       (:file "symlink")
       (:file "service")
       (:file "timer")
       (:file "env-var")
       (:file "config-lines")
       (:file "config-ini")
       (:file "config-env")
       (:file "package-action")
       (:file "secret")
       (:file "user")
       (:file "group")
       (:file "authorized-key")
       (:file "permissions")
       (:file "mount")
       (:file "sysctl")
       (:file "kernel-module")
       (:file "hostname")
       (:file "locale")
       (:file "firewall")
       (:file "cron")
       (:file "command")))
     (:file "pipeline")
     (:file "privilege")
     (:file "dsl")
     (:file "cli")))))
