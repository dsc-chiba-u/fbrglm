## Internal residual helpers shared by plot.fbrglm() and glance.fbrglm().
## glmnet does not register a residuals() method, so deviance and Pearson
## residuals are computed by hand from y, the fitted mean mu, and (where
## applicable) the family's dev.resids function. The helpers return
## numeric vectors for single-response families and matrices for
## mgaussian; on the unsupported branches they return NULL so callers can
## fall back to NA or to a diagnostic message.

## Reconstruct the training response. fbrglm() stores the post-NA-drop
## response vector on the fit as `y_train`, so plot.fbrglm and
## glance.fbrglm can reach a clean residual without re-running
## model.frame().
.fbrglm_response <- function(object) object$y_train

## Response-scale fitted values at the chosen lambda.
.fbrglm_fitted_response <- function(object) {
    fam_name <- .fbrglm_family_label(object)
    if (fam_name == "cox") {
        ## predict("response") on a glmnet Cox returns the relative
        ## risk; we expose the *linear predictor* eta instead because
        ## the deviance-residual surrogate below needs eta.
        return(stats::predict(object, type = "link"))
    }
    stats::predict(object, type = "response")
}

## Deviance residuals at the chosen lambda. Returns NULL when the
## family does not have a per-observation deviance residual defined for
## the regularized setting; the caller is expected to handle NULL.
.fbrglm_deviance_residuals <- function(object) {
    fam      <- object$family
    fam_name <- .fbrglm_family_label(object)
    mu       <- .fbrglm_fitted_response(object)
    y        <- .fbrglm_response(object)
    w        <- if (is.null(object$weights)) rep(1, length(mu))
                else as.numeric(object$weights)

    ## --- the five exponential-family cases -------------------------
    ## stats::gaussian(), binomial(), poisson(), Gamma(),
    ## MASS::negative.binomial() all expose family$dev.resids(y, mu, w),
    ## so we can use the canonical signed sqrt-deviance formula.
    if (!is.null(y) && is.numeric(mu) &&
        fam_name %in% c("gaussian", "binomial", "poisson",
                        "Gamma", "negative.binomial", "negbin",
                        "Negative Binomial(2)")) {
        if (!inherits(fam, "family") && is.character(fam)) {
            fam <- switch(fam_name,
                          gaussian = stats::gaussian(),
                          binomial = stats::binomial(),
                          poisson  = stats::poisson(),
                          NULL)
        }
        if (is.null(fam)) return(NULL)
        dr <- fam$dev.resids(as.numeric(y), as.numeric(mu), w)
        return(sign(as.numeric(y) - as.numeric(mu)) * sqrt(dr))
    }

    ## --- multinomial: per-row negative log-likelihood --------------
    if (fam_name == "multinomial" && !is.null(y)) {
        prob <- as.matrix(mu)
        ## ensure column labels match y values
        if (is.factor(y)) y_idx <- as.integer(y)
        else              y_idx <- match(as.character(y), colnames(prob))
        if (anyNA(y_idx)) return(NULL)
        p_chosen <- prob[cbind(seq_along(y_idx), y_idx)]
        ## clip away log(0)
        p_chosen <- pmax(p_chosen, .Machine$double.eps)
        return(sqrt(-2 * log(p_chosen)))
    }

    ## --- mgaussian: per-row, per-response gaussian residuals -------
    if (fam_name == "mgaussian" && !is.null(y)) {
        if (!is.matrix(y)) y <- as.matrix(y)
        return(as.matrix(y) - as.matrix(mu))
    }

    ## --- Cox: surrogate coxph(y ~ offset(eta)) ---------------------
    if (fam_name == "cox" && !is.null(y) &&
        requireNamespace("survival", quietly = TRUE)) {
        eta <- as.numeric(mu)
        cph <- tryCatch(
            survival::coxph(y ~ offset(eta), init = 0, iter.max = 0,
                            ties = "breslow", x = FALSE, y = FALSE),
            error = function(e) NULL)
        if (is.null(cph)) return(NULL)
        return(as.numeric(stats::residuals(cph, type = "deviance")))
    }

    NULL
}

## Total deviance at the chosen lambda; used by glance.fbrglm.
.fbrglm_deviance <- function(object) {
    r <- .fbrglm_deviance_residuals(object)
    if (is.null(r))       return(NA_real_)
    if (is.matrix(r))     return(sum(r * r))
    sum(r * r)
}

## CV statistics at the chosen lambda; NA when no cv.glmnet was run.
.fbrglm_cv_stat <- function(object, stat = c("cvm", "cvsd")) {
    stat <- match.arg(stat)
    cv <- object$cv_fit
    if (is.null(cv)) return(NA_real_)
    idx <- which.min(abs(cv$lambda - object$lambda_value))
    if (!length(idx)) return(NA_real_)
    as.numeric(cv[[stat]][idx])
}
