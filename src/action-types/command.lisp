;;;; src/action-types/command.lisp
;;;;
;;;; The :command executor, the final escape hatch. Runs a raw shell
;;;; command, but only when its own idempotency check (:creates / :unless /
;;;; :only-if) says it's needed; with none given, it honestly reports the
;;;; command as always needing to run rather than guessing.
;;;;
;;;; Usage:
;;;;     (:action :command :target "clone dotfiles" :run "git clone ... ~/.dotfiles" :creates "~/.dotfiles")

(in-package :ldl.core)

(defun command-needed-p (action)
  (cond
    ((getf action :creates) (not (probe-file (expand-home (getf action :creates)))))
    ((getf action :unless) (not (shell-ok-p (getf action :unless))))
    ((getf action :only-if) (shell-ok-p (getf action :only-if)))
    (t t)))

(defun execute-command (action &key mode)
  (let* ((name (action-target action))
         (needed (command-needed-p action)))
    (case mode
      (:check (report (if needed :would-change :unchanged) :target name))
      (:apply
       (when needed (uiop:run-program (list "sh" "-c" (getf action :run)) :output t :error-output t))
       (report (if needed :changed :unchanged) :target name))
      (:remove
       (when (getf action :remove-run)
         (uiop:run-program (list "sh" "-c" (getf action :remove-run)) :output t :error-output t :ignore-error-status t))
       (report :removed :target name)))))

(register-action-type :command #'execute-command
  :description "Run a raw shell command, gated by a :creates/:unless/:only-if idempotency check")
