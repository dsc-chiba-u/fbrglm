# fbrglm

Formula-based regularized GLM — a formula/data interface for
[`glmnet`](https://cran.r-project.org/package=glmnet) that feels closer to
base R's `glm()`.

## Why

`glmnet` is the standard for L1/L2-regularized GLMs in R, but its API
diverges from `glm()` in ways that raise the learning cost: it takes a
pre-built design matrix instead of a formula, doesn't auto-handle factors,
doesn't filter incomplete cases, and lambda selection is a post-hoc step
on the `cv.glmnet` object. `fbrglm` closes the gap so you can write the
same `y ~ x1 + x2` you'd write for `glm()` and get a regularized fit back.

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

Development install from a local clone:

```r
devtools::install("/home/koki/dev/fbrglm")
# or
install.packages("/home/koki/dev/fbrglm", repos = NULL, type = "source")
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

| `type`       | gaussian / Gamma / NB | binomial             | poisson           | cox           |
|--------------|-----------------------|----------------------|-------------------|---------------|
| `"link"`     | η                     | η (logit)            | η (log)           | η             |
| `"response"` | mean (link⁻¹η)        | probability ∈ [0, 1] | rate, `exp(η)`    | rate, `exp(η)`|
| `"class"`    | error                 | 0 / 1 (threshold 0.5)| error             | error         |

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

The MVP only supports `infer = "none"`. That means **no standard errors,
no z values, no p values, and no confidence intervals** are produced;
`coef()` returns the regularized point estimates and `summary()` reports
the non-zero terms plus complete-case bookkeeping. Honest inference
(`infer = "split"`, `infer = "selective"`) is the next milestone — see
`TODO.md`.

## Planned (not yet implemented)

- `infer = "split"` — data splitting with `selection_frac` for honest
  post-selection SEs / p-values / CIs via a base-R `glm()` refit.
- `infer = "selective"` — selective inference at the chosen λ.
- QR-pivot column dropping for rank-deficient designs (currently a
  warning plus `fit$rank_info`; offending columns are not yet dropped).
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

Headline observation in the prediction-failure benchmark (small synthetic
data, narrowed test factor levels): raw `glmnet` can fail when train and
test design matrices are built naively. `parsnip` / `workflows` also
handles the narrowed-level case, but with higher runtime overhead in the
tested setting. `fbrglm` aims to provide a lighter-weight glm-like
interface with prediction-time design-matrix consistency.

## License

MIT — see `LICENSE`.
