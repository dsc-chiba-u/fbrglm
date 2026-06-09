## Align a design matrix `X` to a target column layout.
##
## Missing columns (present in `target_cols` but not in `X`) are added
## as all-zero columns; extra columns (present in `X` but not in
## `target_cols`) are dropped; the result is reordered to match
## `target_cols` exactly.
##
## Novel factor levels are the caller's problem: this helper sees a
## ready-made matrix and assumes upstream `model.frame(..., xlev = ...)`
## has already rejected anything that can't be encoded.
.fbrglm_align_x <- function(X, target_cols) {
    missing_cols <- setdiff(target_cols, colnames(X))
    if (length(missing_cols)) {
        pad <- matrix(0, nrow = nrow(X), ncol = length(missing_cols))
        colnames(pad) <- missing_cols
        X <- cbind(X, pad)
    }
    X[, target_cols, drop = FALSE]
}

## Internal helper: read nobs info from either the new $nobs_info list
## or the legacy top-level fields.
.fbrglm_nobs_info <- function(object) {
    if (!is.null(object$nobs_info)) {
        return(object$nobs_info)
    }
    list(
        n_total = object$n_total,
        n_dropped_missing = object$n_dropped_missing,
        n_used = object$n_used %||% object$nobs
    )
}

`%||%` <- function(a, b) if (is.null(a)) b else a

#' @export
print.fbrglm <- function(x, ...) {
    cat("Formula-based regularized GLM (fbrglm)\n")
    if (!is.null(x$call)) {
        cat("\nCall:\n")
        print(x$call)
    }
    cat("\nFamily:        ", x$family, "\n", sep = "")
    cat("Alpha:         ", x$alpha, "\n", sep = "")
    cat("Lambda rule:   ", x$lambda_rule, "\n", sep = "")
    cat("Lambda value:  ", format(x$lambda_value), "\n", sep = "")
    cat("Inference:     ", x$infer, "\n", sep = "")
    ni <- .fbrglm_nobs_info(x)
    if (!is.null(ni$n_total)) {
        cat(sprintf("Observations:  total = %d, dropped = %d, used = %d\n",
                    ni$n_total, ni$n_dropped_missing, ni$n_used))
    }
    if (!is.null(x$nonzero)) {
        cat(sprintf("Non-zero terms: %d / %d\n",
                    length(x$nonzero), length(x$x_colnames)))
    }
    invisible(x)
}

#' @export
summary.fbrglm <- function(object, ...) {
    ni <- .fbrglm_nobs_info(object)
    structure(
        list(
            call = object$call,
            family = object$family,
            infer = object$infer,
            selection_frac = object$selection_frac,
            coefficients = object$coefficients,
            nonzero = object$nonzero,
            lambda_value = object$lambda_value,
            lambda_method = object$lambda_rule,
            nobs_info = ni,
            rank_info = object$rank_info
        ),
        class = "summary.fbrglm"
    )
}

#' @export
print.summary.fbrglm <- function(x, ...) {
    cat("fbrglm summary\n")
    cat("==============\n")
    if (!is.null(x$call)) {
        cat("\nCall:\n")
        print(x$call)
    }
    cat("\nFamily:        ", x$family, "\n", sep = "")
    cat("Lambda method: ", x$lambda_method, "\n", sep = "")
    cat("Lambda value:  ", format(x$lambda_value), "\n", sep = "")
    cat("Inference:     ", x$infer, "\n", sep = "")
    ni <- x$nobs_info
    cat("\nObservations:\n")
    cat(sprintf("  total = %d, dropped (missing) = %d, used = %d\n",
                ni$n_total, ni$n_dropped_missing, ni$n_used))
    cat("\nCoefficients (including zeros):\n")
    print(x$coefficients)
    cat(sprintf("\nNon-zero predictors (%d):\n", length(x$nonzero)))
    if (length(x$nonzero)) {
        cat("  ", paste(x$nonzero, collapse = ", "), "\n", sep = "")
    } else {
        cat("  (none)\n")
    }
    invisible(x)
}

#' @export
predict.fbrglm <- function(object,
                           newdata = NULL,
                           type = c("link", "response", "class"),
                           ...) {
    type <- match.arg(type)

    if (is.null(newdata)) {
        X <- object$x_train
    } else {
        Terms <- stats::delete.response(object$terms)
        mf <- stats::model.frame(Terms, newdata, xlev = object$xlevels)
        X_full <- stats::model.matrix(Terms, mf,
                                      contrasts.arg = object$contrasts)
        intercept_idx <- which(colnames(X_full) == "(Intercept)")
        X <- if (length(intercept_idx)) {
            X_full[, -intercept_idx, drop = FALSE]
        } else {
            X_full
        }
        ## Pad missing columns with zeros, drop extras, reorder.
        ## Novel factor levels would already have errored inside
        ## model.frame() above.
        X <- .fbrglm_align_x(X, object$x_colnames)
    }

    fit_for_predict <- if (!is.null(object$cv_fit)) {
        object$cv_fit
    } else {
        object$fit
    }
    s <- object$lambda_value

    if (type == "class") {
        if (!object$family %in% c("binomial", "multinomial")) {
            stop(sprintf(
                "type = 'class' is valid only for binomial / multinomial; got '%s'.",
                object$family), call. = FALSE)
        }
        if (object$family == "binomial") {
            prob <- stats::predict(fit_for_predict, newx = X, s = s,
                                   type = "response")
            return(as.numeric(as.vector(prob) >= 0.5))
        }
        raw <- stats::predict(fit_for_predict, newx = X, s = s,
                              type = "class")
        return(as.vector(raw))
    }

    pred <- stats::predict(fit_for_predict, newx = X, s = s, type = type)
    as.vector(pred)
}

#' @export
coef.fbrglm <- function(object, ...) {
    object$coefficients
}

#' @export
nobs.fbrglm <- function(object, ...) {
    ni <- .fbrglm_nobs_info(object)
    ni$n_used
}

#' @export
plot.fbrglm <- function(x, ...) {
    if (!is.null(x$cv_fit)) {
        plot(x$cv_fit, ...)
    } else if (!is.null(x$fit)) {
        plot(x$fit, ...)
    } else {
        stop("plot.fbrglm(): no glmnet / cv.glmnet fit attached to this object.",
             call. = FALSE)
    }
    invisible(x)
}
