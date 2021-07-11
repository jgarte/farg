(define-module (farg)
               #:use-module (guix ui)
               #:use-module (ice-9 match)
               #:use-module (ice-9 format)
               #:use-module (ice-9 getopt-long))

(define %version "0.0.1")

(define option-spec
  '((version (single-char #\v) (value #f))
    (help    (single-char #\h) (value #f))))

(define (show-help)
  (display (G_ "Usage: farg ACTION [ARG ...] [FILE]\n\n"))
  (display
    (G_
      (string-append " A system colorscheme manager" " - " "version" " " %version "\n\n")))
  (display (G_ "The valid values for ACTION are:\n"))
  (display (G_ "   generate    generate a colorscheme for FILE using pywal\n"))
  (display (G_ "   export      export generated colorscheme\n"))
  (display (G_ "   import      import an exported colorscheme\n")))

(define (show-invalid-action action)
  (display (G_ (string-append "Invalid action '" action "'"))))

(define (main args)
  (let* ((option-spec '((version (single-char #\v) (value #f))
                        (help    (single-char #\h) (value #f))))
         (options (getopt-long args option-spec))
         (help-wanted (option-ref options 'help #f))
         (version-wanted (option-ref options 'version #f)))
    (if (or version-wanted help-wanted)
        (begin
          (if help-wanted (show-help) (display %version))
          (newline))
        (begin
          (match (list-tail args 1) ; skip filename arg
                 (("generate") (display "lets generate"))
                 (("import") (display "lets import"))
                 (("export") (display "lets export"))
                 ((action) (show-invalid-action action))
                 (() (show-help)))
          (newline)))))

(main (command-line))
