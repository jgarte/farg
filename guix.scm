(use-modules
  (guix packages)
  ((guix licenses) #:prefix license:)
  (guix download)
  (guix build-system gnu)
  (gnu packages)
  (gnu packages autotools)
  (gnu packages guile)
  (gnu packages guile-xyz)
  (gnu packages pkg-config)
  (gnu packages python-xyz)
  (gnu packages texinfo))

(package
  (name "farg")
  (version "0.1")
  (source "./farg-0.1.tar.gz")
  (build-system gnu-build-system)
  (arguments `())
  (native-inputs
    `(("autoconf" ,autoconf)
      ("automake" ,automake)
      ("pkg-config" ,pkg-config)
      ("texinfo" ,texinfo)))
  (inputs `(("guile" ,guile-3.0)))
  (propagated-inputs `("python-pywal" ,python-pywal))
  (synopsis "")
  (description "")
  (home-page "")
  (license license:gpl3+))

