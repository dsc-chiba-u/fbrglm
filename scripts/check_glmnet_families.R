## scripts/check_glmnet_families.R
## Empirically probe which family argument forms glmnet::glmnet() and
## glmnet::cv.glmnet() accept, and which predict types work.
## Results inform the fbrglm family-validation rules.

suppressPackageStartupMessages({
    library(glmnet)
})

set.seed(20260301)
n <- 100
p <- 5
X <- matrix(rnorm(n * p), n, p)
colnames(X) <- paste0("x", 1:p)

eta_lin <- 0.4 * X[, 1] - 0.3 * X[, 2]

probe <- function(label, family_arg, y, predict_types,
                  extra_glmnet = list()) {
    cat("\n=== ", label, " ===\n", sep = "")
    fit_args <- c(list(x = X, y = y, family = family_arg, alpha = 1,
                       lambda = 0.05),
                  extra_glmnet)
    fit <- tryCatch(do.call(glmnet::glmnet, fit_args),
                    error = function(e) e)
    if (inherits(fit, "error")) {
        cat("  glmnet:     FAIL — ", conditionMessage(fit), "\n", sep = "")
    } else {
        cat("  glmnet:     OK (class ", paste(class(fit), collapse=","), ")\n", sep = "")
    }

    cv_args <- c(list(x = X, y = y, family = family_arg, alpha = 1,
                      nfolds = 5),
                 extra_glmnet)
    cv <- tryCatch(do.call(glmnet::cv.glmnet, cv_args),
                   error = function(e) e)
    if (inherits(cv, "error")) {
        cat("  cv.glmnet:  FAIL — ", conditionMessage(cv), "\n", sep = "")
    } else {
        cat("  cv.glmnet:  OK\n")
    }

    if (inherits(fit, "glmnet")) {
        for (tp in predict_types) {
            out <- tryCatch(
                predict(fit, newx = X, s = 0.05, type = tp),
                error = function(e) e
            )
            if (inherits(out, "error")) {
                cat("    predict type='", tp, "': FAIL — ",
                    conditionMessage(out), "\n", sep = "")
            } else {
                cat("    predict type='", tp, "': OK (",
                    paste(dim(out) %||% length(out), collapse="x"),
                    ", class ", paste(class(out), collapse=","), ")\n", sep = "")
            }
        }
    }
}
`%||%` <- function(a, b) if (is.null(a)) b else a

## 1. gaussian
probe("gaussian (chr)", "gaussian",
      y = stats::rnorm(n, eta_lin, 0.5),
      predict_types = c("link", "response"))

## 2. binomial
probe("binomial (chr)", "binomial",
      y = stats::rbinom(n, 1, stats::plogis(eta_lin)),
      predict_types = c("link", "response", "class"))

## 3. poisson
probe("poisson (chr)", "poisson",
      y = stats::rpois(n, exp(eta_lin)),
      predict_types = c("link", "response"))

## 4. cox (needs Surv on y)
if (requireNamespace("survival", quietly = TRUE)) {
    t_event <- stats::rexp(n, exp(eta_lin))
    t_cens  <- 3
    t_obs   <- pmin(t_event, t_cens)
    delta   <- as.integer(t_event <= t_cens)
    y_cox <- survival::Surv(t_obs, delta)
    probe("cox (chr, Surv)", "cox",
          y = y_cox,
          predict_types = c("link", "response", "class"))
}

## 5. Gamma family object
probe("Gamma(link='log') family object", stats::Gamma(link = "log"),
      y = stats::rgamma(n, shape = 2, rate = exp(-eta_lin)),
      predict_types = c("link", "response"))

## 6. negative binomial family object (MASS)
if (requireNamespace("MASS", quietly = TRUE)) {
    nb_fam <- MASS::negative.binomial(theta = 2)
    probe("MASS::negative.binomial(theta=2)", nb_fam,
          y = stats::rnbinom(n, mu = exp(eta_lin), size = 2),
          predict_types = c("link", "response"))
}

## 7. multinomial
y_mult <- factor(sample(c("a","b","c"), n, replace = TRUE))
probe("multinomial (chr)", "multinomial",
      y = y_mult,
      predict_types = c("link", "response", "class"))

## 8. mgaussian
Y_m <- cbind(stats::rnorm(n, eta_lin, 0.5),
             stats::rnorm(n, -eta_lin, 0.5))
probe("mgaussian (chr)", "mgaussian",
      y = Y_m,
      predict_types = c("link", "response"))

cat("\n=== glmnet version: ", as.character(utils::packageVersion("glmnet")),
    " ===\n", sep = "")
