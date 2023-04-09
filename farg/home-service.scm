(define-module (farg home-service)
  #:use-module (guix gexp)
  #:use-module (srfi srfi-1)
  #:use-module (gnu home services)
  #:use-module (gnu home services shells)
  #:use-module (gnu services configuration)
  #:use-module (farg source)
  #:use-module (farg packages)
  #:export (
            home-farg-service-type
            home-farg-configuration
            home-farg-configuration?
            <home-farg-configuration>

            home-farg-configuration-source
            home-farg-configuration-activation-commands))

(define-configuration
  home-farg-configuration
  (source
   (farg-source (farg-source))
   "The farg source generated by a source generator.")
  (activation-commands
   (list '())
   "List of commands to run when the new home environment has been activated.
This can be used to update currently running applications, e.g. pywalfox.")
  (no-serialization))

(define (home-farg-files-service config)
  (farg-source-files (home-farg-configuration-source config)))

(define (home-farg-profile-service config)
  (farg-source-packages (home-farg-configuration-source config)))

(define (home-farg-environment-variables-service config)
  (farg-source-env-vars (home-farg-configuration-source config)))

(define (home-farg-activation-service config)
  #~(begin
      (display "Activating colorscheme...\n")
      #$@(home-farg-configuration-activation-commands config)))

(define (home-farg-extensions original-config extensions)
  (let ((extensions (reverse extensions)))
    (home-farg-configuration
     (inherit original-config)
     (activation-commands
      (fold append '()
            (append (home-farg-configuration-activation-commands original-config)
                    extensions))))))

(define home-farg-service-type
  (service-type
   (name 'home-farg)
   (extensions
    (list
     (service-extension
      home-files-service-type
      home-farg-files-service)
     (service-extension
      home-profile-service-type
      home-farg-profile-service)
     (service-extension
      home-environment-variables-service-type
      home-farg-environment-variables-service)
     (service-extension
      home-activation-service-type
      home-farg-activation-service)))
   (compose identity)
   (extend home-farg-extensions)
   (default-value (home-farg-configuration))
   (description "Persist generated colorscheme.")))
