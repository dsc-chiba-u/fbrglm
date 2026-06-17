# fbrglm

Safe formula-based wrapper around
[`glmnet`](https://cran.r-project.org/package=glmnet): bring `glm()`'s
strict modeling-workflow semantics — formula + data in, predict-time
design matrix reconstructed from a frozen recipe out — to L1 / L2 /
elastic-net regularized GLMs.

## Why

`glmnet` is the de facto standard for regularized GLMs in R, but its
matrix-shaped API hands the full model recipe back to the caller:
factor encoding, contrasts, complete-case filtering, rank deficiency,
and predict-time design-matrix reconstruction. The recurring failure
modes are:

- the test factor's levels narrow (or an interaction with such a
  level is involved), so `glmnet::predict()` errors on a column-width
  mismatch;
- a session's `options("contrasts")` setting differs between fit and
  predict, so the design matrix silently changes meaning;
- a column is linearly dependent and gets reported as a numeric `0` —
  visually identical to a coefficient the L1 penalty shrunk to zero;
- production data carries a factor value the training set never saw,
  and there is no built-in way to keep the batch alive;
- complete-case bookkeeping is not exposed on the fit object.

`fbrglm` brings `stats::glm()`'s strict conventions to the `glmnet`
engine: frozen `terms` / `xlevels` / `contrasts` on the fit, QR-pivot
rank-deficient column drop with `NA` in `coef()` / `summary()`,
glm-style error on novel test factor levels (with an opt-in
`on_new_levels = "na"` for production scoring), explicit
`nobs_info` complete-case counts, and an explicit refusal to print
classical SE / z / p / CI under `infer = "none"`. The underlying
`glmnet` / `cv.glmnet` calls are unchanged — predictions are
bit-identical to a hand-built raw-`glmnet` call across every
glmnet-supported family — and reachable through `as_glmnet()` /
`as_cv_glmnet()` for downstream tooling.

## Status

`infer = "none"` only. Family coverage is:

**Core supported** (parity-checked against raw `glmnet`):
`gaussian`, `binomial`, `poisson`, `Gamma` (via `stats::Gamma(link = "log")`),
`negative binomial` (via `MASS::negative.binomial(theta = ...)` — **fixed
θ only**).

**Experimental** (basic fit / predict paths work, breadth of usage not
exhaustively tested):
native Cox (`family = "cox"` with `Surv(time, status) ~ ...`),
`multinomial`, `mgaussian`.

**Out of scope for the MVP**:
- Joint θ estimation in the style of `MASS::glm.nb()`.
- Cox-specific extras such as strata, ties handling, and time-varying
  covariates have not been validated.
- `infer = "split"` and `infer = "selective"` are planned but not
  implemented.

See `TODO.md` for the full backlog.

## Installation

Recommended:

```r
pak::pkg_install("dsc-chiba-u/fbrglm")
```

Alternative:

```r
remotes::install_github("dsc-chiba-u/fbrglm")
# or
devtools::install_github("dsc-chiba-u/fbrglm")
```

## Quick start

### Gaussian

```r
library(fbrglm)

set.seed(1)
n <- 100
df <- data.frame(
    y  = rnorm(n),
    x1 = rnorm(n),
    x2 = rnorm(n)
)

fit <- fbrglm(y ~ x1 + x2, data = df,
              family = "gaussian",
              lambda = "cv_min")

coef(fit)
head(predict(fit, type = "response"))
nobs(fit)
```

### Binomial

```r
library(fbrglm)

set.seed(2)
n <- 200
df <- data.frame(
    y  = rbinom(n, 1, 0.5),
    x1 = rnorm(n),
    x2 = rnorm(n)
)

fit <- fbrglm(y ~ x1 + x2, data = df,
              family = "binomial",
              lambda = "cv_1se")

head(predict(fit, type = "response"))   # probabilities in [0, 1]
head(predict(fit, type = "class"))      # 0/1
```

### Factor predictors

Factors are auto-dummied by `model.matrix()`. The training factor levels
are stored on the fit so `predict(newdata = ...)` still works when some
levels are missing from the test data.

```r
library(fbrglm)

set.seed(3)
n <- 200
train <- data.frame(
    y  = rnorm(n),
    x1 = rnorm(n),
    g  = factor(sample(c("A", "B", "C"), n, replace = TRUE),
                levels = c("A", "B", "C"))
)
fit <- fbrglm(y ~ x1 + g, data = train,
              family = "gaussian",
              lambda = "fix", lambda_value = 0.05)

# newdata missing level "C" — still works
test <- data.frame(
    x1 = rnorm(10),
    g  = factor(rep(c("A", "B"), 5), levels = c("A", "B", "C"))
)
predict(fit, newdata = test, type = "response")
```

By default, `predict()` errors on a factor value the model has not
seen — same as `stats::predict.glm()`. Production-style batch
scoring can opt into a softer mode:

```r
# `test_unseen$g` contains a new level "D" not in the training data;
# rows with that value get NA, the rest score normally, and a warning
# names how many rows were dropped.
predict(fit, newdata = test_unseen, type = "response",
        on_new_levels = "na")
```

## API

### `lambda` selection

`fbrglm()` exposes three rules through one argument:

| `lambda`   | meaning                                | backend                     |
|------------|----------------------------------------|-----------------------------|
| `"cv_min"` | `cv.glmnet()$lambda.min` (default)     | `glmnet::cv.glmnet()`       |
| `"cv_1se"` | `cv.glmnet()$lambda.1se`               | `glmnet::cv.glmnet()`       |
| `"fix"`    | uses `lambda_value` directly           | `glmnet::glmnet(lambda = ...)` |

`lambda = "fix"` requires `lambda_value` (numeric). The numeric λ that
the fit actually used is always available as `fit$lambda_value`.

### `predict(type = ...)`

For the single-response GLM families (`gaussian`, `binomial`,
`poisson`, `Gamma`, `negative.binomial`, `cox`):

| `type`       | gaussian / Gamma / NB | binomial             | poisson           | cox                                |
|--------------|-----------------------|----------------------|-------------------|------------------------------------|
| `"link"`     | η                     | η (logit)            | η (log)           | η (linear predictor)               |
| `"response"` | mean (link⁻¹η)        | probability ∈ [0, 1] | rate, `exp(η)`    | relative risk, `exp(η)`            |
| `"class"`    | error                 | 0 / 1 (threshold 0.5)| error             | error                              |

Cox predictions are on the linear-predictor / relative-risk scale, not
absolute hazards. fbrglm does not estimate the baseline hazard;
absolute survival curves require a separate baseline-hazard step (e.g.
via `survival::basehaz()` on a `coxph` fit, or an equivalent Breslow
estimate computed against the `coxnet` linear predictors).

For the multi-response families:

- `multinomial`: `"link"` / `"response"` return an `(n × k)` matrix
  (one column per class); `"class"` returns the argmax class label.
- `mgaussian`: `"link"` / `"response"` return an `(n × q)` matrix
  (one column per response); `"class"` errors.

See `vignette("fbrglm-families")` for worked examples.

### Complete-case bookkeeping: `nobs_info`

Complete-case filtering happens automatically. The numbers are exposed at
`fit$nobs_info`:

```r
fit$nobs_info$n_total            # rows in the input data
fit$nobs_info$n_dropped_missing  # rows with any NA in the model.frame
fit$nobs_info$n_used             # rows actually fit
nobs(fit)                        # same as $n_used
```

If any rows are dropped, `fbrglm()` prints a one-line message.

### Inference: only `infer = "none"` for now

Only `infer = "none"` is currently enabled, and `summary()` deliberately
**does not report classical SE, z, p-values, or confidence
intervals**: shrinkage bias, data-driven λ selection, and active-set
conditioning all break the textbook interpretation of those
quantities. The `summary()` output instead carries a permanent footer
naming the three failure modes and the planned remediation paths
(`infer = "split"` for sample-split refits, `infer = "selective"`
for selective inference at the chosen λ). `coef()` returns the
regularized point estimates with `NA` for any column dropped by the
QR-pivot rank check; `summary()` adds the glm-style
"`(N not defined because of singularities: ...)`" header when that
happens, the complete-case `nobs_info` triple, and the inference
policy footer.

## Planned (not yet implemented)

- `infer = "split"` — data splitting with `selection_frac` for honest
  post-selection SEs / p-values / CIs via a base-R `glm()` refit.
- `infer = "selective"` — selective inference at the chosen λ.
- Broader Cox coverage (strata, ties handling, time-varying
  covariates) and corresponding tests.
- Joint θ estimation for negative binomial (`MASS::glm.nb()`-style).

Full list and rationale: `TODO.md`.

## Vignettes

- *Getting started* (`vignette("fbrglm")`) — formula / data, λ
  selection, `predict(type = ...)`, `nobs_info`, factor narrowing,
  offsets.
- *Families and model types* (`vignette("fbrglm-families")`) — worked
  examples for linear, logistic, Poisson (with offset), Gamma,
  negative binomial (fixed θ), native Cox (`Surv()` LHS), plus the
  experimental multinomial and mgaussian paths. Two survival routes
  are shown explicitly: the **piecewise exponential Poisson** model on
  long-format data and the **native Cox** path via `family = "cox"`;
  these are different models and the vignette does not conflate them.

## Reproducible experiments

Smoke tests and benchmarks live in a separate repository:
<https://github.com/dsc-chiba-u/fbrglm-experiments>.

Currently it contains:

- smoke tests for MVP behavior (gaussian / binomial / poisson basics,
  `glmnet` parity at fixed λ, `cv.glmnet` parity at `cv_min` / `cv_1se`,
  factor newdata, complete-case bookkeeping)
- a prediction-failure benchmark for train/test factor-level mismatch
- a small runtime benchmark
- generated plots for both benchmarks

Comparison methods covered in the small benchmarks:

- raw `glmnet`
- `glmnetUtils`
- `parsnip` / `workflows` with the `glmnet` engine

Headline observations from the prediction-failure benchmark, in two
factor-level scenarios:

- *Narrowed test* (train: A/B/C/D, test: A/B). `fbrglm`, the
  `glmnet_raw_safe` (manual re-level) path, `glmnetUtils` with
  `use.model.frame = TRUE`, and the `parsnip` / `workflows` pipeline
  all succeed. Default `glmnet_raw_naive` and default `glmnetUtils`
  fail with a column-width error.
- *Novel level test* (train: A/B, test: A/B/C/D). `fbrglm`'s default
  reproduces `stats::predict.glm()`'s "factor has new levels"
  error verbatim, as does `glmnetUtils` with
  `use.model.frame = TRUE` and `stats::glm()` itself. The default
  fast paths get the column-width error instead. `parsnip` warns
  and silently coerces novel cells to the reference level; `fbrglm`'s
  opt-in `on_new_levels = "na"` is the only path that returns `NA`
  at novel-level rows and finite predictions elsewhere.

## License

MIT — see `LICENSE`.
