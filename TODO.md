# TODO

Heavy features from the spec memo that are intentionally **deferred** so the
MVP skeleton stays small and stable. The MVP itself (argument validation,
return-value contract, S3 method registration) is in `R/fbrglm.R` /
`R/methods.R`.

## Package name

- [ ] Decide whether to rename `fbrglm` → `rfglm` ("regularized &
      formula-based GLM"). The current package uses `fbrglm`; the spec memo
      uses `rfglm`. Either name maps to the same scope — pick before the
      first JSS/SoftwareX submission.

## Fit pipeline (formula → model matrix → glmnet)

- [ ] `model.frame()` / `model.matrix()` pipeline so users can pass
      `formula + data` and have y/X built for them.
- [ ] Automatic dummy encoding of factor variables, with factor levels
      saved on the fitted object so `predict()` can reproduce columns.
- [ ] Complete-case filtering with an explicit "N rows dropped due to
      missing" message; expose `n_total`, `n_dropped_missing`, `n_used`
      on the fitted object.
- [ ] Rank-deficiency guard via QR pivoting before handing `x` to glmnet:
      drop linearly dependent columns and remember them so `summary()` can
      report their coefficients as `NA`. Reference sketch:
      ```r
      qrout <- qr(x)
      if (qrout$rank > 1L) x <- x[, qrout$pivot[1L:qrout$rank]]
      ```
- [ ] `weights` / `offset` pass-through to `glmnet()` / `cv.glmnet()`
      (and to the inner `glm()` refit under `infer = "split"`).
- [ ] Allow `x`, `y` direct-matrix entry as a secondary code path
      (formula/data wins when both are given).
- [ ] Pass-through of glmnet / cv.glmnet tuning args via `...`
      (`nlambda`, `nfolds`, `standardize`, ...).
- [ ] End-to-end λ rules:
      `"cv_min"` → `cv.glmnet()$lambda.min`,
      `"cv_1se"` → `cv.glmnet()$lambda.1se`,
      `"fix"`    → `glmnet(..., lambda = lambda_value)`.

## Predict / S3 methods

- [ ] `predict.fbrglm(object, newdata, type)` — rebuild the model matrix
      from the stored formula and factor levels, then return
      `"link"` / `"response"` / `"class"`. `"class"` is valid only for
      binomial / multinomial; error otherwise. Binomial → 0/1 by 0.5,
      multinomial → argmax category.
- [ ] `summary.fbrglm` — include `call`, `family`, `infer` (+
      `selection_frac` when relevant), full coefficient table (zeros
      included; SE / z / p / CI / stars only when `infer != "none"`),
      `nonzero` names, `lambda_value`, `lambda_method`, and the
      `n_total` / `n_dropped_missing` / `n_used` trio (split into
      selection/inference under `infer = "split"`).
- [ ] `plot.fbrglm` — CV curve when fit via `cv.glmnet`, coefficient path
      under `lambda = "fix"`.

## Inference (heavy — explicitly out of MVP scope)

- [ ] `infer = "split"` with `selection_frac` (default 0.2):
      use the selection share to pick λ via CV and the nonzero variables,
      then refit a plain `glm()` on the inference share for honest SEs /
      p-values / CIs.
- [ ] `infer = "selective"` — selective inference (post-selection CIs /
      p-values) at the chosen λ. Decide between `selectiveInference` and a
      hand-rolled path before locking the API.

## Families (deferred)

- [ ] `family = "multinomial"` — separate code path (base `glm()` doesn't
      cover this; pair `glmnet` with an alternative refit for inference).
- [ ] `family = "cox"` with `Surv(time, status) ~ ...` accepted on the LHS;
      survival-style summaries.
- [ ] Explicitly NOT planned for the first release: `"mgaussian"`.

## Tooling

- [ ] Switch `NAMESPACE` to a roxygen2-generated file and stop hand-editing.
- [ ] `R CMD check --as-cran` clean.
- [ ] GitHub Actions: R-CMD-check + test-coverage.
- [ ] Vignette: a "glm → fbrglm in five minutes" walk-through.

## Publication targets (context)

- Journal of Statistical Software (IF 8.1) — primary target.
- SoftwareX (IF 2.4) — fallback.

The pitch hinges on closing the API gap between base `glm()` and `glmnet`:
formula/data front-end, automatic factor handling, rank-deficiency guard,
glm-style `summary()` / `predict()`, and a single `lambda` selector. Heavy
inference (split / selective) is a second-phase feature, not a launch
blocker — keep that boundary visible in the docs.
