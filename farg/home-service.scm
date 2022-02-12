(define-module (farg home-service)
  #:use-module (guix gexp)
  #:use-module (gnu home services)
  #:use-module (gnu home services shells)
  #:use-module (gnu services configuration)
  #:use-module (farg utils)
  #:use-module (farg config)
  #:use-module (farg colorscheme)
  #:export (home-farg-service-type))

(define-configuration
  home-farg-configuration
  (colorscheme
   (colorscheme)
   "The generated colorscheme.")
  (config
   (farg-config)
   "The farg configuration.")
  (no-serialization))

(define (home-farg-environment-variables-service config)
  (define (serialize-string str)
    (if str str ""))

  (define (serialize-boolean bool)
    (if bool 1 0))

  (let* ((colorscheme (home-farg-configuration-colorscheme config))
         (farg (home-farg-configuration-config config))
         (wallpaper (colorscheme-wallpaper colorscheme))
         (backend (farg-config-backend farg))
         (saturation (farg-config-saturation farg))
         (light? (farg-config-light? farg)))
    ;; Save pywal settings to make sure that we only re-generate colors if
    ;; these settings change. This will help speed up the reconfiguration.
    `(("GUIX_FARG_WALLPAPER" . ,(serialize-string wallpaper))
      ("GUIX_FARG_BACKEND" . ,(serialize-string backend))
      ("GUIX_FARG_SATURATION" . ,saturation)
      ("GUIX_FARG_LIGHT" . ,(serialize-boolean backend)))))

;; TODO: Move generated pywal files from /tmp/
(define (home-farg-files-service config)
  '())

(define (home-farg-activation-service config)
  #~(begin
      (display "Activating colorscheme...")
      #$(farg-config-activation-commands config)))

;; TODO: Add pywal as a profile dependency?
(define home-farg-service-type
  (service-type
   (name 'home-farg)
   (extensions
    (list
     (service-extension
      home-environment-variables-service-type
      home-farg-environment-variables-service)
     (service-extension
      home-files-service-type
      home-farg-files-service)
     (service-extension
      home-activation-service-type
      home-farg-activation-service)))
   (description "Persist generated colorscheme.")))
