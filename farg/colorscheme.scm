(define-module (farg colorscheme)
  #:use-module (farg utils)
  #:use-module (farg config)
  #:use-module (farg packages)
  #:use-module (srfi srfi-1)
  #:use-module (ice-9 match)
  #:use-module (ice-9 popen)
  #:use-module (ice-9 rdelim)
  #:use-module (ice-9 exceptions)
  #:use-module (gnu services configuration)
  #:export (
            colorscheme
            <colorscheme>
            colorscheme?
            colorscheme-alpha
            colorscheme-light?
            colorscheme-wallpaper
            colorscheme-text
            colorscheme-primary
            colorscheme-primary-text
            colorscheme-secondary
            colorscheme-secondary-text
            colorscheme-background
            colorscheme-raw

            maybe-colorscheme?

            hex->hsl
            hex->rgba
            hex->luminance
            rgba->luminance
            rgba->hex
            rgba->hsl
            hsl->hex
            hsl->rgba

            set-alpha
            with-alpha
            with-filters
            adjust-hue
            adjust-saturation
            adjust-lightness

            lighten
            darken
            brighten
            saturate
            desaturate
            offset
            blend
            make-readable
            contrast

            rgba:contrast

            hsl:contrast
            hsl:lighten
            hsl:darken
            hsl:brighten
            hsl:saturate
            hsl:desaturate

            colors->colorscheme
            generate-colorscheme
            read-colorscheme))

;; TODO: Add function for finding color with contrast ratio

;; TODO: Add guix command for choosing a wallpaper and using it in the
;;       colorscheme generation before running a reconfigure, e.g.
;;       'guix colorscheme'. It can be saved as an environment variable or file
;;       when generating the home environment. When running a regular reconfigure,
;;       the environment variable can be read and applied appropriately.

;; TODO: How should we handle themes? Some wallpapers must be adjusted
;;       to look good. This should be done using some configuration option.

;; TODO: Is it possible to generate two home environments? One for light and one
;;       for dark colorschemes. This way you can easily switch between light and dark
;;       using e.g. 'guix colorscheme light', 'guix colorscheme dark'.

;; TODO: Save wallpaper to store.
(define-configuration
  colorscheme
  (alpha
   (number 1.0)
   "Default transparency for the colorscheme (0-1).")
  (light?
   (boolean #f)
   "If the colorscheme is a light theme")
  (wallpaper
   (maybe-string #f)
   "Colorscheme wallpaper")
  (primary
   (string "")
   "Primary accent color")
  (secondary
   (string "")
   "Secondary accent color")
  (text
   (string "")
   "Main text color")
  (primary-text
   (string "")
   "Primary accent complementary text color")
  (secondary-text
   (string "")
   "Secondary accent complementary text color")
  (background
   (string "")
   "Main background color")
  (raw
   (list '())
   "Raw colors read from the generated colors file.")
  (no-serialization))

(define (maybe-colorscheme? x)
  (or (boolean? x) (colorscheme? x)))

(define (generate-colorscheme wallpaper config output-path)
  (define colorscheme-saturation
    (let ((saturation (farg-config-saturation config)))
      (if (procedure? saturation)
          (saturation (farg-config-light? config))
          saturation)))

  (begin
    (let ((home-service-activated? (getenv "GUIX_FARG_WALLPAPER"))
          (is-root? (equal? (geteuid) 0)))
    ;; HACK: Manually install wal if this is the first time you run farg.
    ;; This is not needed to get access to the wal binary, but rather to ensure
    ;; that wal can access the imagemagick binary.
    (when (and (not home-service-activated?) (not is-root?))
      (system "guix install python-pywal-farg"))
    (display "Generating colorscheme...\n")
    (system
     (string-join
      (list (string-append "PYWAL_CACHE_DIR=" output-path)
            "$(guix build python-pywal-farg)/bin/wal"
            "-i" wallpaper
            "--backend" (farg-config-backend config)
            "--saturate" (number->string colorscheme-saturation)
            (if (farg-config-light? config) "-l" "")
            ;; Skip reloading
            ;; TODO: Add option for not skipping reloading
            "-e" "-t" "-s" "-n"
            ;; Disable output
            "-q")
      " "))
    ;; Remove again, since it is being added via the home service
    (when (and (not home-service-activated?) (not is-root?))
      (system "guix remove python-pywal-farg"))
    (read-colorscheme output-path))))

(define* (read-colorscheme path)
  "Read generated colors from PATH."
  (define (read-colors port acc index)
    (let ((color (read-line port)))
      (if (eof-object? color)
          acc
          (read-colors port
                       (cons `(,index . ,color) acc)
                       (+ index 1)))))

  (read-colors (open-input-file (string-append path "/colors")) '() 0))

(define* (colors->colorscheme wallpaper colors config)
  "Converts a list of generated colors into a colorscheme record."
  ;; TODO: Correctly set primary and secondary text.
  ;; TODO: Generate extra color for light theme background
  (define colorscheme-alpha
    (let ((alpha (farg-config-alpha config)))
      (if (procedure? alpha)
          (alpha (farg-config-light? config))
          alpha)))

  (let ((background (assoc-ref colors 0))
        (primary (assoc-ref colors 8))
        (secondary (assoc-ref colors 9)))
    (colorscheme
     (alpha colorscheme-alpha)
     (light? (farg-config-light? config))
     (wallpaper wallpaper)
     (primary (assoc-ref colors 10))
     (secondary (assoc-ref colors 13))
     (text (assoc-ref colors 15))
     (background background)
     (primary-text (make-readable primary background))
     (secondary-text (make-readable secondary background))
     (raw colors))))

(define* (set-alpha prev new)
  "Mirrors the alpha channel of PREV to NEW. If NEW has an alpha
channel, but PREV does not, it will be removed."
  (let ((prev-alpha? (eq? (string-length prev) 9))
        (new-alpha? (eq? (string-length new) 9)))
    (cond
     ((and (not prev-alpha?) new-alpha?) (string-drop-right new 2))
     ((and prev-alpha? (not new-alpha?)) (string-append new (string-take-right prev 2)))
     (else new))))

(define* (with-alpha hex alpha)
  "Sets the alpha channel of HEX based on the percentage ALPHA.
If HEX has an alpha set, it will be replaced."
  (let ((new-alpha (format #f "~2,'0x" (inexact->exact (round (* 255.0 (/ alpha 100)))))))
    (if (eq? (string-length hex) 9)
        (string-append (string-take hex 7) new-alpha)
        (string-append hex new-alpha))))

(define* (hex->rgba str #:key (alpha? #f))
  "Converts a hex color STR into its RGBA color representation.
If the hex color does not specify the alpha, it will default to 100%."
  (define (split-rgb acc hex)
    (if (eq? (string-length hex) 0)
        acc
        (split-rgb
         (cons (exact->inexact (/ (string->number (string-take hex 2) 16) 255)) acc)
         (string-drop hex 2))))

  (if (or (not (string? str))
          (eq? (string-length str) 0))
    (raise-exception
     (make-exception-with-message
      (string-append "farg: '" str "' is not a valid hex color.")))
    (let* ((hex (if (equal? (string-take str 1) "#")
                    (substring str 1)
                    str))
           (rgb (split-rgb '() hex))
           (has-alpha? (eq? (length rgb) 4)))
      (reverse
       (if alpha?
           (if has-alpha? (cons 1.0 rgb) rgb)
           (if has-alpha? (list-tail rgb 1) rgb))))))

(define* (hex->hsl hex)
  "Converts a hex color HEX into its HSL color representation.
Conversion of black and white will result in a hue of 0% (undefined)."
  (rgba->hsl (hex->rgba hex)))

;; Based on formula at https://www.myndex.com/WEB/LuminanceContrast.
(define* (hex->luminance hex)
  "Calculates the luminance of hex color HEX."
  (rgba->luminance (hex->rgba hex)))

(define* (rgba->luminance color)
  "Calculates the luminance of COLOR in rgba format."
  (define (calc pair)
    (let ((value (cadr pair)))
      (* (car pair)
         ;; FIXME: Some colors, e.g. #00FF00 or #0000FF will yield complex numbers.
         ;; Not sure how to fix, so just replace it with 0 and be done with it.
         (if (> (imag-part value) 0)
             0
             (expt value 2.2)))))

  (apply + (map calc (zip '(0.2126 0.7152 0.0722) color))))

(define* (rgba->hex rgba #:key (alpha? #f))
  "Converts RGBA into its hex color representation."
  (fold
   (lambda (v acc)
     (string-append
      acc
      (format #f "~2,'0x" (bounded 0 255 (inexact->exact (round (* v 255)))))))
   "#"
   (if (or alpha? (= (length rgba) 3))
       (append rgba '(1.0))
       rgba)))

(define* (rgba->hsl rgba)
  "Converts RGBA into its HSL color representation."
  (define (safe-division x1 x2 denom)
    (if (= denom 0.0)
        0.0
        (/ (- x1 x2) denom)))

  (let* ((c-min (apply min rgba))
         (c-max (apply max rgba))
         (lum (/ (+ c-min c-max) 2))
         (sat (if (<= lum 0.5)
                  (safe-division c-max c-min (+ c-max c-min))
                  (safe-division c-max c-min (- 2.0 c-max c-min))))
         (hue-denom (- c-max c-min))
         (hue (if (= hue-denom 0.0)
                  ;; Hue is undefined in cases where the denominator is 0.
                  0.0
                  (* 60.0
                     (match (list-index (lambda (v) (eq? v c-max)) rgba)
                       ;; Red
                       (0 (safe-division (list-ref rgba 1)
                                         (list-ref rgba 2)
                                         hue-denom))
                       ;; Green
                       (1 (+ (safe-division (list-ref rgba 2)
                                            (list-ref rgba 0)
                                            hue-denom)
                             2.0))
                       ;; Blue
                       (2 (+ (safe-division (list-ref rgba 0)
                                            (list-ref rgba 1)
                                            hue-denom)
                             4.0)))))))
    `(,(if (negative? hue) (+ hue 360) hue) ,sat ,lum)))

(define* (hsl->rgba hsl)
  "Convert HSL into its RGBA color representation."
  (define hue (list-ref hsl 0))
  (define sat (list-ref hsl 1))
  (define lum (list-ref hsl 2))

  (define (normalize-rgb-value v)
    (if (negative? v)
        (+ v 1)
        (if (> v 1) (- v 1) v)))

  (if (= sat 0.0)
      ;; Shade of grey, convert to RGB directly.
      (map (lambda (v) (* v lum)) `(1.0 1.0 1.0))
      (let* ((magic1 (if (< lum 0.5)
                         (* lum (+ 1.0 sat))
                         (- (+ lum sat) (* lum sat))))
             (magic2 (- (* 2.0 lum) magic1))
             (hue-norm (/ hue 360))
             (tmp-r (normalize-rgb-value (+ hue-norm 0.3333)))
             (tmp-g (normalize-rgb-value hue-norm))
             (tmp-b (normalize-rgb-value (- hue-norm 0.3333))))
        (map (lambda (v)
               (cond
                ((< (* 6 v) 1.0) (+ magic2 (* 6.0 v (- magic1 magic2))))
                ((< (* 2 v) 1.0) magic1)
                ((< (* 3 v) 2.0) (+ magic2 (* 6.0 (- 0.6666 v) (- magic1 magic2))))
                (else magic2)))
         (list tmp-r tmp-g tmp-b)))))

(define* (hsl->hex hsl)
  "Converts HSL into its hex color representation."
  (rgba->hex (hsl->rgba hsl)))

;; Based on https://github.com/protesilaos/modus-themes/blob/main/modus-themes.el.
(define* (contrast c1 c2)
  "Calculates the WCAG contrast ratio between the hex colors C1 and C2."
  (rgba:contrast (hex->rgba c1)
                 (hex->rgba c2)))

(define (hsl:contrast c1 c2)
  "Calculates the WCAG contrast ratio between the HSL colors C1 and C2."
  (rgba:contrast (hsl->rgba c1)
                 (hsl->rgba c2)))

(define (rgba:contrast c1 c2)
  "Calculates the WCAG contrast ratio between the RGBA colors C1 and C2."
  (let ((ct (/ (+ (rgba->luminance c1) 0.05)
               (+ (rgba->luminance c2) 0.05))))
    (if (> (imag-part ct) 0)
        0
        (max ct (/ ct)))))

(define* (bounded lower upper value)
  "Bounds VALUE between LOWER and UPPER."
  (min upper (max lower value)))

;; TODO: Combine adjust-* procedures into one.
(define* (adjust-lightness hsl amount proc)
  "Adjusts the lightness of HSL by applying AMOUNT
and current lightness to PROC."
  `(,(car hsl)
    ,(cadr hsl)
    ,(bounded 0.0 1.0 (proc (caddr hsl)
                            (/ amount 100)))))

(define* (adjust-saturation hsl amount proc)
  "Adjusts the saturation of HSL by applying AMOUNT
and current saturation to PROC."
  `(,(car hsl)
    ,(bounded 0.0 1.0 (proc (cadr hsl)
                            (/ amount 100)))
    ,(caddr hsl)))

(define* (adjust-hue hsl amount proc)
  "Adjusts the hue of HSL by applying AMOUNT and current hue to PROC."
  `(,(bounded 0.0 1.0 (proc (car hsl)
                            (/ amount 100)))
    ,(cadr hsl)
    ,(caddr hsl)))

(define* (hsl:brighten hsl amount)
  (rgba->hsl (map (lambda (v) (bounded 0 255 (+ v (/ amount 100))))
                  (hsl->rgba hsl))))

(define* (hsl:lighten hsl amount)
  (adjust-lightness hsl amount +))

(define* (hsl:darken hsl amount)
  (adjust-lightness hsl amount -))

(define* (hsl:saturate hsl amount)
  (adjust-saturation hsl amount +))

(define* (hsl:desaturate hsl amount)
  (adjust-saturation hsl amount -))

(define* (brighten hex #:optional (amount 10))
  "Decreases the brightness of hex color HEX by AMOUNT."
  (set-alpha hex
             (rgba->hex
              (map (lambda (v) (bounded 0 255 (+ v (/ amount 100))))
                   (hex->rgba hex)))))

(define* (lighten hex #:optional (amount 10))
  "Increases the lightness of hex color HEX by AMOUNT."
  (set-alpha hex (hsl->hex (hsl:lighten (hex->hsl hex) amount))))

(define* (darken hex #:optional (amount 10))
  "Decreases the lightness of hex color HEX by AMOUNT."
  (set-alpha hex (hsl->hex (hsl:darken (hex->hsl hex) amount))))

(define* (saturate hex #:optional (amount 10))
  "Increases the saturation of hex color HEX by AMOUNT."
  (set-alpha hex (hsl->hex (hsl:saturate (hex->hsl hex) amount))))

(define* (desaturate hex #:optional (amount 10))
  "Decreases the saturation of hex color HEX by AMOUNT."
  (set-alpha hex (hsl->hex (hsl:desaturate (hex->hsl hex) amount))))

(define* (offset hex #:optional (amount 10))
  (let* ((hsl (hex->hsl hex))
         (lum (caddr hsl)))
    (set-alpha hex
               (hsl->hex
                ;; Check if color is bright or dark
                (if (> lum 0.5)
                    (hsl:darken hsl amount)
                    (hsl:brighten hsl amount))))))

(define* (blend source backdrop #:optional (percentage 0.9))
  "Blends SOURCE with percentage PERCENTAGE with BACKDROP.
Setting PERCENTAGE >= 1.0 will return SOURCE, and PERCENTAGE = 0 will return BACKDROP."
  (let* ((source-rgb (hex->rgba source))
         (backdrop-rgb (hex->rgba backdrop))
         (mR (- (car backdrop-rgb) (car source-rgb)))
         (mG (- (cadr backdrop-rgb) (cadr source-rgb)))
         (mB (- (caddr backdrop-rgb) (caddr source-rgb))))
    (set-alpha source
               (rgba->hex
                `(,(+ (* mR (- 1 percentage)) (car source-rgb))
                  ,(+ (* mG (- 1 percentage)) (cadr source-rgb))
                  ,(+ (* mB (- 1 percentage)) (caddr source-rgb)))))))

(define* (make-readable fg bg #:optional (ratio 7))
  "Calculates a new color based on hex color FG that has a contrast ratio
of RATIO to the hex color BG."
  (define step 5) ;; 5% lightness change per iteration
  (define bg-hsl (hex->hsl bg))
  (define bg-light? (> (caddr bg-hsl) 0.5))

  (define (find-readable-color hsl)
    (let* ((fg-lightness (caddr hsl)))
      (if (or (>= fg-lightness 0.95)
              (<= fg-lightness 0.05)
              (>= (hsl:contrast hsl bg-hsl) ratio))
          hsl
          (find-readable-color (if bg-light?
                                   (hsl:darken hsl step)
                                   (hsl:lighten hsl step))))))

  (set-alpha fg
             (hsl->hex (find-readable-color (hex->hsl fg)))))

(define* (with-filters hex filters)
  "Applies the filters in FILTERS to HEX. Only converts between color representations once, thus yielding better performance.
@example
(with-filters \"#000000\" '((lighten 20) (saturate 20) (brighten 10)))
@end example"
  (set-alpha
   hex
   (hsl->hex
    (fold (lambda (filter acc)
            (apply (primitive-eval (symbol-append 'hsl: (car filter)))
                   (let ((args (list-tail filter 1)))
                     `(,acc ,@(if (null? args) 10 args)))))
            (hex->hsl hex)
            filters))))
