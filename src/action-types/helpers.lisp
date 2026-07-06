;;;; src/action-types/helpers.lisp
;;;;
;;;; Shared utilities used by the built-in action executors: path/home
;;;; expansion, reading and writing files, POSIX mode/owner/group
;;;; inspection and mutation, running a command with or without sudo
;;;; escalation, a privileged-file-write helper for root-owned paths, and
;;;; the REPORT macro every executor uses to build its return value.

(in-package :ldl.core)

(defun expand-home (path)
  "Expand a leading ~ to the invoking user's home directory."
  (let ((home (or (uiop:getenv "HOME") "/")))
    (if (and (> (length path) 0) (char= (char path 0) #\~))
        (concatenate 'string home (subseq path 1))
        path)))

(defun read-file-string (path)
  (when (probe-file path)
    (uiop:read-file-string path)))

(defun write-file-string (path content)
  (ensure-directories-exist path)
  (with-open-file (f path :direction :output :if-exists :supersede :if-does-not-exist :create)
    (write-string content f)))

(defun file-mode (path)
  "Best-effort POSIX permission bits for PATH, or nil if unavailable."
  (ignore-errors
   (parse-integer
    (string-trim '(#\Newline #\Space)
                 (uiop:run-program (list "stat" "-c" "%a" (namestring path))
                                    :output '(:string :stripped t)))
    :radix 8)))

(defun set-file-mode (path mode)
  (when mode
    (ignore-errors
     (uiop:run-program (list "chmod" (format nil "~o" mode) (namestring path))))))

(defun set-file-owner (path owner group)
  (when (or owner group)
    (ignore-errors
     (uiop:run-program
      (list "chown" (format nil "~a:~a" (or owner "") (or group "")) (namestring path))))))

(defun resolve-owner (action)
  "Per spec: :owner defaults to the calling (non-root) user, even under sudo."
  (or (getf action :owner) (or (uiop:getenv "SUDO_USER") (uiop:getenv "USER"))))

(defun resolve-group (action)
  (or (getf action :group)
      (ignore-errors
       (string-trim '(#\Newline)
                     (uiop:run-program (list "id" "-gn") :output '(:string :stripped t))))))

(defun apply-file-ownership (path action)
  (set-file-mode path (getf action :mode))
  (set-file-owner path (resolve-owner action) (resolve-group action)))

(defun run-privileged (args)
  "Run a command, prefixing with sudo unless already privileged."
  (let ((cmd (if (privileged-p) args (cons "sudo" args))))
    (uiop:run-program cmd :output t :error-output t :ignore-error-status t)))

(defun write-privileged-file (path content)
  "Write CONTENT to PATH, elevating via sudo if necessary. Writes to a
scratch file as the invoking user first, then copies it into place with
one privileged command, rather than requiring the whole LDL process to
run as root just to open a root-owned path directly."
  (if (privileged-p)
      (write-file-string path content)
      (let ((tmp (format nil "/tmp/ldl-write-~a" (random 1000000))))
        (write-file-string tmp content)
        (run-privileged (list "cp" tmp path))
        (ignore-errors (delete-file tmp)))))

(defun shell-ok-p (command)
  "T if COMMAND exits zero when run through /bin/sh, without emitting its
output to the terminal. Used for :only-if / :unless idempotency checks and
backend-detection probes."
  (zerop (nth-value 2 (uiop:run-program (list "sh" "-c" command) :ignore-error-status t))))

(defun which (program)
  "T if PROGRAM is found on PATH."
  (shell-ok-p (format nil "command -v ~a >/dev/null 2>&1" program)))

(defmacro report (status &rest kvs)
  "Build a uniform executor return value: a plist with :status plus extras."
  `(list :status ,status ,@kvs))
