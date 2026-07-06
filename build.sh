# Most clean installations or new users do have a local bin.
mkdir ~/.local/bin/

# Build ldl and store in bin.
sbcl \
  --eval '(require :asdf)' \
  --eval '(push #P"./" asdf:*central-registry*)' \
  --eval '(asdf:load-system :ldl :force t)' \
  --eval '(sb-ext:save-lisp-and-die
             "ldl"
             :executable t
             :toplevel
             (lambda ()
               (ldl.core:main (rest sb-ext:*posix-argv*))))' \
&& ln -sf "$PWD/ldl" ~/.local/bin/ldl

# Show ldl functions
clear
ldl
