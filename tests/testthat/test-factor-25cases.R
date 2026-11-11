## -----------------------------------------------------------------------
## Nishiuchi's 25-case factor-handling specification (paper/revise/Nishiuchi.md).
## This file is diagnostic: expectations come from the SPEC, not from the
## current implementation. A FAIL here does not mean the test is wrong;
## it means the current implementation diverges from the spec, which the
## reviewer response needs to address explicitly.
## -----------------------------------------------------------------------

mk_train_abc <- function(n = 120, seed = 1, fam = "gaussian") {
    set.seed(seed)
    df <- data.frame(
        y  = if (fam == "binomial") rbinom(n, 1, 0.5) else rnorm(n),
        x1 = rnorm(n),
        g  = factor(sample(c("A", "B", "C"), n, replace = TRUE),
                    levels = c("A", "B", "C"))
    )
    df
}

fit_abc <- function(train, fam = "gaussian") {
    suppressMessages(
        fbrglm(y ~ x1 + g, data = train, family = fam,
               lambda = "fix", lambda_value = 0.05)
    )
}

## =======================================================================
## A. Factor levels: preservation / loss
## =======================================================================

test_that("A1: ordinary subset preserves unused factor levels and predict works", {
    train <- mk_train_abc()
    fit   <- fit_abc(train)
    ## Subset out all "C" rows. R preserves levels on a subset.
    test <- train[train$g != "C", c("x1", "g")]
    expect_equal(levels(test$g), c("A", "B", "C"))   # spec: 3-level factor preserved
    p <- predict(fit, newdata = test, type = "response")
    expect_length(p, nrow(test))
    expect_true(all(is.finite(p)))
})

test_that("A2: droplevels(test) still predicts via stored xlevels", {
    train <- mk_train_abc()
    fit   <- fit_abc(train)
    test_raw   <- train[train$g != "C", c("x1", "g")]
    test_drop  <- droplevels(test_raw)
    expect_equal(levels(test_drop$g), c("A", "B"))   # droplevels erased "C"
    p1 <- predict(fit, newdata = test_raw,  type = "response")
    p2 <- predict(fit, newdata = test_drop, type = "response")
    expect_equal(p1, p2)                             # spec: same predictions
})

test_that("A3: character-to-factor regenerated independently predicts correctly", {
    train <- mk_train_abc()
    fit   <- fit_abc(train)
    ## Test data loaded as character, then factor()'d locally — levels
    ## will be whichever categories happen to be present, not the
    ## training triplet.
    test_chr <- data.frame(
        x1 = rnorm(5),
        g  = c("A", "B", "A", "B", "A"),
        stringsAsFactors = FALSE
    )
    test_chr$g <- factor(test_chr$g)                # yields levels c("A","B")
    expect_equal(levels(test_chr$g), c("A", "B"))
    p <- predict(fit, newdata = test_chr, type = "response")
    expect_length(p, 5)
    expect_true(all(is.finite(p)))
})

test_that("A4: independently CSV-reloaded test data predicts correctly", {
    train <- mk_train_abc()
    fit   <- fit_abc(train)
    tmp <- tempfile(fileext = ".csv")
    on.exit(unlink(tmp), add = TRUE)
    test_src <- data.frame(x1 = rnorm(6),
                           g  = c("A", "B", "A", "B", "A", "B"))
    utils::write.csv(test_src, tmp, row.names = FALSE)
    test_back <- utils::read.csv(tmp, stringsAsFactors = FALSE)
    test_back$g <- factor(test_back$g)              # independent factor()
    p <- predict(fit, newdata = test_back, type = "response")
    expect_length(p, 6)
    expect_true(all(is.finite(p)))
})

test_that("A5: test data with a single factor level predicts correctly", {
    train <- mk_train_abc()
    fit   <- fit_abc(train)
    test_one <- data.frame(
        x1 = rnorm(4),
        g  = factor(rep("A", 4), levels = c("A", "B", "C"))
    )
    p <- predict(fit, newdata = test_one, type = "response")
    expect_length(p, 4)
    expect_true(all(is.finite(p)))
})

## =======================================================================
## B. Encoding / column correspondence
## =======================================================================

test_that("B1: reversed level order in test yields identical predictions per category", {
    train <- mk_train_abc()
    fit   <- fit_abc(train)
    cats <- c("A", "B", "C")
    test_fwd <- data.frame(
        x1 = rep(0.5, 3),
        g  = factor(cats, levels = c("A", "B", "C"))
    )
    test_rev <- data.frame(
        x1 = rep(0.5, 3),
        g  = factor(cats, levels = c("C", "B", "A"))   # order reversed
    )
    p_fwd <- predict(fit, newdata = test_fwd, type = "response")
    p_rev <- predict(fit, newdata = test_rev, type = "response")
    expect_equal(p_fwd, p_rev)   # spec: same category -> same prediction
})

test_that("B2: different reference level in test still encoded via stored contrasts", {
    train <- mk_train_abc()
    fit   <- fit_abc(train)
    cats <- c("A", "B", "C")
    base_test <- data.frame(x1 = rep(0.3, 3), g = factor(cats))
    rebased   <- data.frame(
        x1 = rep(0.3, 3),
        g  = stats::relevel(factor(cats), ref = "B")
    )
    p1 <- predict(fit, newdata = base_test, type = "response")
    p2 <- predict(fit, newdata = rebased,   type = "response")
    expect_equal(p1, p2)
})

test_that("B3: predict works when newdata lacks the training reference level", {
    train <- mk_train_abc()
    fit   <- fit_abc(train)
    ## Training reference is "A" (first level). Make a test without any "A".
    test <- data.frame(
        x1 = rnorm(4),
        g  = factor(c("B", "C", "B", "C"), levels = c("A", "B", "C"))
    )
    p <- predict(fit, newdata = test, type = "response")
    expect_length(p, 4)
    expect_true(all(is.finite(p)))
})

test_that("B4: predict invariant to session options('contrasts')", {
    ## Cross-reference: test-basic.R:671 ('predict is invariant to session-level
    ## options('contrasts')') already covers the contr.treatment vs contr.sum
    ## flip across saveRDS, so this slot is marked covered.
    expect_true(TRUE)
})

test_that("B5: two factors with different level structures predict correctly", {
    set.seed(201)
    n <- 150
    train <- data.frame(
        y  = rnorm(n),
        x1 = rnorm(n),
        g1 = factor(sample(c("a", "b", "c"), n, replace = TRUE),
                    levels = c("a", "b", "c")),
        g2 = factor(sample(c("X", "Y"), n, replace = TRUE),
                    levels = c("X", "Y"))
    )
    fit <- suppressMessages(
        fbrglm(y ~ x1 + g1 + g2, data = train,
               family = "gaussian", lambda = "fix", lambda_value = 0.05)
    )
    ## Test factors have DIFFERENT subsets of levels.
    test <- data.frame(
        x1 = rnorm(6),
        g1 = factor(c("a", "b", "b", "a", "b", "a"),
                    levels = c("a", "b", "c")),
        g2 = factor(c("Y", "Y", "Y", "Y", "Y", "Y"),
                    levels = c("X", "Y"))                # g2 has only "Y"
    )
    p <- predict(fit, newdata = test, type = "response")
    expect_length(p, 6)
    expect_true(all(is.finite(p)))
})

test_that("B6: factor + numeric mix keeps column order and finite predictions", {
    set.seed(202)
    n <- 120
    train <- data.frame(
        y   = rnorm(n),
        age = rnorm(n),
        region = factor(sample(c("E", "W", "N"), n, replace = TRUE),
                        levels = c("E", "W", "N"))
    )
    fit <- suppressMessages(
        fbrglm(y ~ age + region, data = train,
               family = "gaussian", lambda = "fix", lambda_value = 0.05)
    )
    expect_true("age" %in% fit$x_colnames)
    expect_true(any(grepl("^region", fit$x_colnames)))
    test <- data.frame(
        age    = rnorm(10),
        region = factor(sample(c("E", "W"), 10, replace = TRUE),
                        levels = c("E", "W", "N"))
    )
    p <- predict(fit, newdata = test, type = "response")
    expect_length(p, 10)
    expect_true(all(is.finite(p)))
})

test_that("B7: formula-internal factor() is round-trippable at predict time", {
    set.seed(203)
    n <- 120
    train <- data.frame(
        y      = rnorm(n),
        x1     = rnorm(n),
        region = sample(c("E", "W", "N"), n, replace = TRUE)   # character
    )
    fit <- suppressMessages(
        fbrglm(y ~ x1 + factor(region), data = train,
               family = "gaussian", lambda = "fix", lambda_value = 0.05)
    )
    test <- data.frame(
        x1     = rnorm(5),
        region = c("E", "W", "E", "W", "N")                    # still character
    )
    p <- predict(fit, newdata = test, type = "response")
    expect_length(p, 5)
    expect_true(all(is.finite(p)))
})

## =======================================================================
## C. Unseen levels and missing values
## =======================================================================

test_that("C1: wholly-unseen category raises an error under default (error)", {
    ## Cross-reference: test-basic.R:249 ('predict errors on novel factor
    ## levels by default (glm-strict)') already covers this.
    expect_true(TRUE)
})

test_that("C2: on_new_levels='na' returns NA only for unseen-level rows", {
    ## Cross-reference: test-basic.R:275 ('predict on_new_levels = "na"
    ## returns NA for novel-level rows with warning') already covers this.
    expect_true(TRUE)
})

test_that("C3: mixed seen/unseen rows preserve row-order correspondence", {
    train <- mk_train_abc(seed = 301)
    fit   <- fit_abc(train)
    test <- data.frame(
        x1 = c(0.1, 0.2, 0.3, 0.4, 0.5),
        g  = factor(c("A", "Z", "B", "Q", "A"),
                    levels = c("A", "B", "Z", "Q"))
    )
    suppressWarnings(
        pred <- predict(fit, newdata = test, type = "response",
                        on_new_levels = "na")
    )
    expect_length(pred, 5)
    expect_true(is.na(pred[2]) && is.na(pred[4]))
    expect_true(all(is.finite(pred[c(1, 3, 5)])))
})

test_that("C4: observation with ANY unseen factor is masked under na policy", {
    set.seed(304)
    n <- 150
    train <- data.frame(
        y  = rnorm(n),
        x1 = rnorm(n),
        g1 = factor(sample(c("a", "b"), n, replace = TRUE),
                    levels = c("a", "b")),
        g2 = factor(sample(c("X", "Y"), n, replace = TRUE),
                    levels = c("X", "Y"))
    )
    fit <- suppressMessages(
        fbrglm(y ~ x1 + g1 + g2, data = train,
               family = "gaussian", lambda = "fix", lambda_value = 0.05)
    )
    ## Row 2 has g1 known but g2 UNSEEN ("Z"). The whole row's
    ## prediction must be NA under the spec.
    test <- data.frame(
        x1 = c(0, 0, 0),
        g1 = factor(c("a", "a", "b"), levels = c("a", "b")),
        g2 = factor(c("X", "Z", "Y"), levels = c("X", "Y", "Z"))
    )
    suppressWarnings(
        pred <- predict(fit, newdata = test, type = "response",
                        on_new_levels = "na")
    )
    expect_length(pred, 3)
    expect_true(is.na(pred[2]))
    expect_true(all(is.finite(pred[c(1, 3)])))
})

test_that("C5: ordinary NA in a factor yields NA prediction for that row", {
    train <- mk_train_abc(seed = 305)
    fit   <- fit_abc(train)
    test <- data.frame(
        x1 = c(0.1, 0.2, 0.3),
        g  = factor(c("A", NA_character_, "B"), levels = c("A", "B", "C"))
    )
    ## Spec: NA follows the missing-value policy and the row's prediction
    ## is itself NA (predict must not drop the row and misalign output).
    pred <- predict(fit, newdata = test, type = "response")
    expect_length(pred, 3)
    expect_true(is.na(pred[2]))
    expect_true(all(is.finite(pred[c(1, 3)])))
})

test_that("C6: level defined but never observed at fit time is retained in xlevels", {
    set.seed(306)
    n <- 80
    train <- data.frame(
        y  = rnorm(n),
        x1 = rnorm(n),
        ## Factor DEFINES level "C" but no row is C.
        g  = factor(sample(c("A", "B"), n, replace = TRUE),
                    levels = c("A", "B", "C"))
    )
    fit <- suppressMessages(
        fbrglm(y ~ x1 + g, data = train,
               family = "gaussian", lambda = "fix", lambda_value = 0.05)
    )
    ## Spec: fit$xlevels keeps the full user-declared level set,
    ## even if drop.unused.levels drops unused dummies from design.
    expect_equal(fit$xlevels$g, c("A", "B", "C"))
    ## And predict on a row that uses the previously-unobserved "C" level
    ## must succeed (as a known level), NOT be treated as unseen.
    test <- data.frame(
        x1 = c(0, 0, 0),
        g  = factor(c("A", "B", "C"), levels = c("A", "B", "C"))
    )
    pred <- predict(fit, newdata = test, type = "response")
    expect_length(pred, 3)
    expect_true(all(is.finite(pred)))
})

test_that("C7: 'NA' as a level name is distinguished from real NA", {
    set.seed(307)
    n <- 100
    g_values <- sample(c("A", "NA"), n, replace = TRUE)
    train <- data.frame(
        y  = rnorm(n),
        x1 = rnorm(n),
        g  = factor(g_values, levels = c("A", "NA"))     # literal "NA" string
    )
    fit <- suppressMessages(
        fbrglm(y ~ x1 + g, data = train,
               family = "gaussian", lambda = "fix", lambda_value = 0.05)
    )
    expect_true("NA" %in% fit$xlevels$g)
    ## Mixed row: one row with literal "NA" string level, one row with real NA.
    test <- data.frame(
        x1 = c(0.1, 0.2),
        g  = factor(c("NA", NA_character_), levels = c("A", "NA"))
    )
    pred <- predict(fit, newdata = test, type = "response")
    expect_length(pred, 2)
    expect_true(is.finite(pred[1]))      # literal "NA" category => finite
    expect_true(is.na(pred[2]))          # real NA => NA
})

## =======================================================================
## D. Edge cases
## =======================================================================

test_that("D1: single-level factor at fit time behaves per spec", {
    set.seed(401)
    n <- 60
    train <- data.frame(
        y  = rnorm(n),
        x1 = rnorm(n),
        g  = factor(rep("A", n), levels = "A")
    )
    ## Spec: either (a) fit raises a clear error, or (b) the single-level
    ## column is silently dropped (no contrast possible) and the fit
    ## proceeds on the remaining predictors. Both are acceptable per
    ## Nishiuchi D1 ("仕様に沿ったエラーまたは処理"); a silent fit with
    ## wrong semantics (e.g. a spurious column) is not.
    out <- tryCatch(
        suppressMessages(
            fbrglm(y ~ x1 + g, data = train, family = "gaussian",
                   lambda = "fix", lambda_value = 0.05)
        ),
        error = function(e) e
    )
    if (inherits(out, "error")) {
        expect_true(nzchar(conditionMessage(out)))
    } else {
        expect_s3_class(out, "fbrglm")
        ## The constant factor cannot produce a usable contrast column.
        expect_false(any(grepl("^g", out$x_colnames)))
    }
})

test_that("D2: ordered factor is preserved and predict round-trips", {
    set.seed(402)
    n <- 100
    train <- data.frame(
        y  = rnorm(n),
        x1 = rnorm(n),
        g  = factor(sample(c("low", "mid", "high"), n, replace = TRUE),
                    levels = c("low", "mid", "high"),
                    ordered = TRUE)
    )
    fit <- suppressMessages(
        fbrglm(y ~ x1 + g, data = train,
               family = "gaussian", lambda = "fix", lambda_value = 0.05)
    )
    ## Spec: xlevels records the ordered level sequence AS ordered.
    expect_equal(fit$xlevels$g, c("low", "mid", "high"))
    test <- data.frame(
        x1 = rnorm(6),
        g  = factor(sample(c("low", "mid", "high"), 6, replace = TRUE),
                    levels = c("low", "mid", "high"), ordered = TRUE)
    )
    p <- predict(fit, newdata = test, type = "response")
    expect_length(p, 6)
    expect_true(all(is.finite(p)))
})

test_that("D3: special-char / unicode level names survive round-trip", {
    set.seed(403)
    n <- 80
    lvls <- c("   spaced", "あい", "x+y")       # ASCII-escaped Hiragana
    train <- data.frame(
        y  = rnorm(n),
        x1 = rnorm(n),
        g  = factor(sample(lvls, n, replace = TRUE), levels = lvls)
    )
    fit <- suppressMessages(
        fbrglm(y ~ x1 + g, data = train,
               family = "gaussian", lambda = "fix", lambda_value = 0.05)
    )
    expect_equal(fit$xlevels$g, lvls)
    test <- data.frame(
        x1 = rnorm(3),
        g  = factor(lvls, levels = lvls)
    )
    p <- predict(fit, newdata = test, type = "response")
    expect_length(p, 3)
    expect_true(all(is.finite(p)))
})

test_that("D4: predict output preserves input row names and row order", {
    train <- mk_train_abc(seed = 404)
    fit   <- fit_abc(train)
    test <- data.frame(
        x1 = c(0.5, 0.6, 0.7, 0.8, 0.9),
        g  = factor(c("A", "Z", "B", "A", "B"),
                    levels = c("A", "B", "Z")),
        row.names = c("r1", "r2", "r3", "r4", "r5")
    )
    suppressWarnings(
        pred <- predict(fit, newdata = test, type = "response",
                        on_new_levels = "na")
    )
    expect_length(pred, 5)
    expect_true(is.na(pred[2]))
    expect_true(all(is.finite(pred[c(1, 3, 4, 5)])))
    ## If pred is a named vector, names should align with test row.names.
    if (!is.null(names(pred))) {
        expect_equal(names(pred), rownames(test))
    } else {
        succeed()
    }
})

test_that("D5: saveRDS/readRDS roundtrip predictions", {
    ## Cross-reference: test-basic.R:706 ('saveRDS / readRDS round-trip
    ## preserves predictions') already covers this.
    expect_true(TRUE)
})

test_that("D6: factor predictor works across supported families", {
    set.seed(406)
    n <- 150
    df <- data.frame(
        x1 = rnorm(n),
        g  = factor(sample(c("A", "B", "C"), n, replace = TRUE),
                    levels = c("A", "B", "C"))
    )
    df$y_gauss <- rnorm(n)
    df$y_bin   <- rbinom(n, 1, 0.5)
    df$y_pois  <- rpois(n, 2)

    f_gauss <- suppressMessages(
        fbrglm(y_gauss ~ x1 + g, data = df, family = "gaussian",
               lambda = "fix", lambda_value = 0.05)
    )
    f_bin   <- suppressMessages(
        fbrglm(y_bin ~ x1 + g, data = df, family = "binomial",
               lambda = "fix", lambda_value = 0.05)
    )
    f_pois  <- suppressMessages(
        fbrglm(y_pois ~ x1 + g, data = df, family = "poisson",
               lambda = "fix", lambda_value = 0.05)
    )
    nd <- data.frame(
        x1 = rnorm(6),
        g  = factor(sample(c("A", "B", "C"), 6, replace = TRUE),
                    levels = c("A", "B", "C"))
    )
    expect_true(all(is.finite(predict(f_gauss, newdata = nd, type = "response"))))
    expect_true(all(is.finite(predict(f_bin,   newdata = nd, type = "response"))))
    expect_true(all(is.finite(predict(f_pois,  newdata = nd, type = "response"))))
})
