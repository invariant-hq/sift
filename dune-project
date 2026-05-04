(lang dune 3.22)

(name sift)

(generate_opam_files true)

(authors "Thibaut Mattio <thibaut.mattio@gmail.com>")

(maintainers "Thibaut Mattio <thibaut.mattio@gmail.com>")

(license ISC)

(implicit_transitive_deps false)

(pin
 (url "git+https://github.com/invariant-hq/mosaic.git")
 (package
  (name tree-sitter)))

(pin
 (url "git+https://github.com/invariant-hq/mosaic.git")
 (package
  (name matrix)))

(pin
 (url "git+https://github.com/invariant-hq/mosaic.git")
 (package
  (name toffee)))

(pin
 (url "git+https://github.com/invariant-hq/mosaic.git")
 (package
  (name mosaic)))

(package
 (name sift)
 (synopsis "Diff-based code review TUI")
 (description
  "Sift is an experimental diff-based code review TUI built with Mosaic. It models review around a feature, the diff from a base revision to a tip revision.")
 (depends
  (ocaml
   (>= 5.1))
  mosaic
  (windtrap :with-test))
 (tags
  (code-review diff tui terminal)))
