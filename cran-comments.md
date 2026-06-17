# Submission comments

## Release

This is a first CRAN submission of `fbrglm` (version 0.0.1).

## Test environments

* local: x86_64-conda-linux-gnu, R 4.5.3
* win-builder (devel + release): TODO before submission
* R-hub (ubuntu-latest, windows-latest, macos-latest): TODO before submission

`R CMD check --as-cran` is clean on the local environment modulo the
two routine NOTEs noted below.

## R CMD check results

```
Status: 0 ERRORs | 0 WARNINGs | 2 NOTEs
```

* "New submission" — expected for a first release.
* "unable to verify current time" — environmental (the build host had
  no outbound network access to the CRAN time server at check time);
  not a defect in the package itself.

A separate environmental warning ("`qpdf` is needed for checks on
size reduction of PDFs") appears only on the local machine because
`qpdf` is not installed there; it does not appear when
`--no-manual` is passed and is not a property of the package.

## Reverse dependencies

None — this is a new package.

## Authors / maintainer

* Maintainer: Koki Tsuyuzaki <koki.tsuyuzaki@gmail.com>

## Notes for the reviewer

* `fbrglm` is a formula-based wrapper around `glmnet`; the underlying
  `glmnet` / `cv.glmnet` calls are reachable through the
  `as_glmnet()` / `as_cv_glmnet()` accessors so downstream callers
  can keep using glmnet-specific helpers directly.
* The companion benchmark / replication material lives in a separate
  repository
  (<https://github.com/dsc-chiba-u/fbrglm-experiments>) and is not
  part of the package itself.
* Inference modes `infer = "split"` and `infer = "selective"` are
  reserved in the API signature but not yet implemented; only
  `infer = "none"` is enabled. The package's `summary()` output
  declines to print classical SE / z / p / CI under that mode rather
  than producing numbers without post-selection guarantees.
