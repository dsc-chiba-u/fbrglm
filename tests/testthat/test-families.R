## Family-coverage tests. The goal is to exercise every glmnet-compatible
## family that fbrglm now passes through (gaussian, binomial, poisson,
## Cox, Gamma, negative binomial, plus the multi-response cases
## multinomial and mgaussian) and to lock in the behaviours that aren't
## yet supported (Cox + type='class').

test_that("gaussian fit + predict works", {
    set.seed(101)
    n <- 100
    df <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n))
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "gaussian",
                  lambda = "fix", lambda_value = 0.05)
    expect_equal(fit$family_name, "gaussian")
    expect_length(predict(fit, type = "response"), n)
})

test_that("binomial fit + predict response/class works", {
    set.seed(102)
    n <- 120
    df <- data.frame(y  = rbinom(n, 1, 0.5),
                     x1 = rnorm(n), x2 = rnorm(n))
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "binomial",
                  lambda = "fix", lambda_value = 0.05)
    p_resp <- predict(fit, type = "response")
    expect_true(all(p_resp >= 0 & p_resp <= 1))
    p_class <- predict(fit, type = "class")
    expect_true(all(p_class %in% c(0, 1)))
})

test_that("poisson fit + predict works", {
    set.seed(103)
    n <- 100
    df <- data.frame(y  = rpois(n, 2),
                     x1 = rnorm(n), x2 = rnorm(n))
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "poisson",
                  lambda = "fix", lambda_value = 0.05)
    pred <- predict(fit, type = "response")
    expect_length(pred, n)
    expect_true(all(pred > 0))
})

test_that("Gamma(link='log') family object fits and predicts", {
    set.seed(104)
    n <- 100
    df <- data.frame(y  = rgamma(n, shape = 2, rate = 1),
                     x1 = rnorm(n), x2 = rnorm(n))
    fit <- fbrglm(y ~ x1 + x2, data = df,
                  family = stats::Gamma(link = "log"),
                  lambda = "fix", lambda_value = 0.05)
    expect_equal(fit$family_name, "Gamma")
    pred <- predict(fit, type = "response")
    expect_length(pred, n)
    expect_true(all(pred > 0))
})

test_that("MASS::negative.binomial(theta = 2) fits and predicts", {
    skip_if_not_installed("MASS")
    set.seed(105)
    n <- 100
    df <- data.frame(y  = rnbinom(n, mu = 2, size = 2),
                     x1 = rnorm(n), x2 = rnorm(n))
    fit <- fbrglm(y ~ x1 + x2, data = df,
                  family = MASS::negative.binomial(theta = 2),
                  lambda = "fix", lambda_value = 0.05)
    expect_match(fit$family_name, "Negative Binomial")
    pred <- predict(fit, type = "response")
    expect_length(pred, n)
})

test_that("Cox (family='cox', Surv LHS) fits and predicts link/response", {
    skip_if_not_installed("survival")
    set.seed(106)
    n <- 100
    x1 <- rnorm(n); x2 <- rnorm(n)
    eta <- 0.3 * x1 - 0.2 * x2
    t_event <- rexp(n, exp(eta))
    t_obs   <- pmin(t_event, 3)
    delta   <- as.integer(t_event <= 3)
    df <- data.frame(t_obs = t_obs, delta = delta, x1 = x1, x2 = x2)
    suppressWarnings({
        fit <- fbrglm(survival::Surv(t_obs, delta) ~ x1 + x2,
                      data = df, family = "cox",
                      lambda = "fix", lambda_value = 0.05)
    })
    expect_equal(fit$family_name, "cox")
    pred <- suppressWarnings(predict(fit, type = "link"))
    expect_length(pred, n)
    pred_r <- suppressWarnings(predict(fit, type = "response"))
    expect_length(pred_r, n)
})

test_that("Cox rejects type='class'", {
    skip_if_not_installed("survival")
    set.seed(107)
    n <- 60
    x1 <- rnorm(n); x2 <- rnorm(n)
    t_event <- rexp(n, exp(0.2 * x1))
    t_obs   <- pmin(t_event, 3)
    delta   <- as.integer(t_event <= 3)
    df <- data.frame(t_obs = t_obs, delta = delta, x1 = x1, x2 = x2)
    suppressWarnings({
        fit <- fbrglm(survival::Surv(t_obs, delta) ~ x1 + x2,
                      data = df, family = "cox",
                      lambda = "fix", lambda_value = 0.05)
    })
    expect_error(predict(fit, type = "class"), "class")
})

test_that("multinomial fits and predicts (experimental)", {
    set.seed(108)
    n <- 150
    df <- data.frame(
        y  = factor(sample(c("a", "b", "c"), n, replace = TRUE)),
        x1 = rnorm(n), x2 = rnorm(n)
    )
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "multinomial",
                  lambda = "fix", lambda_value = 0.05)
    expect_equal(fit$family_name, "multinomial")
    p_resp <- predict(fit, type = "response")
    expect_true(is.matrix(p_resp))
    expect_equal(nrow(p_resp), n)
    expect_equal(ncol(p_resp), 3L)
    p_class <- predict(fit, type = "class")
    expect_length(p_class, n)
    expect_true(all(p_class %in% levels(df$y)))
})

test_that("mgaussian fits and predicts (experimental)", {
    set.seed(109)
    n <- 100
    df <- data.frame(
        y1 = rnorm(n), y2 = rnorm(n),
        x1 = rnorm(n), x2 = rnorm(n)
    )
    fit <- fbrglm(cbind(y1, y2) ~ x1 + x2, data = df,
                  family = "mgaussian",
                  lambda = "fix", lambda_value = 0.05)
    expect_equal(fit$family_name, "mgaussian")
    pred <- predict(fit, type = "response")
    expect_true(is.matrix(pred) || is.array(pred))
    expect_equal(nrow(pred), n)
    expect_equal(ncol(pred), 2L)
})

test_that("print/summary survive family objects", {
    set.seed(110)
    n <- 80
    df <- data.frame(y  = rgamma(n, 2, 1),
                     x1 = rnorm(n), x2 = rnorm(n))
    fit <- fbrglm(y ~ x1 + x2, data = df,
                  family = stats::Gamma(link = "log"),
                  lambda = "fix", lambda_value = 0.05)
    expect_no_error(capture.output(print(fit)))
    expect_no_error(capture.output(print(summary(fit))))
})

test_that("tidy() and glance() work across the supported families", {
    fits <- list()
    set.seed(120)
    n <- 100
    base <- data.frame(x1 = rnorm(n), x2 = rnorm(n))

    df_g <- cbind(base, y = rnorm(n))
    fits$gaussian <- fbrglm(y ~ x1 + x2, data = df_g, family = "gaussian",
                            lambda = "fix", lambda_value = 0.05)
    df_b <- cbind(base, y = rbinom(n, 1, 0.5))
    fits$binomial <- fbrglm(y ~ x1 + x2, data = df_b, family = "binomial",
                            lambda = "fix", lambda_value = 0.05)
    df_p <- cbind(base, y = rpois(n, lambda = 1))
    fits$poisson  <- fbrglm(y ~ x1 + x2, data = df_p, family = "poisson",
                            lambda = "fix", lambda_value = 0.05)
    df_gam <- cbind(base, y = rgamma(n, 2, 1))
    fits$gamma <- fbrglm(y ~ x1 + x2, data = df_gam,
                         family = stats::Gamma(link = "log"),
                         lambda = "fix", lambda_value = 0.05)
    if (requireNamespace("MASS", quietly = TRUE)) {
        fits$negbin <- fbrglm(
            y ~ x1 + x2, data = df_p,
            family = MASS::negative.binomial(theta = 2),
            lambda = "fix", lambda_value = 0.05)
    }
    if (requireNamespace("survival", quietly = TRUE)) {
        df_cox <- cbind(base,
                        time  = rexp(n, rate = 0.5),
                        event = rbinom(n, 1, 0.7))
        fits$cox <- fbrglm(survival::Surv(time, event) ~ x1 + x2,
                           data = df_cox, family = "cox",
                           lambda = "fix", lambda_value = 0.05)
    }
    df_mn <- cbind(base, y = factor(sample(LETTERS[1:3], n, replace = TRUE)))
    fits$multinomial <- fbrglm(y ~ x1 + x2, data = df_mn,
                               family = "multinomial",
                               lambda = "fix", lambda_value = 0.05)
    df_mg <- cbind(base, y1 = rnorm(n), y2 = rnorm(n))
    fits$mgaussian <- fbrglm(cbind(y1, y2) ~ x1 + x2, data = df_mg,
                             family = "mgaussian",
                             lambda = "fix", lambda_value = 0.05)

    for (nm in names(fits)) {
        out_t <- expect_no_error(tidy(fits[[nm]]))
        expect_s3_class(out_t, "tbl_df")
        expect_true(all(c("term", "estimate", "nonzero", "lambda")
                        %in% names(out_t)))
        out_g <- expect_no_error(glance(fits[[nm]]))
        expect_equal(nrow(out_g), 1L)
        expect_true(out_g$family %in% c("gaussian", "binomial", "poisson",
                                        "Gamma", "Negative Binomial(2)",
                                        "cox", "multinomial", "mgaussian"))
    }
})
