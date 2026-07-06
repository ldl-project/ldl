;;;; src/facts.lisp
;;;;
;;;; Fact prober registration and probing. A Fact is a probed or
;;;; profile-overridden truth about the current machine (:os, :hostname,
;;;; :laptop-p, :display-server, and anything a provider author adds);
;;;; *FACTS* holds the resolved plist for the current run.
;;;;
;;;; Usage:
;;;;   Reading a fact, from inside a home definition or a provider:
;;;;
;;;;     (fact :laptop-p)
;;;;
;;;;   Registering a new one, typically from a project's providers/ file:
;;;;
;;;;     (register-fact-prober :gpu (lambda () (if (probe-file "...") :nvidia :unknown)))

(in-package :ldl.core)

(defvar *fact-probers* (make-hash-table :test 'eq)
  "Maps fact key -> (prober-function . registrant-name).")

(defvar *facts* nil
  "Plist of resolved facts, populated by PROBE-ALL-FACTS and merged with
a profile's overrides. Read via FACT.")

(defun register-fact-prober (key prober-fn &optional (registrant (package-name *package*)))
  "Register a fact prober for KEY. If a different registrant already
registered a prober for the same KEY, signal FACT-PROBER-CONFLICT and abort
startup -- there is no implicit first-one-wins resolution."
  (let ((existing (gethash key *fact-probers*)))
    (when (and existing (not (string= (cdr existing) registrant)))
      (error 'fact-prober-conflict
             :fact-key key
             :registrants (list (cdr existing) registrant)))
    (setf (gethash key *fact-probers*) (cons prober-fn registrant)))
  key)

(defun default-fact-probers ()
  "Register the small set of built-in facts LDL always probes."
  (register-fact-prober :os #'probe-os "ldl-core")
  (register-fact-prober :hostname (lambda () (or (uiop:hostname) "unknown")) "ldl-core")
  (register-fact-prober :laptop-p #'probe-laptop-p "ldl-core")
  (register-fact-prober :display-server #'probe-display-server "ldl-core"))

(defun probe-os ()
  (cond
    ((probe-file "/etc/fedora-release") :fedora)
    ((probe-file "/etc/arch-release") :arch)
    ((probe-file "/etc/debian_version") :debian)
    ((probe-file "/etc/os-release")
     (handler-case
         (with-open-file (f "/etc/os-release")
           (loop for line = (read-line f nil nil)
                 while line
                 when (and (>= (length line) 3) (string= line "ID=" :end1 3))
                   do (return (intern (string-upcase (string-trim "\"" (subseq line 3))) :keyword))
                 finally (return :unknown)))
       (error () :unknown)))
    (t :unknown)))

(defun probe-laptop-p ()
  (and (probe-file "/sys/class/power_supply/BAT0") t))

(defun probe-display-server ()
  (cond
    ((uiop:getenv "WAYLAND_DISPLAY") :wayland)
    ((uiop:getenv "DISPLAY") :x11)
    (t nil)))

(defun probe-all-facts ()
  "Run every registered fact prober once and populate *FACTS*."
  (let ((result '()))
    (maphash (lambda (key entry)
               (setf result (list* key (funcall (car entry)) result)))
             *fact-probers*)
    (setf *facts* result)))

(defun fact (key)
  "Read a fact by keyword. Reflects probed values merged with any
profile override -- the home definition cannot distinguish the two."
  (getf *facts* key))
