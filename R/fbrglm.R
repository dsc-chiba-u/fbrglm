#' Fit a Formula-Based Regularized GLM
#'
#' Fits a regularized generalized linear model with a formula/data interface
#' that mirrors base R's [stats::glm()] while delegating the actual penalized
#' fit to [glmnet::glmnet()] / [glmnet::cv.glmnet()].
#'
#' MVP scope: `infer = "none"`, families `gaussian` / `binomial` / `poisson`,
#' λ rules `cv_min` / `cv_1se` / `fix`. Heavier features (split / selective
#' inference, multinomial / cox, rank-deficient column dropping) are tracked
#' in `TODO.md`.
#'
#' @param formula A model formula, e.g. `y ~ x1 + x2`.
#' @param data A data frame containing the variables in `formula`.
#' @param family One of `"gaussian"`, `"binomial"`, `"poisson"`. Accepted as a
#'   character string, a family generator (e.g. `binomial`), or a family
#'   object (e.g. `binomial()`). `"multinomial"` and `"cox"` are reserved by
#'   the spec but not yet implemented and will error.
#' @param weights Optional observation weights, passed to glmnet / cv.glmnet.
#' @param offset Optional offset vector, passed to glmnet / cv.glmnet.
#' @param infer Inference mode: `"none"`, `"split"`, or `"selective"`. Only
#'   `"none"` is implemented in the MVP.
#' @param selection_frac Selection-share for `infer = "split"` (default 0.2).
#'   Stored only; not yet used.
#' @param alpha Elastic-net mixing parameter, passed to glmnet.
#' @param lambda λ-selection rule: `"cv_min"`, `"cv_1se"`, or `"fix"`.
#' @param lambda_value Numeric λ used when `lambda = "fix"`.
#' @param x,y Optional pre-built design matrix and response. Not yet
#'   supported in the MVP; supply `formula` + `data` instead.
#' @param ... Additional arguments forwarded to [glmnet::glmnet()] /
#'   [glmnet::cv.glmnet()] (`nlambda`, `nfolds`, `standardize`, ...).
#'
#' @return An object of class `c("fbrglm", "regularized_glm")` with fields
#'   `coefficients`, `lambda_value`, `lambda_rule`, `nonzero`, `fit`,
#'   `cv_fit`, `terms`, `xlevels`, `contrasts`, `x_colnames`, `x_train`,
#'   `nobs_info`, `rank_info`, etc.
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

    qrout <- qr(X)
    rank_info <- list(
        rank           = qrout$rank,
        ncol           = ncol(X),
        rank_deficient = qrout$rank < ncol(X),
        pivot          = qrout$pivot
    )
    if (rank_info$rank_deficient) {
        warning(sprintf(
            "Design matrix is rank-deficient: rank %d < %d columns. ",
            rank_info$rank, rank_info$ncol),
            "Columns are not dropped in this MVP; see TODO.md.",
            call. = FALSE)
    }

    glmnet_args <- list(x = X, y = y_vec,
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
    ## only for the simple matrix case.
    if (is.list(co_obj) && !inherits(co_obj, "Matrix")) {
        co <- co_obj
        nonzero <- character(0)
    } else {
        co <- as.numeric(co_obj)
        names(co) <- rownames(co_obj)
        nonzero <- setdiff(names(co)[co != 0], "(Intercept)")
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
        x_train = X,
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
