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

MVP skeleton — `infer = "none"` only, families `gaussian` / `binomial`
/ `poisson`. See **Planned** below and `TODO.md` for the deferred work.

## Installation

```r
# from a local clone (recommended on systems where binary deps misbehave)
install.packages("/path/to/fbrglm", repos = NULL, type = "source")

# or with devtools
devtools::install("/path/to/fbrglm")

# or with pak
pak::pkg_install("/path/to/fbrglm")
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

| `type`       | gaussian | binomial             | poisson           |
|--------------|----------|----------------------|-------------------|
| `"link"`     | η        | η (logit)            | η (log)           |
| `"response"` | η        | probability ∈ [0, 1] | rate, `exp(η)`    |
| `"class"`    | error    | 0 / 1 (threshold 0.5)| error             |

`"class"` is only valid for binomial in the MVP; gaussian and poisson
return an error.

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
- `family = "multinomial"` and `family = "cox"` (with `Surv(time, status)`
  on the LHS).
- QR-pivot column dropping for rank-deficient designs (currently a
  warning plus `fit$rank_info`; offending columns are not yet dropped).
- Vignette and CI (R-CMD-check + test-coverage on GitHub Actions).

Full list and rationale: `TODO.md`.

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
