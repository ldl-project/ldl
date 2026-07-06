;;;; src/features.lisp
;;;;
;;;; Feature definitions and dependency-graph resolution. A Feature is a
;;;; named capability (:editor, :docker, ...) with an optional list of other
;;;; features it :requires; RESOLVE-FEATURE-GRAPH walks that DAG starting
;;;; from a home definition's USE-FEATURE calls, dependencies first.
;;;;
;;;; Usage:
;;;;     (define-feature :editor :description "Text editor capability" :requires nil)

(in-package :ldl.core)

(defstruct feature
  name
  description
  tags
  provides
  requires)

(defvar *feature-registry* (make-hash-table :test 'eq)
  "Maps feature name (keyword) -> FEATURE struct.")

(defmacro define-feature (name &key description tags provides requires)
  "All of DESCRIPTION, TAGS, PROVIDES, and REQUIRES are taken as literal
data at macroexpansion time (consistent with the rest of the DSL) -- e.g.
:requires (:terminal :fonts) is a literal list of feature names, not code
to evaluate."
  `(setf (gethash ,name *feature-registry*)
         (make-feature :name ,name :description ',description
                        :tags ',tags :provides ',provides :requires ',requires)))

(defun feature-by-name (name)
  (or (gethash name *feature-registry*)
      (error 'missing-provider :feature name
             :message (format nil "No feature named ~a is registered." name))))

(defun resolve-feature-graph (root-names)
  "Given the list of top-level feature names requested via USE-FEATURE,
recursively resolve :requires, returning an ordered list of feature names
(dependencies before dependents), duplicates removed. Detects cycles."
  (let ((visited (make-hash-table :test 'eq))
        (visiting (make-hash-table :test 'eq))
        (order '()))
    (labels ((visit (name path)
               (cond
                 ((gethash name visited) nil)
                 ((gethash name visiting)
                  (error 'dependency-cycle :cycle (reverse (cons name path))))
                 (t
                  (setf (gethash name visiting) t)
                  (let ((f (feature-by-name name)))
                    (dolist (dep (feature-requires f))
                      (visit dep (cons name path))))
                  (remhash name visiting)
                  (setf (gethash name visited) t)
                  (push name order)))))
      (dolist (name root-names)
        (visit name nil)))
    (nreverse order)))
