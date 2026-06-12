## Build a short, printable label for an fbrglm object's family. The
## `family` slot may be a character string or a glm `family` object
## (which is a list); reach for `family_name` first and fall back
## safely so cat()/print() never see a raw list.
.fbrglm_family_label <- function(object) {
    if (!is.null(object$family_name) &&
        is.character(object$family_name) &&
        length(object$family_name) == 1L) {
        return(object$family_name)
    }
    fam <- object$family
    if (is.character(fam) && length(fam) >= 1L) return(fam[1])
    if (inherits(fam, "family") && is.character(fam$family)) {
        return(fam$family)
    }
    "<family>"
}

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
    cat("\nFamily:        ", .fbrglm_family_label(x), "\n", sep = "")
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
    ri <- x$rank_info
    if (isTRUE(ri$rank_deficient)) {
        cat(sprintf("Rank deficiency: %d / %d columns dropped (NA in coef): %s\n",
                    length(ri$dropped_cols), ri$ncol,
                    paste(ri$dropped_cols, collapse = ", ")))
    }
    invisible(x)
}

#' @export
summary.fbrglm <- function(object, ...) {
    ni <- .fbrglm_nobs_info(object)
    structure(
        list(
            call = object$call,
            family = .fbrglm_family_label(object),
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
    cat("\nFamily:        ", .fbrglm_family_label(x), "\n", sep = "")
    cat("Lambda method: ", x$lambda_method, "\n", sep = "")
    cat("Lambda value:  ", format(x$lambda_value), "\n", sep = "")
    cat("Inference:     ", x$infer, "\n", sep = "")
    ni <- x$nobs_info
    cat("\nObservations:\n")
    cat(sprintf("  total = %d, dropped (missing) = %d, used = %d\n",
                ni$n_total, ni$n_dropped_missing, ni$n_used))

    ri <- x$rank_info
    rd <- isTRUE(ri$rank_deficient)
    header <- if (rd) {
        sprintf("Coefficients: (%d not defined because of singularities: %s)",
                length(ri$dropped_cols),
                paste(ri$dropped_cols, collapse = ", "))
    } else {
        "Coefficients:"
    }
    cat("\n", header, "\n", sep = "")
    if (is.list(x$coefficients) && !is.matrix(x$coefficients)) {
        ## multinomial / mgaussian: glmnet returns a list of coefficient
        ## matrices keyed by class / response. Print each block under its
        ## key so the layout stays interpretable.
        for (k in names(x$coefficients)) {
            cat("--- ", k, " ---\n", sep = "")
            print(x$coefficients[[k]])
        }
    } else {
        ## glm()-style single-column estimate table with NA at dropped
        ## positions. printCoefmat handles NA alignment cleanly and is
        ## the same formatter stats::summary.glm() uses.
        co_mat <- matrix(x$coefficients, ncol = 1L,
                         dimnames = list(names(x$coefficients), "Estimate"))
        stats::printCoefmat(co_mat, na.print = "NA", ...)
    }

    cat(sprintf("\nNon-zero predictors (%d):", length(x$nonzero)))
    if (length(x$nonzero)) {
        cat(" ", paste(x$nonzero, collapse = ", "), "\n", sep = "")
    } else {
        cat(" (none)\n")
    }

    ## Inference-policy footer. Spelled out at every summary() call so
    ## users do not silently mistake regularised point estimates for
    ## classical maximum-likelihood output. Matches the framing in
    ## vignette("fbrglm").
    cat("\nNote: no standard errors, z-values, or p-values are reported under\n")
    cat("infer = \"none\". Classical inference does not account for the\n")
    cat("shrinkage bias from L1/L2 penalisation or for the data-driven\n")
    cat("selection of lambda. Use infer = \"split\" / \"selective\" (planned)\n")
    cat("for valid post-selection inference; see vignette(\"fbrglm\").\n")
    invisible(x)
}

#' @export
predict.fbrglm <- function(object,
                           newdata = NULL,
                           type = c("link", "response", "class"),
                           newoffset = NULL,
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
        ## If the model was fit with rank-deficient drops, restrict
        ## newdata to the same kept columns the underlying glmnet fit
        ## actually saw. NA-valued coefficients live in `coefficients`,
        ## not in the underlying glmnet object.
        kept_cols <- object$rank_info$kept_cols
        if (!is.null(kept_cols) &&
            length(object$rank_info$dropped_cols)) {
            X <- X[, kept_cols, drop = FALSE]
        }
    }

    ## --- offset handling --------------------------------------------
    ## If the model was fit with an offset:
    ##   newdata = NULL  -> reuse the stored training offset (unless the
    ##                      caller passed their own newoffset)
    ##   newdata != NULL -> caller must supply newoffset
    fit_had_offset <- !is.null(object$offset)
    if (fit_had_offset) {
        if (is.null(newdata)) {
            if (is.null(newoffset)) {
                newoffset <- as.numeric(object$offset)
            }
        } else if (is.null(newoffset)) {
            stop("This model was fit with an offset; provide ",
                 "`newoffset` for prediction with newdata.",
                 call. = FALSE)
        }
    }
    if (!is.null(newoffset) && length(newoffset) != nrow(X)) {
        stop(sprintf(
            "`newoffset` length (%d) does not match the number of prediction rows (%d).",
            length(newoffset), nrow(X)
        ), call. = FALSE)
    }

    fit_for_predict <- if (!is.null(object$cv_fit)) {
        object$cv_fit
    } else {
        object$fit
    }
    s <- object$lambda_value

    pred_args <- list(object = fit_for_predict, newx = X, s = s)
    if (!is.null(newoffset)) {
        pred_args$newoffset <- as.numeric(newoffset)
    }

    fam_name <- .fbrglm_family_label(object)

    if (type == "class") {
        if (!fam_name %in% c("binomial", "multinomial")) {
            stop(sprintf(
                "type = 'class' is valid only for binomial / multinomial; got '%s'.",
                fam_name), call. = FALSE)
        }
        if (fam_name == "binomial") {
            pred_args$type <- "response"
            prob <- do.call(stats::predict, pred_args)
            return(as.numeric(as.vector(prob) >= 0.5))
        }
        pred_args$type <- "class"
        raw <- do.call(stats::predict, pred_args)
        return(as.vector(raw))
    }

    pred_args$type <- type
    pred <- do.call(stats::predict, pred_args)
    ## multinomial / mgaussian return a 3D array (n, k, n_lambda).
    ## Drop the trailing 1-d slice when we asked for a single lambda.
    if (length(dim(pred)) == 3L && dim(pred)[3L] == 1L) {
        ## Default drop = TRUE collapses (n, k, 1) -> (n, k) matrix,
        ## which is what callers expect for multinomial / mgaussian.
        pred <- pred[, , 1]
    }
    if (is.matrix(pred) && ncol(pred) == 1L) {
        return(as.vector(pred))
    }
    pred
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
