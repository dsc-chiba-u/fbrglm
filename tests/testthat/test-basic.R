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

test_that("unsupported character family raises a helpful error", {
    df <- data.frame(y = rnorm(10), x1 = rnorm(10), x2 = rnorm(10))
    expect_error(
        fbrglm(y ~ x1 + x2, data = df, family = "Banana",
               lambda = "fix", lambda_value = 0.1),
        "recognised glmnet character family"
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

test_that("rank-deficient designs auto-drop linearly dependent columns", {
    set.seed(40)
    n <- 80
    df <- data.frame(
        y  = rnorm(n),
        x1 = rnorm(n),
        x2 = rnorm(n)
    )
    df$x3 <- df$x1 + df$x2   # linearly dependent column
    expect_message(
        fit <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                      lambda = "fix", lambda_value = 0.1),
        "linearly dependent"
    )
    expect_true(fit$rank_info$rank_deficient)
    expect_equal(fit$rank_info$ncol, 3L)
    expect_lt(fit$rank_info$rank, fit$rank_info$ncol)
    expect_length(fit$rank_info$pivot, 3L)
    expect_equal(length(fit$rank_info$kept_cols), fit$rank_info$rank)
    expect_equal(length(fit$rank_info$dropped_cols),
                 fit$rank_info$ncol - fit$rank_info$rank)
    expect_setequal(c(fit$rank_info$kept_cols, fit$rank_info$dropped_cols),
                    fit$x_colnames)
})

test_that("coef() returns NA at dropped positions and matches full layout", {
    set.seed(42)
    n <- 80
    df <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n))
    df$x3 <- df$x1 + df$x2
    suppressMessages(
        fit <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                      lambda = "fix", lambda_value = 0.1)
    )
    co <- coef(fit)
    expect_equal(names(co), c("(Intercept)", "x1", "x2", "x3"))
    dropped <- fit$rank_info$dropped_cols
    expect_true(all(is.na(co[dropped])))
    kept <- fit$rank_info$kept_cols
    expect_true(all(!is.na(co[kept])))
    expect_false(is.na(co["(Intercept)"]))
    expect_false(any(is.na(fit$nonzero)))
})

test_that("predict() works on rank-deficient fits for both training and new data", {
    set.seed(43)
    n <- 80
    df <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n))
    df$x3 <- df$x1 + df$x2
    suppressMessages(
        fit <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                      lambda = "fix", lambda_value = 0.1)
    )
    p_train <- predict(fit)
    expect_length(p_train, n)
    expect_false(anyNA(p_train))
    p_new <- predict(fit, newdata = df[seq_len(10), ])
    expect_length(p_new, 10L)
    expect_false(anyNA(p_new))
})

test_that("rank_info$rank_deficient is FALSE on a healthy design", {
    set.seed(41)
    n <- 80
    df <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n))
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "gaussian",
                  lambda = "fix", lambda_value = 0.1)
    expect_false(fit$rank_info$rank_deficient)
    expect_equal(fit$rank_info$rank, fit$rank_info$ncol)
    expect_equal(fit$rank_info$kept_cols, fit$x_colnames)
    expect_equal(fit$rank_info$dropped_cols, character(0))
})

test_that("summary() renders a glm-style Estimate table with NA at dropped positions", {
    set.seed(44)
    n <- 60
    df <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n))
    df$x3 <- df$x1 + df$x2
    suppressMessages(
        fit <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                      lambda = "fix", lambda_value = 0.1)
    )
    out <- capture.output(print(summary(fit)))
    txt <- paste(out, collapse = "\n")
    expect_match(txt, "Estimate", fixed = TRUE)
    expect_match(txt, "(1 not defined because of singularities: x3)",
                 fixed = TRUE)
    expect_match(txt, format(fit$lambda_value), fixed = TRUE)
})

test_that("summary() prints the inference-policy footer", {
    set.seed(45)
    n <- 60
    df <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n))
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "gaussian",
                  lambda = "fix", lambda_value = 0.1)
    txt <- paste(capture.output(print(summary(fit))), collapse = "\n")
    expect_match(txt, "no standard errors", fixed = TRUE)
    expect_match(txt, "shrinkage bias", fixed = TRUE)
    expect_match(txt, "data-driven\nselection of lambda", fixed = TRUE)
})

test_that("summary() omits the singularity note when the design is healthy", {
    set.seed(46)
    n <- 60
    df <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n))
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "gaussian",
                  lambda = "fix", lambda_value = 0.1)
    txt <- paste(capture.output(print(summary(fit))), collapse = "\n")
    expect_false(grepl("not defined because of singularities", txt,
                       fixed = TRUE))
    expect_match(txt, "Coefficients:\n", fixed = TRUE)
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

test_that("predict errors on novel factor levels by default (glm-strict)", {
    set.seed(50)
    train <- data.frame(
        y  = rbinom(200, 1, 0.5),
        x1 = rnorm(200),
        g  = factor(sample(c("A", "B"), 200, replace = TRUE),
                    levels = c("A", "B"))
    )
    test_wider <- data.frame(
        x1 = rnorm(10),
        g  = factor(c("A", "B", "C", "D", "A", "C", "B", "D", "A", "C"),
                    levels = c("A", "B", "C", "D"))
    )
    suppressMessages(
        fit <- fbrglm(y ~ x1 + g, data = train, family = "binomial",
                      lambda = "fix", lambda_value = 0.05)
    )
    ## stats::model.frame() raises a locale-dependent message
    ## (in English: "factor X has new levels ..."; other R locales
    ## translate it), so the test only asserts that an error is
    ## raised rather than matching the message text.
    expect_error(
        predict(fit, newdata = test_wider, type = "response")
    )
})

test_that("predict on_new_levels = 'na' returns NA for novel-level rows with warning", {
    set.seed(51)
    train <- data.frame(
        y  = rbinom(200, 1, 0.5),
        x1 = rnorm(200),
        g  = factor(sample(c("A", "B"), 200, replace = TRUE),
                    levels = c("A", "B"))
    )
    test_wider <- data.frame(
        x1 = rnorm(10),
        g  = factor(c("A", "B", "C", "D", "A", "C", "B", "D", "A", "C"),
                    levels = c("A", "B", "C", "D"))
    )
    suppressMessages(
        fit <- fbrglm(y ~ x1 + g, data = train, family = "binomial",
                      lambda = "fix", lambda_value = 0.05)
    )
    novel_mask <- as.character(test_wider$g) %in% c("C", "D")
    expect_warning(
        pred <- predict(fit, newdata = test_wider, type = "response",
                        on_new_levels = "na"),
        "predict.fbrglm:.*not seen in training"
    )
    expect_length(pred, nrow(test_wider))
    expect_true(all(is.na(pred[novel_mask])))
    expect_true(all(is.finite(pred[!novel_mask])))
})

test_that("predict on_new_levels = 'na' also masks type = 'class' output", {
    set.seed(52)
    train <- data.frame(
        y  = rbinom(200, 1, 0.5),
        x1 = rnorm(200),
        g  = factor(sample(c("A", "B"), 200, replace = TRUE),
                    levels = c("A", "B"))
    )
    test_wider <- data.frame(
        x1 = rnorm(5),
        g  = factor(c("A", "B", "C", "D", "A"), levels = c("A", "B", "C", "D"))
    )
    suppressMessages(
        fit <- fbrglm(y ~ x1 + g, data = train, family = "binomial",
                      lambda = "fix", lambda_value = 0.05)
    )
    suppressWarnings(
        cls <- predict(fit, newdata = test_wider, type = "class",
                       on_new_levels = "na")
    )
    expect_length(cls, 5L)
    expect_true(all(is.na(cls[c(3, 4)])))
    expect_true(all(!is.na(cls[c(1, 2, 5)])))
})

test_that("predict on_new_levels = 'na' is a no-op when all levels are familiar", {
    set.seed(53)
    train <- data.frame(
        y  = rbinom(200, 1, 0.5),
        x1 = rnorm(200),
        g  = factor(sample(c("A", "B"), 200, replace = TRUE),
                    levels = c("A", "B"))
    )
    test_safe <- data.frame(
        x1 = rnorm(10),
        g  = factor(sample(c("A", "B"), 10, replace = TRUE),
                    levels = c("A", "B"))
    )
    suppressMessages(
        fit <- fbrglm(y ~ x1 + g, data = train, family = "binomial",
                      lambda = "fix", lambda_value = 0.05)
    )
    expect_silent(
        pred <- predict(fit, newdata = test_safe, type = "response",
                        on_new_levels = "na")
    )
    expect_length(pred, 10L)
    expect_true(all(is.finite(pred)))
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

test_that("plot.fbrglm defaults to glm-style diagnostic panels", {
    set.seed(80)
    n <- 200
    df <- data.frame(
        y  = rnorm(n),
        x1 = rnorm(n), x2 = rnorm(n), x3 = rnorm(n)
    )
    fit <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                  lambda = "cv_min")
    tf <- tempfile(fileext = ".png")
    grDevices::png(tf)
    on.exit({ grDevices::dev.off(); unlink(tf) }, add = TRUE)
    expect_no_error(plot(fit))                 # default what = "diagnostic"
    expect_no_error(plot(fit, which = 1L))     # single panel
})

test_that("plot.fbrglm what='path' delegates to plot.glmnet", {
    set.seed(81)
    n <- 200
    df <- data.frame(
        y  = rnorm(n),
        x1 = rnorm(n), x2 = rnorm(n), x3 = rnorm(n)
    )
    fit <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                  lambda = "fix", lambda_value = 0.1)
    tf <- tempfile(fileext = ".png")
    grDevices::png(tf)
    on.exit({ grDevices::dev.off(); unlink(tf) }, add = TRUE)
    expect_no_error(plot(fit, what = "path"))
})

test_that("plot.fbrglm what='cv' delegates to plot.cv.glmnet", {
    set.seed(82)
    n <- 200
    df <- data.frame(
        y  = rnorm(n),
        x1 = rnorm(n), x2 = rnorm(n), x3 = rnorm(n)
    )
    fit <- fbrglm(y ~ x1 + x2 + x3, data = df, family = "gaussian",
                  lambda = "cv_1se")
    tf <- tempfile(fileext = ".png")
    grDevices::png(tf)
    on.exit({ grDevices::dev.off(); unlink(tf) }, add = TRUE)
    expect_no_error(plot(fit, what = "cv"))
})

test_that("plot.fbrglm errors on what='cv' when no cv.glmnet was attached", {
    set.seed(83)
    n <- 80
    df <- data.frame(y = rnorm(n), x1 = rnorm(n), x2 = rnorm(n))
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "gaussian",
                  lambda = "fix", lambda_value = 0.05)
    expect_error(plot(fit, what = "cv"), "cv\\.glmnet")
})

test_that("plot.fbrglm errors when no fit is attached", {
    fake <- structure(list(fit = NULL, cv_fit = NULL),
                      class = c("fbrglm", "regularized_glm"))
    expect_error(plot(fake), "no glmnet")
})

test_that("predict respects offset when newdata is NULL", {
    set.seed(90)
    n <- 100
    df <- data.frame(y  = rbinom(n, 1, 0.5),
                     x1 = rnorm(n), x2 = rnorm(n))
    off <- rnorm(n, sd = 0.3)
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "binomial",
                  offset = off,
                  lambda = "fix", lambda_value = 0.05)
    pred <- predict(fit, type = "response")
    expect_length(pred, n)
    expect_true(all(pred >= 0 & pred <= 1))
})

test_that("predict errors when offset model is given newdata without newoffset", {
    set.seed(91)
    n <- 100
    df <- data.frame(y  = rbinom(n, 1, 0.5),
                     x1 = rnorm(n), x2 = rnorm(n))
    off <- rnorm(n, sd = 0.3)
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "binomial",
                  offset = off,
                  lambda = "fix", lambda_value = 0.05)
    nd <- data.frame(x1 = rnorm(10), x2 = rnorm(10))
    expect_error(predict(fit, newdata = nd, type = "response"),
                 "newoffset")
})

test_that("predict works on newdata with matching newoffset", {
    set.seed(92)
    n <- 100
    df <- data.frame(y  = rbinom(n, 1, 0.5),
                     x1 = rnorm(n), x2 = rnorm(n))
    off <- rnorm(n, sd = 0.3)
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "binomial",
                  offset = off,
                  lambda = "fix", lambda_value = 0.05)
    nd <- data.frame(x1 = rnorm(10), x2 = rnorm(10))
    new_off <- rnorm(10, sd = 0.3)
    pred <- predict(fit, newdata = nd, newoffset = new_off,
                    type = "response")
    expect_length(pred, 10)
    expect_true(all(pred >= 0 & pred <= 1))
})

test_that("predict errors when newoffset length is wrong", {
    set.seed(93)
    n <- 100
    df <- data.frame(y  = rbinom(n, 1, 0.5),
                     x1 = rnorm(n), x2 = rnorm(n))
    off <- rnorm(n, sd = 0.3)
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "binomial",
                  offset = off,
                  lambda = "fix", lambda_value = 0.05)
    nd <- data.frame(x1 = rnorm(10), x2 = rnorm(10))
    expect_error(
        predict(fit, newdata = nd, newoffset = rnorm(5),
                type = "response"),
        "newoffset"
    )
})

test_that("type='class' respects newoffset", {
    set.seed(94)
    n <- 100
    df <- data.frame(y  = rbinom(n, 1, 0.5),
                     x1 = rnorm(n), x2 = rnorm(n))
    off <- rnorm(n, sd = 0.3)
    fit <- fbrglm(y ~ x1 + x2, data = df, family = "binomial",
                  offset = off,
                  lambda = "fix", lambda_value = 0.05)
    nd <- data.frame(x1 = rnorm(10), x2 = rnorm(10))
    new_off <- rnorm(10, sd = 0.3)
    pred <- predict(fit, newdata = nd, newoffset = new_off,
                    type = "class")
    expect_length(pred, 10)
    expect_true(all(pred %in% c(0, 1)))
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

## Regression tests for the failure modes called out in the manuscript's
## Motivating problems section: interaction-term column dropout under a
## narrowed test factor, session-level options("contrasts") changes
## between fit and predict, and saveRDS round-trips. fbrglm's contract
## across all three is that the prediction-time design matrix is
## reconstructed from the fit object alone, not from current session
## state.

test_that("predict handles y ~ x1 * g when newdata factor narrows", {
    set.seed(60)
    train <- data.frame(
        y  = rnorm(120),
        x1 = rnorm(120),
        g  = factor(sample(c("A", "B", "C"), 120, replace = TRUE),
                    levels = c("A", "B", "C"))
    )
    test_narrow <- data.frame(
        x1 = rnorm(15),
        g  = factor(sample(c("A", "B"), 15, replace = TRUE),
                    levels = c("A", "B"))
    )
    fit <- fbrglm(y ~ x1 * g, data = train, family = "gaussian",
                  lambda = "fix", lambda_value = 0.05)
    ## Train design has 5 columns: x1, gB, gC, x1:gB, x1:gC.
    ## A naive model.matrix on the narrowed test would only emit
    ## x1, gB, x1:gB (3 columns) — fbrglm must reconstruct 5.
    expect_equal(length(fit$x_colnames), 5L)
    p <- predict(fit, newdata = test_narrow, type = "response")
    expect_length(p, nrow(test_narrow))
    expect_true(all(is.finite(p)))
})

test_that("predict is invariant to session-level options('contrasts')", {
    set.seed(61)
    train <- data.frame(
        y  = rnorm(100),
        x1 = rnorm(100),
        g  = factor(sample(c("A", "B", "C"), 100, replace = TRUE),
                    levels = c("A", "B", "C"))
    )
    new_dat <- data.frame(
        x1 = rnorm(20),
        g  = factor(sample(c("A", "B", "C"), 20, replace = TRUE),
                    levels = c("A", "B", "C"))
    )

    ## Fit under the package default (contr.treatment).
    opts_in <- options(contrasts = c("contr.treatment", "contr.poly"))
    on.exit(options(opts_in), add = TRUE)
    fit <- fbrglm(y ~ x1 + g, data = train, family = "gaussian",
                  lambda = "fix", lambda_value = 0.05)
    p_treat <- predict(fit, newdata = new_dat, type = "response")

    ## Flip the session contrasts. fbrglm's stored contrasts attribute
    ## should make predict() ignore the change.
    options(contrasts = c("contr.sum", "contr.poly"))
    p_sum <- predict(fit, newdata = new_dat, type = "response")
    expect_equal(p_treat, p_sum)

    ## And as a sharper sanity check, predict on the training rows
    ## under the flipped contrasts must agree with the canonical
    ## (newdata = NULL) train prediction.
    p_train_nullnew <- predict(fit, type = "response")
    p_train_newdat  <- predict(fit, newdata = train, type = "response")
    expect_equal(p_train_nullnew, p_train_newdat)
})

test_that("saveRDS / readRDS round-trip preserves predictions", {
    set.seed(62)
    train <- data.frame(
        y  = rnorm(100),
        x1 = rnorm(100),
        g  = factor(sample(c("A", "B", "C"), 100, replace = TRUE),
                    levels = c("A", "B", "C"))
    )
    new_dat <- data.frame(
        x1 = rnorm(15),
        g  = factor(sample(c("A", "B", "C"), 15, replace = TRUE),
                    levels = c("A", "B", "C"))
    )
    fit_orig <- fbrglm(y ~ x1 + g, data = train, family = "gaussian",
                       lambda = "fix", lambda_value = 0.05)
    p_orig <- predict(fit_orig, newdata = new_dat, type = "response")

    rds_path <- tempfile(fileext = ".rds")
    on.exit(unlink(rds_path), add = TRUE)
    saveRDS(fit_orig, rds_path)

    ## Reload under a flipped session contrasts setting to verify
    ## the round-trip is robust to global state.
    opts_in <- options(contrasts = c("contr.sum", "contr.poly"))
    on.exit(options(opts_in), add = TRUE)
    fit_reloaded <- readRDS(rds_path)
    expect_s3_class(fit_reloaded, "fbrglm")

    p_reloaded <- predict(fit_reloaded, newdata = new_dat,
                          type = "response")
    expect_equal(p_orig, p_reloaded)

    ## Coefficient vector also bit-identical across the round trip.
    expect_equal(coef(fit_orig), coef(fit_reloaded))
})
