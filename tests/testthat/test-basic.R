test_that("fbrglm() can be called and returns the right class", {
    set.seed(1)
    df <- data.frame(
        y = rnorm(20),
        x1 = rnorm(20),
        x2 = rnorm(20)
    )
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "gaussian",
                  lambda = "fix", lambda_value = 0.1)
    expect_s3_class(fit, "fbrglm")
    expect_s3_class(fit, "regularized_glm")
    expect_false(inherits(fit, "glm"))
    expect_false(inherits(fit, "glmnet"))
})

test_that("unsupported family raises an error", {
    df <- data.frame(y = rnorm(10), x = rnorm(10))
    expect_error(
        fbrglm(y ~ x, data = df, family = "Gamma"),
        "not implemented"
    )
})

test_that("unsupported infer raises an error", {
    df <- data.frame(y = rnorm(10), x = rnorm(10))
    expect_error(
        fbrglm(y ~ x, data = df, family = "gaussian", infer = "selective"),
        "not implemented"
    )
    expect_error(
        fbrglm(y ~ x, data = df, family = "gaussian", infer = "split"),
        "not implemented"
    )
})

test_that("deferred families error distinctly", {
    df <- data.frame(y = rnorm(10), x = rnorm(10))
    expect_error(
        fbrglm(y ~ x, data = df, family = "multinomial"),
        "not implemented yet"
    )
    expect_error(
        fbrglm(y ~ x, data = df, family = "cox"),
        "not implemented yet"
    )
})

test_that("lambda = 'fix' without lambda_value raises an error", {
    df <- data.frame(y = rnorm(10), x = rnorm(10))
    expect_error(
        fbrglm(y ~ x, data = df, family = "gaussian",
               lambda = "fix", lambda_value = NULL),
        "lambda_value"
    )
})

test_that("x/y direct entry is rejected in the MVP", {
    expect_error(
        fbrglm(x = matrix(rnorm(20), 10, 2), y = rnorm(10)),
        "not implemented"
    )
})

test_that("lambda='fix' predictions match direct glmnet", {
    set.seed(42)
    n <- 100; p <- 5
    Xd <- matrix(rnorm(n * p), n, p)
    colnames(Xd) <- paste0("x", 1:p)
    y <- rnorm(n)
    df <- data.frame(y = y, Xd)

    fit_fbr <- fbrglm(y ~ x1 + x2 + x3 + x4 + x5, data = df,
                      family = "gaussian", lambda = "fix",
                      lambda_value = 0.1)
    fit_gln <- glmnet::glmnet(Xd, y, family = "gaussian",
                              alpha = 1, lambda = 0.1)

    pred_fbr <- predict(fit_fbr)
    pred_gln <- as.vector(predict(fit_gln, newx = Xd, s = 0.1))
    expect_equal(pred_fbr, pred_gln)
})

test_that("lambda='cv_min' matches cv.glmnet$lambda.min", {
    set.seed(0)
    n <- 200; p <- 5
    Xd <- matrix(rnorm(n * p), n, p)
    colnames(Xd) <- paste0("x", 1:p)
    y <- rnorm(n)
    df <- data.frame(y = y, Xd)

    set.seed(7)
    fit_fbr <- fbrglm(y ~ x1 + x2 + x3 + x4 + x5, data = df,
                      family = "gaussian", lambda = "cv_min")
    set.seed(7)
    cv <- glmnet::cv.glmnet(Xd, y, family = "gaussian", alpha = 1)

    expect_equal(fit_fbr$lambda_value, cv$lambda.min)
})

test_that("lambda='cv_1se' matches cv.glmnet$lambda.1se", {
    set.seed(0)
    n <- 200; p <- 5
    Xd <- matrix(rnorm(n * p), n, p)
    colnames(Xd) <- paste0("x", 1:p)
    y <- rnorm(n)
    df <- data.frame(y = y, Xd)

    set.seed(7)
    fit_fbr <- fbrglm(y ~ x1 + x2 + x3 + x4 + x5, data = df,
                      family = "gaussian", lambda = "cv_1se")
    set.seed(7)
    cv <- glmnet::cv.glmnet(Xd, y, family = "gaussian", alpha = 1)

    expect_equal(fit_fbr$lambda_value, cv$lambda.1se)
})

test_that("factor predictor fits successfully", {
    set.seed(1)
    n <- 100
    df <- data.frame(
        y = rnorm(n),
        x1 = rnorm(n),
        g = factor(sample(letters[1:3], n, replace = TRUE),
                   levels = letters[1:3])
    )
    fit <- fbrglm(y ~ x1 + g, data = df, family = "gaussian",
                  lambda = "fix", lambda_value = 0.1)
    expect_s3_class(fit, "fbrglm")
    expect_true(any(grepl("^g", fit$x_colnames)))
})

test_that("rank_info flags rank-deficient designs", {
    set.seed(40)
    n <- 80
    df <- data.frame(
        y  = rnorm(n),
        x1 = rnorm(n),
        x2 = rnorm(n)
    )
    df$x3 <- df$x1 + df$x2   # linearly dependent column
    expect_warning(
        fit <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                      lambda = "fix", lambda_value = 0.1),
        "rank-deficient"
    )
    expect_true(fit$rank_info$rank_deficient)
    expect_equal(fit$rank_info$ncol, 3L)
    expect_lt(fit$rank_info$rank, fit$rank_info$ncol)
    expect_length(fit$rank_info$pivot, 3L)
})

test_that("rank_info$rank_deficient is FALSE on a healthy design", {
    set.seed(41)
    n <- 80
    df <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n))
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "gaussian",
                  lambda = "fix", lambda_value = 0.1)
    expect_false(fit$rank_info$rank_deficient)
    expect_equal(fit$rank_info$rank, fit$rank_info$ncol)
})

test_that(".fbrglm_align_x pads missing, drops extra, reorders", {
    X <- matrix(c(10, 20, 30,
                  40, 50, 60), nrow = 3, byrow = FALSE)
    colnames(X) <- c("x1", "x_extra")
    target <- c("x1", "x_missing_1", "x_missing_2")
    out <- fbrglm:::.fbrglm_align_x(X, target)
    expect_equal(colnames(out), target)
    expect_equal(out[, "x1"], c(10, 20, 30))
    expect_true(all(out[, "x_missing_1"] == 0))
    expect_true(all(out[, "x_missing_2"] == 0))
    expect_false("x_extra" %in% colnames(out))
    expect_equal(nrow(out), 3L)
})

test_that("predict succeeds when newdata factor has narrowed levels", {
    set.seed(20)
    n_train <- 200
    train <- data.frame(
        y  = rnorm(n_train),
        x1 = rnorm(n_train),
        g  = factor(sample(c("A", "B", "C", "D"), n_train, replace = TRUE),
                    levels = c("A", "B", "C", "D"))
    )
    fit <- fbrglm(y ~ x1 + g, data = train, family = "gaussian",
                  lambda = "fix", lambda_value = 0.05)
    train_ncol <- length(fit$x_colnames)

    n_test <- 20
    test <- data.frame(
        x1 = rnorm(n_test),
        ## Narrow levels on purpose: factor only knows about A/B.
        g  = factor(sample(c("A", "B"), n_test, replace = TRUE),
                    levels = c("A", "B"))
    )
    pred <- predict(fit, newdata = test, type = "response")
    expect_length(pred, n_test)
    expect_true(all(is.finite(pred)))

    ## Walk the same internal path predict() takes, to confirm column
    ## alignment ends up matching the training width even when
    ## model.matrix() on the narrowed test data is narrower upstream.
    Terms <- stats::delete.response(fit$terms)
    mf <- stats::model.frame(Terms, test, xlev = fit$xlevels)
    Xt <- stats::model.matrix(Terms, mf, contrasts.arg = fit$contrasts)
    Xt <- Xt[, colnames(Xt) != "(Intercept)", drop = FALSE]
    Xt <- fbrglm:::.fbrglm_align_x(Xt, fit$x_colnames)
    expect_equal(ncol(Xt), train_ncol)
    expect_equal(colnames(Xt), fit$x_colnames)
})

test_that("predict works when newdata is missing some factor levels", {
    set.seed(2)
    n <- 100
    df <- data.frame(
        y = rnorm(n),
        x1 = rnorm(n),
        g = factor(sample(letters[1:3], n, replace = TRUE),
                   levels = letters[1:3])
    )
    fit <- fbrglm(y ~ x1 + g, data = df, family = "gaussian",
                  lambda = "fix", lambda_value = 0.1)

    nd <- data.frame(
        x1 = rnorm(10),
        g = factor(rep(c("a", "b"), 5), levels = letters[1:3])
    )
    pred <- predict(fit, newdata = nd)
    expect_length(pred, 10)
    expect_type(pred, "double")
})

test_that("nobs_info holds n_total / n_dropped_missing / n_used", {
    set.seed(3)
    n <- 30
    df <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n))
    df$y[1:3] <- NA
    fit <- suppressMessages(
        fbrglm(y ~ x1 + x2, data = df, family = "gaussian",
               lambda = "fix", lambda_value = 0.1)
    )
    expect_type(fit$nobs_info, "list")
    expect_equal(fit$nobs_info$n_total, n)
    expect_equal(fit$nobs_info$n_dropped_missing, 3L)
    expect_equal(fit$nobs_info$n_used, n - 3L)
    expect_equal(nobs(fit), n - 3L)
    ## summary() should surface the same structure.
    s <- summary(fit)
    expect_equal(s$nobs_info$n_total, n)
    expect_equal(s$nobs_info$n_dropped_missing, 3L)
    expect_equal(s$nobs_info$n_used, n - 3L)
})

test_that("predict type='response' for binomial is in [0,1]", {
    set.seed(4)
    n <- 100
    df <- data.frame(
        y = rbinom(n, 1, 0.5),
        x1 = rnorm(n), x2 = rnorm(n)
    )
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "binomial",
                  lambda = "fix", lambda_value = 0.05)
    pred <- predict(fit, type = "response")
    expect_true(all(pred >= 0 & pred <= 1))
})

test_that("predict type='class' for binomial is 0/1", {
    set.seed(5)
    n <- 100
    df <- data.frame(
        y = rbinom(n, 1, 0.5),
        x1 = rnorm(n), x2 = rnorm(n)
    )
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "binomial",
                  lambda = "fix", lambda_value = 0.05)
    pred <- predict(fit, type = "class")
    expect_true(all(pred %in% c(0, 1)))
})

test_that("predict type='class' errors for gaussian and poisson", {
    set.seed(6)
    n <- 50
    df_g <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n))
    fit_g <- fbrglm(y ~ x1 + x2, data = df_g, family = "gaussian",
                    lambda = "fix", lambda_value = 0.1)
    expect_error(predict(fit_g, type = "class"), "class")

    df_p <- data.frame(y = rpois(n, 2), x1 = rnorm(n), x2 = rnorm(n))
    fit_p <- fbrglm(y ~ x1 + x2, data = df_p, family = "poisson",
                    lambda = "fix", lambda_value = 0.1)
    expect_error(predict(fit_p, type = "class"), "class")
})

test_that("coef() returns the named coefficient vector", {
    set.seed(11)
    n <- 80
    df <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n))
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "gaussian",
                  lambda = "fix", lambda_value = 0.1)
    co <- coef(fit)
    expect_true(is.numeric(co))
    expect_true("(Intercept)" %in% names(co))
    expect_true(all(c("x1", "x2") %in% names(co)))
})

test_that("as_glmnet / as_cv_glmnet return the underlying objects", {
    set.seed(12)
    n <- 80
    df <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n))
    fit_fix <- fbrglm(y ~ x1 + x2, data = df, family = "gaussian",
                      lambda = "fix", lambda_value = 0.1)
    expect_s3_class(as_glmnet(fit_fix), "glmnet")
    expect_null(as_cv_glmnet(fit_fix))

    set.seed(13)
    fit_cv <- fbrglm(y ~ x1 + x2, data = df, family = "gaussian",
                     lambda = "cv_min")
    expect_s3_class(as_glmnet(fit_cv), "glmnet")
    expect_s3_class(as_cv_glmnet(fit_cv), "cv.glmnet")
})
