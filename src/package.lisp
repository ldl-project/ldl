;;;; src/package.lisp
;;;;
;;;; Package definitions for the three packages LDL's core is split across:
;;;;
;;;;   :ldl.core       -- the engine, DSL, and CLI (everything else in src/)
;;;;   :ldl.log        -- the small leveled-logging facility
;;;;   :ldl-templates  -- where a project's own RENDER-* template functions live
;;;;
;;;; This is the first file loaded (see ldl.asd), so every other file in the
;;;; system can assume these packages, and everything :ldl.core exports,
;;;; already exist.

(defpackage :ldl.log
  (:use :cl)
  (:export #:info #:debug* #:warn* #:error* #:set-verbosity #:*verbosity*))

(defpackage :ldl.core
  (:use :cl)
  (:shadow #:package #:directory)
  (:export
   ;; conditions
   #:ldl-error
   #:missing-provider
   #:action-conflict
   #:insufficient-privileges
   #:permission-denied-mid-run
   #:non-interactive-prompt
   #:fact-prober-conflict
   #:missing-template-renderer
   #:execution-failure
   #:file-discovery-load-error
   #:pipeline-aborted-by-hook
   #:dependency-cycle
   #:retry #:skip #:abort-processing
   #:use-first #:use-second
   #:specify-provider #:skip-feature
   #:retry-with-sudo
   #:supply-value
   #:specify-renderer #:treat-as-static

   ;; facts / profiles
   #:register-fact-prober
   #:probe-all-facts
   #:fact
   #:*facts*
   #:define-profile
   #:*profiles*
   #:apply-profile

   ;; catalogs
   #:define-catalog
   #:register-catalog
   #:catalog-lookup

   ;; features / providers
   #:define-feature
   #:*feature-registry*
   #:register-provider
   #:find-provider
   #:find-providers-for
   #:resolve-feature-graph

   ;; actions
   #:make-action
   #:action-type
   #:action-target
   #:action-plist
   #:action-identity
   #:register-action-type
   #:find-executor
   #:execute-action
   #:dedup-actions
   #:order-actions

   ;; secrets / templates
   #:resolve-secret
   #:render-template

   ;; pipeline
   #:register-pipeline-hook
   #:run-pipeline
   #:*pipeline-hooks*

   ;; privilege
   #:privileged-p
   #:preflight-check

   ;; discovery
   #:discover-project
   #:discover-plugins

   ;; dsl
   #:define-home
   #:use-feature
   #:file
   #:directory
   #:symlink
   #:package
   #:secret
   #:env-var
   #:config-lines
   #:config-ini
   #:config-env
   #:direct-action
   #:user
   #:group
   #:authorized-key
   #:permissions
   #:mount
   #:sysctl
   #:kernel-module
   #:hostname
   #:locale
   #:firewall
   #:cron
   #:command
   #:*current-home-actions*
   #:*current-home-name*
   #:*current-home-traits*

   ;; cli
   #:main))

(defpackage :ldl-templates
  (:use :cl)
  (:export))
