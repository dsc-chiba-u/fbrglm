# fbrglm 0.1.0

* New `tidy()` method (S3 method for `generics::tidy`) returning a
  tibble with one row per coefficient (`term`, `estimate`, `nonzero`,
  `lambda`). Rank-deficient columns surface as `NA` in `estimate`,
  matching `coef()` / `summary()` conventions. For multinomial and
  mgaussian fits the tibble is in long form with an extra `class`
  or `response` column. Standard errors, z / t values, p-values,
  and confidence intervals are intentionally omitted under
  `infer = "none"`.

* New `glance()` method returning a single-row tibble summarising
  the fit: `family`, `lambda_rule`, `lambda`, `alpha`, `infer`,
  `nobs` / `nobs_dropped` / `nobs_total`, `rank` / `rank_dropped` /
  `rank_deficient`, `nonzero`, `deviance`, `cvm_at_lambda` /
  `cvsd_at_lambda` (when a CV fit is attached), and `logLik` /
  `AIC` / `BIC` columns kept for `broom` shape compatibility but
  set to `NA` under the regularized estimator.

* `plot.fbrglm()` is rewritten with a `what` argument. The new
  default `what = "diagnostic"` shows `glm()`-style residual
  diagnostics (Residuals vs Fitted, Normal Q-Q, Scale-Location)
  using deviance residuals at the chosen lambda; the leverage /
  Cook's-distance panels of `plot.lm()` are deliberately omitted
  because the hat-matrix-based standardisation does not have a
  canonical regularized analogue. `what = "path"` delegates to
  `plot.glmnet()` for the regularization path (the previous
  default); `what = "cv"` delegates to `plot.cv.glmnet()` for the
  CV curve. The same call now also accepts the standard
  `plot.lm()` arguments (`which`, `caption`, `sub.caption`, ...).

* The fitted response vector is now stored on the fit as
  `y_train`, parallel to the existing `x_train`, so internal
  diagnostics do not need to re-run `model.frame()`.

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
