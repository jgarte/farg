(define-module (farg home-service)
  #:use-module (ice-9 match)
  #:use-module (srfi srfi-1)
  #:use-module (guix gexp)
  #:use-module (gnu home services)
  #:use-module (gnu home services shells)
  #:use-module (gnu services configuration)
  #:use-module (gnu packages imagemagick)
  #:use-module (farg utils)
  #:use-module (farg picker)
  #:use-module (farg config)
  #:use-module (farg packages)
  #:use-module (farg colorscheme)
  #:export (
            home-farg-service-type
            home-farg-configuration
            home-farg-configuration?
            <home-farg-configuration>

            home-farg-configuration-colorscheme
            home-farg-configuration-config

            modify-farg-config))

(define-configuration
  home-farg-configuration
  (colorscheme
   (colorscheme (colorscheme))
   "The generated colorscheme")
  (config
   (farg-config (farg-config))
   "The farg configuration.")
  (no-serialization))

(define (home-farg-environment-variables-service config)
  (let* ((colorscheme (home-farg-configuration-colorscheme config))
         (farg (home-farg-configuration-config config))
         (wallpaper (colorscheme-wallpaper colorscheme))
         (backend (farg-config-backend farg))
         (saturation (farg-config-saturation farg))
         (light? (farg-config-light? farg)))
    `(
      ;; Make guix aware of `guix colorscheme` after first reconfigure.
      ;; Potentially dangerous "fix", it makes possible for malicious channel
      ;; expose it's own guix subcommands.
      ("GUILE_LOAD_PATH" . "$XDG_CONFIG_HOME/guix/current/share/guile/site/3.0:$GUILE_LOAD_PATH")
      ("GUILE_LOAD_COMPILED_PATH" . "$XDG_CONFIG_HOME/guix/current/lib/guile/3.0/site-ccache:$GUILE_LOAD_COMPILED_PATH")

      ;; Save pywal settings to make sure that we only re-generate colors if
      ;; these settings change. This will help speed up the reconfiguration.
      ("GUIX_FARG_WALLPAPER" . ,(serialize-string wallpaper))
      ("GUIX_FARG_BACKEND" . ,(serialize-string backend))
      ("GUIX_FARG_SATURATION" . ,(number->string saturation))
      ("GUIX_FARG_LIGHT" . ,(serialize-boolean light?)))))

(define (remove-home-path-prefix path)
  (if (and (eq? (string-contains path "/home/") 0)
           (> (string-length path) 7))
      (substring path (+ 1 (string-index path #\/ 6)))
      path))

(define (home-farg-files-service config)
  (define (copy-exported-file from-dir to-dir name)
    (let ((out (string-append to-dir "/" name))
          (in (string-append from-dir "/" name)))
      (if (file-exists? in)
          `(,out ,(local-file in))
          #f)))

  (let* ((fconfig (home-farg-configuration-config config))
         (wallpaper-path (farg-config-wallpaper-search-directory fconfig)))
    `(,@(filter-map
         (lambda (f)
           (copy-exported-file
            (farg-config-temporary-directory fconfig)
            (remove-home-path-prefix (farg-config-colors-directory fconfig))
            f))
         (farg-config-color-files fconfig))
      (".config/farg/picker.scm"
       ,(program-file "farg-picker.scm"
                        (sxiv-wallpaper-picker wallpaper-path))))))

(define (home-farg-activation-service config)
  #~(begin
      (display "Activating colorscheme...\n")
      #$@(farg-config-activation-commands (home-farg-configuration-config config))))

(define (home-farg-profile-service config)
  (list python-pywal-farg))

(define (home-farg-extension old-config extend-proc)
  (extend-proc old-config))

(define-syntax modify-farg-config
  (syntax-rules (=>)
    ((_ (param => new-config))
     (lambda (old-config)
       (let ((param (home-farg-configuration-config old-config)))
         (home-farg-configuration
          (inherit old-config)
          (config new-config)))))))

(define home-farg-service-type
  (service-type
   (name 'home-farg)
   (extensions
    (list
     (service-extension
      home-profile-service-type
      home-farg-profile-service)
     (service-extension
      home-environment-variables-service-type
      home-farg-environment-variables-service)
     (service-extension
      home-files-service-type
      home-farg-files-service)
     (service-extension
      home-activation-service-type
      home-farg-activation-service)))
   ;; Each extension will override the previous config
   ;; with its own, generally by inheriting the old config
   ;; and then adding their own updated values.
   ;;
   ;; Composing the extensions is done by creating a new procedure
   ;; that accepts the service configuration and then recursively
   ;; call each extension procedure with the result of the previous extension.
   (compose (lambda (extensions)
              (match extensions
                (() identity)
                ((procs ...)
                 (lambda (old-config)
                   (fold-right (lambda (p extended-config) (p extended-config))
                               old-config
                               extensions))))))
   (extend home-farg-extension)
   (default-value (home-farg-configuration))
   (description "Persist generated colorscheme.")))
