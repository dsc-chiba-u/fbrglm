#' Fit a Formula-Based Regularized GLM
#'
#' Fits a regularized generalized linear model with a formula/data interface
#' that mirrors base R's [stats::glm()] while delegating the actual penalized
#' fit to [glmnet::glmnet()] / [glmnet::cv.glmnet()].
#'
#' Current scope: `infer = "none"` only, with the same family argument
#' surface as `glmnet` itself. The character strings `"gaussian"`,
#' `"binomial"`, `"poisson"`, `"cox"`, `"multinomial"`, and `"mgaussian"`
#' are accepted; so are GLM family objects (e.g.
#' `stats::Gamma(link = "log")`, `MASS::negative.binomial(theta = 2)`).
#' Native Cox, multinomial, and mgaussian paths are exercised by the
#' tests but marked **experimental**: more unusual usage (Cox strata,
#' tie handling, time-varying covariates) is not yet validated. Joint
#' theta estimation in the spirit of `MASS::glm.nb()` is out of scope;
#' pass the desired theta to `MASS::negative.binomial()` directly.
#' `lambda` rules are `cv_min` / `cv_1se` / `fix`. Rank-deficient
#' designs are handled in
#' the spirit of [stats::glm()]: linearly dependent columns are dropped
#' via a QR pivot, the underlying glmnet fit only sees the independent
#' subset, and the dropped columns surface as `NA` in `coef()` /
#' `summary()`. Novel factor levels in `newdata` at predict time also
#' follow [stats::predict.glm()] by default -- an unseen level raises an
#' error. Production scoring pipelines can opt into
#' `predict(fit, newdata, on_new_levels = "na")` to set affected rows
#' to `NA` (with a warning) instead. Heavier features (split /
#' selective inference) are tracked in `TODO.md`.
#'
#' @param formula A model formula, e.g. `y ~ x1 + x2`. For Cox a
#'   `survival::Surv(time, status) ~ ...` LHS is accepted; for mgaussian
#'   the LHS is a matrix expression such as `cbind(y1, y2) ~ ...`.
#' @param data A data frame containing the variables in `formula`.
#' @param family A character string (`"gaussian"`, `"binomial"`,
#'   `"poisson"`, `"cox"`, `"multinomial"`, `"mgaussian"`), a GLM family
#'   object (e.g. `stats::Gamma(link = "log")`,
#'   `MASS::negative.binomial(theta = 2)`), or a bare family generator
#'   (e.g. `binomial`) -- the same surface `glmnet` itself accepts. Cox,
#'   multinomial, and mgaussian are supported but **experimental** (see
#'   Details).
#' @param weights Optional observation weights, passed to glmnet / cv.glmnet.
#' @param offset Optional offset vector, passed to glmnet / cv.glmnet.
#'   Reused at predict time when `newdata = NULL`; for `newdata`, supply
#'   `newoffset` to `predict()`.
#' @param infer Inference mode: `"none"`, `"split"`, or `"selective"`. Only
#'   `"none"` is implemented; the other two error.
#' @param selection_frac Selection-share for `infer = "split"` (default 0.2).
#'   Stored only; not yet used.
#' @param alpha Elastic-net mixing parameter, passed to glmnet.
#' @param lambda `lambda`-selection rule: `"cv_min"`, `"cv_1se"`, or
#'   `"fix"`.
#' @param lambda_value Numeric `lambda` used when `lambda = "fix"`.
#' @param x,y Optional pre-built design matrix and response. Not yet
#'   supported; supply `formula` + `data` instead.
#' @param ... Additional arguments forwarded to [glmnet::glmnet()] /
#'   [glmnet::cv.glmnet()] (`nlambda`, `nfolds`, `standardize`, ...).
#'
#' @return An object of class `c("fbrglm", "regularized_glm")` with
#'   fields including `family` (the value passed to glmnet -- a string or
#'   a family object), `family_name` (a short display string), `weights`,
#'   `offset`, `alpha`, `lambda_rule`, `lambda_value`, `infer`,
#'   `selection_frac`, `fit` (the underlying `glmnet` object), `cv_fit`
#'   (`cv.glmnet`, or `NULL` for `lambda = "fix"`), `coefficients`,
#'   `nonzero`, `terms`, `xlevels`, `contrasts`, `x_colnames`, `x_train`,
#'   `nobs_info` (`n_total` / `n_dropped_missing` / `n_used`), and
#'   `rank_info` (`rank` / `ncol` / `rank_deficient` / `pivot` /
#'   `kept_cols` / `dropped_cols`). When the design is rank-deficient,
#'   linearly dependent columns are dropped before fitting (in the
#'   spirit of [stats::glm()]); their entries in `coefficients` are
#'   reported as `NA` to distinguish "not identifiable" from
#'   "shrunk to zero by penalty".
#' @aliases print.fbrglm summary.fbrglm predict.fbrglm coef.fbrglm
#'   nobs.fbrglm plot.fbrglm print.summary.fbrglm
#' @importFrom stats nobs coef predict
#' @importFrom graphics plot
#' @export
fbrglm <- function(formula,
                   data,
                   family = c("gaussian", "binomial", "poisson"),
                   weights = NULL,
                   offset = NULL,
                   infer = c("none", "split", "selective"),
                   selection_frac = 0.2,
                   alpha = 1,
                   lambda = c("cv_min", "cv_1se", "fix"),
                   lambda_value = NULL,
                   x = NULL,
                   y = NULL,
                   ...) {
    call <- match.call()

    if (!is.null(x) || !is.null(y)) {
        stop("The x/y direct-matrix entry point is not implemented yet; ",
             "pass `formula` and `data` instead.", call. = FALSE)
    }
    if (missing(formula)) stop("`formula` is required.", call. = FALSE)
    if (missing(data)) stop("`data` is required.", call. = FALSE)

    ## --- Resolve family --------------------------------------------
    ## fbrglm accepts any family value glmnet itself accepts: the six
    ## canonical character strings and any glm `family` object. Bare
    ## family generators (e.g. `Gamma` without parentheses) are called
    ## to obtain a family object. We store both the value passed to
    ## glmnet (`family`) and a display name (`family_name`) used for
    ## printing, dispatch, and back-compat.
    char_known <- c("gaussian", "binomial", "poisson",
                    "cox", "multinomial", "mgaussian")
    if (is.character(family)) {
        family_name <- as.character(family)[1]
        if (!family_name %in% char_known) {
            stop(sprintf(
                "family '%s' is not a recognised glmnet character family. ",
                family_name),
                "Known character families: ",
                paste(char_known, collapse = ", "),
                ". For other GLM families, pass a family object, e.g. ",
                "stats::Gamma(link = 'log') or ",
                "MASS::negative.binomial(theta = 2).",
                call. = FALSE)
        }
        family_for_glmnet <- family_name
    } else if (inherits(family, "family")) {
        family_name <- family$family
        family_for_glmnet <- family
    } else if (is.function(family)) {
        f_obj <- tryCatch(family(), error = function(e) NULL)
        if (!inherits(f_obj, "family")) {
            stop("`family` must be a character string, a family object, ",
                 "or a function that returns a family object.",
                 call. = FALSE)
        }
        family_name <- f_obj$family
        family_for_glmnet <- f_obj
    } else {
        stop("`family` must be a character string, a family object, ",
             "or a function that returns a family object.",
             call. = FALSE)
    }

    lambda_rule <- match.arg(lambda, c("cv_min", "cv_1se", "fix"))
    if (lambda_rule == "fix" && is.null(lambda_value)) {
        stop("`lambda_value` must be provided when lambda = \"fix\".",
             call. = FALSE)
    }

    infer_mode <- match.arg(infer, c("none", "split", "selective"))
    if (infer_mode != "none") {
        stop(sprintf(
            "infer = '%s' is not implemented yet. Only 'none' is supported.",
            infer_mode), call. = FALSE)
    }

    n_total <- nrow(data)
    mf_call <- match.call(expand.dots = FALSE)
    m <- match(c("formula", "data", "weights", "offset"),
               names(mf_call), 0L)
    mf_call <- mf_call[c(1L, m)]
    mf_call$drop.unused.levels <- TRUE
    mf_call[[1L]] <- quote(stats::model.frame)
    mf <- eval(mf_call, parent.frame())

    n_used <- nrow(mf)
    n_dropped_missing <- n_total - n_used
    if (n_dropped_missing > 0L) {
        message(sprintf(
            "fbrglm: dropped %d row(s) with missing values (%d / %d kept).",
            n_dropped_missing, n_used, n_total))
    }

    Terms <- attr(mf, "terms")
    y_vec <- stats::model.response(mf)
    w_vec <- stats::model.weights(mf)
    o_vec <- stats::model.offset(mf)

    X_full <- stats::model.matrix(Terms, mf)
    contrasts_used <- attr(X_full, "contrasts")
    intercept_idx <- which(colnames(X_full) == "(Intercept)")
    X <- if (length(intercept_idx)) {
        X_full[, -intercept_idx, drop = FALSE]
    } else {
        X_full
    }
    x_colnames <- colnames(X)
    xlevels <- stats::.getXlevels(Terms, mf)

    ## Rank-deficiency check, glm()-style. stats::glm.fit / lm.fit run a
    ## column-pivoted QR (LINPACK's dqrls with tol = 1e-7) on the full
    ## design matrix INCLUDING the intercept. Because glmnet handles the
    ## intercept itself, we work on the intercept-stripped X but center
    ## each column first: rank(scale(X, center = TRUE)) equals
    ## rank(cbind(1, X)) - 1, so the deficiency set is identical to
    ## what glm() would report, while the intercept never has to compete
    ## for a slot in the pivot. The independent subset is taken as
    ## `pivot[1:rank]` (sorted to preserve the user's original column
    ## order), matching glm()'s coefficient layout. Dropped columns get
    ## NA at coef() time below.
    ncol_full <- ncol(X)
    if (ncol_full > 0L) {
        X_centered <- sweep(X, 2L, colMeans(X), "-", check.margin = FALSE)
        qrout      <- qr(X_centered, tol = 1e-7)
    } else {
        qrout <- list(rank = 0L, pivot = integer(0))
    }
    rank_deficient <- qrout$rank < ncol_full
    if (rank_deficient) {
        keep_idx     <- sort(qrout$pivot[seq_len(qrout$rank)])
        kept_cols    <- x_colnames[keep_idx]
        dropped_cols <- x_colnames[-keep_idx]
        X_fit        <- X[, keep_idx, drop = FALSE]
        message(sprintf(
            "fbrglm: dropped %d linearly dependent column(s) (rank %d / %d): %s. ",
            length(dropped_cols), qrout$rank, ncol_full,
            paste(dropped_cols, collapse = ", ")),
            "Their coefficients will be reported as NA, as in stats::glm().")
    } else {
        keep_idx     <- seq_len(ncol_full)
        kept_cols    <- x_colnames
        dropped_cols <- character(0)
        X_fit        <- X
    }
    rank_info <- list(
        rank           = qrout$rank,
        ncol           = ncol_full,
        rank_deficient = rank_deficient,
        pivot          = qrout$pivot,
        kept_cols      = kept_cols,
        dropped_cols   = dropped_cols
    )

    glmnet_args <- list(x = X_fit, y = y_vec,
                        family = family_for_glmnet, alpha = alpha)
    if (!is.null(w_vec)) glmnet_args$weights <- as.numeric(w_vec)
    if (!is.null(o_vec)) glmnet_args$offset <- as.numeric(o_vec)
    extra <- list(...)
    glmnet_args[names(extra)] <- extra

    if (lambda_rule == "fix") {
        glmnet_args$lambda <- lambda_value
        fit <- do.call(glmnet::glmnet, glmnet_args)
        cv_fit <- NULL
        chosen_lambda <- lambda_value
    } else {
        cv_fit <- do.call(glmnet::cv.glmnet, glmnet_args)
        fit <- cv_fit$glmnet.fit
        chosen_lambda <- if (lambda_rule == "cv_min") {
            cv_fit$lambda.min
        } else {
            cv_fit$lambda.1se
        }
    }

    co_obj <- if (!is.null(cv_fit)) {
        stats::coef(cv_fit, s = chosen_lambda)
    } else {
        stats::coef(fit, s = chosen_lambda)
    }
    ## Most families return a (sparse) matrix; multinomial / mgaussian
    ## return a list of matrices. Keep the structure and derive nonzero
    ## only for the simple matrix case. When the design was
    ## rank-deficient, glmnet only saw kept_cols; expand back to the
    ## full (Intercept) + x_colnames layout with NA at dropped
    ## positions, matching glm()'s "not defined because of
    ## singularities" convention.
    full_names <- c("(Intercept)", x_colnames)
    if (is.list(co_obj) && !inherits(co_obj, "Matrix")) {
        if (rank_deficient) {
            co <- lapply(co_obj, function(m) {
                out <- matrix(NA_real_, nrow = length(full_names),
                              ncol = ncol(m),
                              dimnames = list(full_names, colnames(m)))
                out[rownames(m), ] <- as.matrix(m)
                out
            })
        } else {
            co <- co_obj
        }
        nonzero <- character(0)
    } else {
        co_named <- as.numeric(co_obj)
        names(co_named) <- rownames(co_obj)
        if (rank_deficient) {
            co <- rep(NA_real_, length(full_names))
            names(co) <- full_names
            co[names(co_named)] <- co_named
        } else {
            co <- co_named
        }
        nonzero <- setdiff(names(co)[!is.na(co) & co != 0], "(Intercept)")
    }

    nobs_info <- list(
        n_total = n_total,
        n_dropped_missing = n_dropped_missing,
        n_used = n_used
    )

    out <- list(
        call = call,
        formula = formula,
        terms = Terms,
        xlevels = xlevels,
        contrasts = contrasts_used,
        x_colnames = x_colnames,
        x_train = X_fit,
        y_train = y_vec,
        family = family_for_glmnet,
        family_name = family_name,
        weights = w_vec,
        offset = o_vec,
        alpha = alpha,
        lambda_rule = lambda_rule,
        lambda_value = chosen_lambda,
        infer = infer_mode,
        selection_frac = selection_frac,
        fit = fit,
        cv_fit = cv_fit,
        coefficients = co,
        nonzero = nonzero,
        rank_info = rank_info,
        nobs_info = nobs_info,
        ## Top-level mirrors kept for backwards compatibility; prefer
        ## `nobs_info` going forward.
        n_total = n_total,
        n_dropped_missing = n_dropped_missing,
        n_used = n_used,
        nobs = n_used
    )
    class(out) <- c("fbrglm", "regularized_glm")
    out
}

#' Extract the Underlying glmnet Fit
#'
#' Returns the raw `glmnet` object stored inside an `fbrglm` model. For a
#' `lambda = "fix"` fit this is the direct [glmnet::glmnet()] return; for
#' a CV fit it is the underlying `glmnet.fit` (`cv_fit$glmnet.fit`).
#'
#' @param object An `fbrglm` object.
#' @param ... Ignored.
#' @return A `glmnet` object, or `NULL` if no fit has been attached yet.
#' @export
as_glmnet <- function(object, ...) {
    if (!inherits(object, "fbrglm")) {
        stop("`object` must be an 'fbrglm' object.", call. = FALSE)
    }
    object$fit
}

#' Extract the Underlying cv.glmnet Fit
#'
#' Returns the raw `cv.glmnet` object stored inside an `fbrglm` model. This
#' is `NULL` when the model was fit with `lambda = "fix"`.
#'
#' @param object An `fbrglm` object.
#' @param ... Ignored.
#' @return A `cv.glmnet` object, or `NULL`.
#' @export
as_cv_glmnet <- function(object, ...) {
    if (!inherits(object, "fbrglm")) {
        stop("`object` must be an 'fbrglm' object.", call. = FALSE)
    }
    object$cv_fit
}
