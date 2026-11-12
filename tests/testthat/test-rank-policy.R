## rank_policy = "drop" vs "keep" and qr_tol surface.
##
## Addresses Nishiuchi 指示 1 for SOFTX-D-26-00949: expose the
## rank-deficient-column handling as a user-controllable policy, and
## expose the QR tolerance that drives it. Default must stay
## backward-compatible ("drop", tol = 1e-7), and "keep" must hand
## every column to glmnet without NA injection at the coefficient
## layer.

library(testthat)
library(fbrglm)

make_rankdef <- function(seed = 2026, n = 200L) {
    set.seed(seed)
    df <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n))
    df$x3 <- df$x1 + df$x2   # exact linear dependence
    df
}

test_that("rank_policy defaults to 'drop' and reproduces prior behavior", {
    df <- make_rankdef()
    suppressMessages(
        fit <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                      lambda = "fix", lambda_value = 0.05)
    )
    expect_equal(fit$rank_policy, "drop")
    expect_equal(fit$qr_tol, 1e-7)
    expect_true(fit$rank_info$rank_deficient)
    expect_true(fit$rank_info$dropped_applied)
    expect_equal(fit$rank_info$policy, "drop")
    expect_equal(fit$rank_info$tol, 1e-7)
    ## Exactly one of {x1,x2,x3} is dropped and reported as NA.
    expect_equal(length(fit$rank_info$dropped_cols), 1L)
    co <- stats::coef(fit)
    expect_true(any(is.na(co)))
    expect_equal(sum(is.na(co)), 1L)
    expect_equal(names(co)[is.na(co)], fit$rank_info$dropped_cols)
})

test_that("rank_policy = 'keep' bypasses the drop and keeps all coefficients", {
    df <- make_rankdef()
    suppressMessages(
        fit_keep <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                           lambda = "fix", lambda_value = 0.05,
                           rank_policy = "keep")
    )
    expect_equal(fit_keep$rank_policy, "keep")
    expect_equal(fit_keep$rank_info$policy, "keep")
    expect_true(fit_keep$rank_info$rank_deficient)       # QR still flags it
    expect_false(fit_keep$rank_info$dropped_applied)     # but we did not drop
    ## Diagnostic kept/dropped_cols still populated by QR for inspection.
    expect_equal(length(fit_keep$rank_info$dropped_cols), 1L)
    co <- stats::coef(fit_keep)
    ## glmnet saw the full design; every column has a (penalised) coef,
    ## no NA injection.
    expect_false(any(is.na(co)))
    expect_equal(length(co), 4L)   # intercept + x1 + x2 + x3
})

test_that("rank_policy = 'keep' matches raw glmnet on the full design", {
    df <- make_rankdef()
    suppressMessages(
        fit_keep <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                           lambda = "fix", lambda_value = 0.05,
                           rank_policy = "keep")
    )
    X <- as.matrix(df[, c("x1", "x2", "x3")])
    raw <- glmnet::glmnet(X, df$y, family = "gaussian", alpha = 1,
                          lambda = 0.05)
    co_fb  <- stats::coef(fit_keep)
    co_raw <- as.numeric(stats::coef(raw, s = 0.05))
    names(co_raw) <- rownames(stats::coef(raw, s = 0.05))
    expect_equal(sort(names(co_fb)), sort(names(co_raw)))
    for (nm in names(co_fb)) {
        expect_equal(co_fb[[nm]], co_raw[[nm]], tolerance = 1e-10,
                     info = sprintf("coef '%s' mismatch", nm))
    }
})

test_that("rank_policy = 'keep' preserves predictions equivalent to raw glmnet", {
    df <- make_rankdef()
    suppressMessages(
        fit_keep <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                           lambda = "fix", lambda_value = 0.05,
                           rank_policy = "keep")
    )
    X <- as.matrix(df[, c("x1", "x2", "x3")])
    raw <- glmnet::glmnet(X, df$y, family = "gaussian", alpha = 1,
                          lambda = 0.05)
    pred_fb  <- as.numeric(stats::predict(fit_keep, newdata = df,
                                          type = "response"))
    pred_raw <- as.numeric(stats::predict(raw, newx = X, s = 0.05,
                                          type = "response"))
    expect_equal(pred_fb, pred_raw, tolerance = 1e-10)
})

test_that("rank_policy = 'drop' predictions ignore the dropped column", {
    df <- make_rankdef()
    suppressMessages(
        fit_drop <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                           lambda = "fix", lambda_value = 0.05)
    )
    ## Prediction path must restrict newdata to kept_cols. Try new
    ## data with a different x3 to confirm the dropped column does
    ## not influence predictions in drop mode.
    set.seed(99)
    nd <- data.frame(
        x1 = rnorm(10),
        x2 = rnorm(10)
    )
    nd$x3 <- nd$x1 + nd$x2      # consistent with training dependency
    p1 <- as.numeric(stats::predict(fit_drop, newdata = nd,
                                    type = "response"))
    ## Perturb x3 so it violates the dependency - predictions must
    ## remain unchanged in drop mode, because x3's coef is NA (dropped).
    nd2 <- nd; nd2$x3 <- nd2$x3 + rnorm(10, sd = 5)
    p2 <- as.numeric(stats::predict(fit_drop, newdata = nd2,
                                    type = "response"))
    expect_equal(p1, p2, tolerance = 1e-10)
})

test_that("rank_policy = 'keep' lets perturbing a flagged column move predictions", {
    df <- make_rankdef()
    suppressMessages(
        fit_keep <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                           lambda = "fix", lambda_value = 0.05,
                           rank_policy = "keep")
    )
    set.seed(99)
    nd <- data.frame(x1 = rnorm(10), x2 = rnorm(10))
    nd$x3 <- nd$x1 + nd$x2
    p1 <- as.numeric(stats::predict(fit_keep, newdata = nd,
                                    type = "response"))
    nd2 <- nd; nd2$x3 <- nd2$x3 + rnorm(10, sd = 5)
    p2 <- as.numeric(stats::predict(fit_keep, newdata = nd2,
                                    type = "response"))
    ## If glmnet assigned any nonzero mass to x3, predictions will shift.
    ## This test only asserts that keep mode does NOT force equality:
    ## we skip the expectation when glmnet happened to shrink x3 to 0.
    co <- stats::coef(fit_keep)
    if (!is.na(co[["x3"]]) && co[["x3"]] != 0) {
        expect_false(isTRUE(all.equal(p1, p2)))
    } else {
        succeed("x3 coefficient shrunk to zero by penalty; equality is fine")
    }
})

test_that("invalid rank_policy is rejected with a clear message", {
    df <- make_rankdef()
    expect_error(
        fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
               lambda = "fix", lambda_value = 0.05,
               rank_policy = "nope"),
        "should be one of"
    )
})

test_that("qr_tol must be a positive finite scalar", {
    df <- make_rankdef()
    expect_error(
        fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
               lambda = "fix", lambda_value = 0.05, qr_tol = 0),
        "positive finite numeric scalar"
    )
    expect_error(
        fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
               lambda = "fix", lambda_value = 0.05, qr_tol = -1),
        "positive finite numeric scalar"
    )
    expect_error(
        fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
               lambda = "fix", lambda_value = 0.05, qr_tol = NA_real_),
        "positive finite numeric scalar"
    )
    expect_error(
        fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
               lambda = "fix", lambda_value = 0.05, qr_tol = c(1e-7, 1e-6)),
        "positive finite numeric scalar"
    )
})

test_that("qr_tol = 1 makes the QR aggressive; small tol = conservative", {
    df <- make_rankdef()
    ## Loose tol: QR treats more columns as dependent. Use keep policy
    ## so glmnet still sees every column - at tol = 1 virtually all
    ## columns get flagged, and under drop policy that would shrink
    ## the design below glmnet's two-column minimum.
    suppressMessages(
        fit_loose <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                            lambda = "fix", lambda_value = 0.05,
                            rank_policy = "keep", qr_tol = 1)
    )
    ## Strict tol (<<< 1e-7): QR should still find the exact
    ## dependence (x3 = x1 + x2 is numerically perfect up to roundoff).
    suppressMessages(
        fit_strict <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                             lambda = "fix", lambda_value = 0.05,
                             rank_policy = "keep", qr_tol = 1e-14)
    )
    expect_equal(fit_loose$qr_tol, 1)
    expect_equal(fit_strict$qr_tol, 1e-14)
    expect_true(fit_loose$rank_info$rank_deficient)
    expect_true(fit_strict$rank_info$rank_deficient)
    expect_gte(length(fit_loose$rank_info$dropped_cols),
               length(fit_strict$rank_info$dropped_cols))
})

test_that("healthy design: rank_policy has no effect on coefficients", {
    set.seed(321)
    n <- 150
    df <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n),
                     x3 = rnorm(n))     # no collinearity
    suppressMessages(
        fit_drop <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                           lambda = "fix", lambda_value = 0.05,
                           rank_policy = "drop")
    )
    suppressMessages(
        fit_keep <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                           lambda = "fix", lambda_value = 0.05,
                           rank_policy = "keep")
    )
    expect_false(fit_drop$rank_info$rank_deficient)
    expect_false(fit_keep$rank_info$rank_deficient)
    expect_false(fit_drop$rank_info$dropped_applied)
    expect_false(fit_keep$rank_info$dropped_applied)
    expect_equal(stats::coef(fit_drop), stats::coef(fit_keep),
                 tolerance = 1e-12)
})

test_that("glance() reports rank_policy and dropped_applied", {
    df <- make_rankdef()
    suppressMessages(
        fit_drop <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                           lambda = "fix", lambda_value = 0.05)
    )
    suppressMessages(
        fit_keep <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                           lambda = "fix", lambda_value = 0.05,
                           rank_policy = "keep")
    )
    g_drop <- generics::glance(fit_drop)
    g_keep <- generics::glance(fit_keep)
    expect_true("rank_policy" %in% names(g_drop))
    expect_true("rank_dropped_applied" %in% names(g_drop))
    expect_equal(g_drop$rank_policy, "drop")
    expect_true(g_drop$rank_dropped_applied)
    expect_equal(g_keep$rank_policy, "keep")
    expect_false(g_keep$rank_dropped_applied)
    ## rank_deficient stays true in both (same QR result).
    expect_true(g_drop$rank_deficient)
    expect_true(g_keep$rank_deficient)
})

test_that("summary prints 'not defined because of singularities' only in drop mode", {
    df <- make_rankdef()
    suppressMessages(
        fit_drop <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                           lambda = "fix", lambda_value = 0.05)
    )
    suppressMessages(
        fit_keep <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                           lambda = "fix", lambda_value = 0.05,
                           rank_policy = "keep")
    )
    out_drop <- utils::capture.output(summary(fit_drop))
    out_keep <- utils::capture.output(summary(fit_keep))
    expect_true(any(grepl("not defined because of singularities",
                          out_drop, fixed = TRUE)))
    expect_false(any(grepl("not defined because of singularities",
                           out_keep, fixed = TRUE)))
})

test_that("print.fbrglm reports a distinct footer for keep vs drop", {
    df <- make_rankdef()
    suppressMessages(
        fit_drop <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                           lambda = "fix", lambda_value = 0.05)
    )
    suppressMessages(
        fit_keep <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                           lambda = "fix", lambda_value = 0.05,
                           rank_policy = "keep")
    )
    out_drop <- utils::capture.output(print(fit_drop))
    out_keep <- utils::capture.output(print(fit_keep))
    expect_true(any(grepl("columns dropped", out_drop, fixed = TRUE)))
    expect_true(any(grepl("rank_policy = \"keep\"",
                          out_keep, fixed = TRUE)))
})

test_that("binomial + factor collinearity: rank_policy = keep returns all coefs", {
    set.seed(77)
    n <- 160
    df <- data.frame(
        y = rbinom(n, 1, 0.5),
        x1 = rnorm(n),
        g  = factor(sample(c("A", "B"), n, replace = TRUE))
    )
    ## Introduce collinearity: duplicate the factor as a second factor.
    df$g2 <- df$g
    suppressMessages(
        fit_drop <- fbrglm(y ~ x1 + g + g2, data = df, family = "binomial",
                           lambda = "fix", lambda_value = 0.05)
    )
    suppressMessages(
        fit_keep <- fbrglm(y ~ x1 + g + g2, data = df, family = "binomial",
                           lambda = "fix", lambda_value = 0.05,
                           rank_policy = "keep")
    )
    expect_true(fit_drop$rank_info$dropped_applied)
    expect_false(fit_keep$rank_info$dropped_applied)
    expect_true(any(is.na(stats::coef(fit_drop))))
    expect_false(any(is.na(stats::coef(fit_keep))))
})
