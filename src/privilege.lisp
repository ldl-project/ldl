;;;; src/privilege.lisp
;;;;
;;;; Privilege detection and the pre-apply preflight check: aborts an :apply
;;;; run up front, before any action executes, if the plan contains a
;;;; :package install that will actually need root and the process doesn't
;;;; have it. A Flatpak install explicitly scoped :user is deliberately
;;;; excluded from this check, since it never escalates privileges either.
;;;;
;;;; Usage:
;;;;     (privileged-p)                     ; => T if effectively root
;;;;     (preflight-check ordered-actions)  ; signals INSUFFICIENT-PRIVILEGES if needed

(in-package :ldl.core)

(defun current-uid ()
  (ignore-errors
   (parse-integer
    (string-trim '(#\Newline)
                 (uiop:run-program (list "id" "-u") :output '(:string :stripped t))))))

(defun privileged-p ()
  "T if the current process can install packages (effectively root)."
  (eql (current-uid) 0))

(defun action-needs-privilege-p (action)
  "T if ACTION is a :package install that will actually need root. Every
:package via is privileged EXCEPT a Flatpak install explicitly scoped
:user -- that one deliberately never escalates (see package-action.lisp),
so it shouldn't force a `sudo ldl apply` requirement on its own."
  (and (eq (action-type action) :package)
       (not (and (eq (getf action :via) :flatpak) (eq (getf action :scope :system) :user)))))

(defun preflight-check (ordered-actions)
  "Per the spec: before :apply executes any action, abort immediately (with
no actions executed) if the plan contains any privileged :package action
and the process lacks privileges to install packages."
  (let ((pkg-count (count-if #'action-needs-privilege-p ordered-actions)))
    (when (and (> pkg-count 0) (not (privileged-p)))
      (error 'insufficient-privileges :count pkg-count))))
