## broom-compatible tidy() / glance() methods on fbrglm fits.

test_that("tidy() returns the expected columns for a single-response fit", {
    set.seed(100)
    n <- 200
    df <- data.frame(y = rbinom(n, 1, 0.5),
                     x1 = rnorm(n), x2 = rnorm(n))
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "binomial",
                  lambda = "fix", lambda_value = 0.01)
    out <- tidy(fit)
    expect_s3_class(out, "tbl_df")
    expect_named(out, c("term", "estimate", "nonzero", "lambda"))
    expect_setequal(out$term, c("(Intercept)", "x1", "x2"))
    expect_true(all(is.finite(out$estimate)))
    expect_true(all(out$lambda == fit$lambda_value))
})

test_that("tidy() reports rank-deficient columns as NA in estimate", {
    set.seed(101)
    n <- 80
    df <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n))
    df$x3 <- df$x1 + df$x2
    suppressMessages(
        fit <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                      lambda = "fix", lambda_value = 0.05)
    )
    out <- tidy(fit)
    expect_true(any(is.na(out$estimate[out$term == "x3"])))
    expect_false(any(out$nonzero[out$term == "x3"]))
})

test_that("tidy() emits a long form for multinomial fits", {
    set.seed(102)
    n <- 200
    df <- data.frame(
        y  = factor(sample(c("A", "B", "C"), n, replace = TRUE)),
        x1 = rnorm(n), x2 = rnorm(n))
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "multinomial",
                  lambda = "fix", lambda_value = 0.05)
    out <- tidy(fit)
    expect_s3_class(out, "tbl_df")
    expect_true("class" %in% names(out))
    expect_setequal(out$class, c("A", "B", "C"))
    expect_setequal(out$term[out$class == "A"],
                    c("(Intercept)", "x1", "x2"))
})

test_that("glance() returns a single-row tibble with the expected fields", {
    set.seed(103)
    n <- 200
    df <- data.frame(y = rbinom(n, 1, 0.5),
                     x1 = rnorm(n), x2 = rnorm(n))
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "binomial",
                  lambda = "fix", lambda_value = 0.05)
    g <- glance(fit)
    expect_s3_class(g, "tbl_df")
    expect_equal(nrow(g), 1L)
    expected <- c("family", "lambda_rule", "lambda", "alpha", "infer",
                  "nobs", "nobs_dropped", "nobs_total",
                  "rank", "rank_dropped", "rank_deficient",
                  "nonzero", "deviance", "cvm_at_lambda",
                  "cvsd_at_lambda", "logLik", "AIC", "BIC")
    expect_true(all(expected %in% names(g)))
    expect_equal(g$family, "binomial")
    expect_equal(g$lambda_rule, "fix")
    expect_equal(g$lambda, fit$lambda_value)
    expect_equal(g$nobs, fit$nobs_info$n_used)
    expect_true(is.na(g$cvm_at_lambda))
})

test_that("glance() exposes cv stats when the model was fit with CV", {
    set.seed(104)
    n <- 200
    df <- data.frame(y = rbinom(n, 1, 0.5),
                     x1 = rnorm(n), x2 = rnorm(n))
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "binomial",
                  lambda = "cv_min")
    g <- glance(fit)
    expect_false(is.na(g$cvm_at_lambda))
    expect_false(is.na(g$cvsd_at_lambda))
    expect_equal(g$lambda_rule, "cv_min")
})

test_that("glance() reports rank-deficient status with the dropped count", {
    set.seed(105)
    n <- 80
    df <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n))
    df$x3 <- df$x1 + df$x2
    suppressMessages(
        fit <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                      lambda = "fix", lambda_value = 0.05)
    )
    g <- glance(fit)
    expect_true(g$rank_deficient)
    expect_equal(g$rank_dropped, 1L)
})
