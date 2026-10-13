(lang dune 3.17)

(name money)

(generate_opam_files true)

(license MIT)

(maintainers "winterchill-trading")

(authors "winterchill-trading")

(source
 (github winterchill-trading/money))

(package
 (name money)
 (synopsis "Currencies, exact amounts, exchange rates and fees")
 (depends
  (ocaml
   (>= 5.2))
  dune
  core
  core_unix
  ppx_jane
  ppx_yojson_conv
  yojson
  zarith
  fixed-decimal))
