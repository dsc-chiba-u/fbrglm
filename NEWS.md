# fbrglm 0.0.1

Initial CRAN release.

* Formula / data interface to `glmnet` covering the full glmnet
  family surface: the six character strings (`gaussian`, `binomial`,
  `poisson`, `cox`, `multinomial`, `mgaussian`) plus arbitrary GLM
  family objects such as `stats::Gamma(link = "log")` and
  `MASS::negative.binomial(theta = ...)`.

* Predict-time design-matrix reconstruction from the training-time
  `terms`, `xlevels`, and `contrasts` stored on the fit object,
  independent of session-level `options("contrasts")`. Absent
  factor-level columns are zero-padded; both main effects and
  interaction terms are aligned in one pass.

* Rank-deficient designs are handled in the spirit of `stats::glm()`:
  a column-pivoted QR check on the column-centred design matrix
  identifies linearly dependent columns, the underlying `glmnet`
  fit only sees the independent subset, and the dropped columns
  surface as `NA` in `coef()` and `summary()` so they can be told
  apart from coefficients the L1 penalty shrunk to zero.

* `predict()` follows `stats::predict.glm()` on novel factor levels
  in `newdata` by default (an error message matching glm's "factor g
  has new levels ..." string). A new
  `predict(fit, newdata, on_new_levels = "na")` opt-in is provided
  for batch / production scoring pipelines: rows with unseen levels
  are returned as `NA` and a warning naming the affected row count
  is emitted, while the rest score normally.

* Complete-case filtering happens through
  `model.frame(..., na.action = na.omit)`; the dropped and used
  counts are exposed as `fit$nobs_info` and announced via a one-line
  message at fit time.

* A single `lambda` argument covers the three common selection
  rules — `"cv_min"`, `"cv_1se"`, and `"fix"` (paired with
  `lambda_value`). The chosen numeric `lambda` is stored on
  `fit$lambda_value` and reused by `predict()`, `coef()`,
  `summary()`, and `plot()` so there is a single source of truth.

* S3 methods (`print`, `summary`, `predict`, `coef`, `nobs`, `plot`)
  mirror the `glm()` surface. `summary()` follows
  `stats::summary.glm()`'s coefficient table layout, including a
  glm-style header "(N not defined because of singularities: ...)"
  when the design was rank-deficient, and a permanent footer
  explaining why no standard errors, z-values, or p-values are
  reported under the current `infer = "none"` mode (shrinkage bias,
  data-driven lambda selection, and active-set conditioning).

* Accessors `as_glmnet()` and `as_cv_glmnet()` expose the underlying
  `glmnet` and `cv.glmnet` objects for downstream tooling that
  consumes them directly.

* Two vignettes: `vignette("fbrglm")` walks the formula/data
  interface, `nobs_info`, factor narrowing, and offsets;
  `vignette("fbrglm-families")` walks the family-by-family worked
  examples plus the piecewise-exponential survival formulation.
