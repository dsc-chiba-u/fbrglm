## scripts/render_figure1.R
##
## Render the birthwt diagnostic panel used as Figure 1 in
## paper/fbrglm-softwarex.Rmd to a standalone PNG at
## paper/Figure1.png, for upload as a separate figure file to the
## SoftwareX / Elsevier EM submission system.
##
## Usage:
##   Rscript scripts/render_figure1.R

project_root <- (function() {
    args <- commandArgs(trailingOnly = FALSE)
    file_arg <- grep("^--file=", args, value = TRUE)
    script_path <- if (length(file_arg)) {
        normalizePath(sub("^--file=", "", file_arg[1]), mustWork = FALSE)
    } else {
        tryCatch(normalizePath(sys.frames()[[1]]$ofile, mustWork = FALSE),
                 error = function(e) NA_character_)
    }
    root <- if (!is.na(script_path) && nzchar(script_path)) {
        dirname(dirname(script_path))
    } else {
        getwd()
    }
    normalizePath(root, mustWork = TRUE)
})()

paper_dir <- file.path(project_root, "paper")
png_path  <- file.path(paper_dir, "Figure1.png")

suppressPackageStartupMessages({
    library(fbrglm)
    library(MASS)
})

data("birthwt", package = "MASS")
birthwt$race      <- factor(birthwt$race,  1:3, c("white", "black", "other"))
birthwt$smoke     <- factor(birthwt$smoke, 0:1, c("no", "yes"))
birthwt$ftv       <- factor(birthwt$ftv)
birthwt$any_visit <- as.integer(birthwt$ftv != "0")

set.seed(93)
idx   <- sample.int(nrow(birthwt), 150)
train <- birthwt[idx, ]

suppressMessages({
    fit <- fbrglm(
        low ~ age + lwt + race + smoke + ptl + ftv + any_visit,
        data         = train,
        family       = "binomial",
        lambda       = "fix",
        lambda_value = 0.05
    )
})

grDevices::png(png_path,
               width  = 7.2, height = 1.7, units = "in",
               res    = 300, type = "cairo")
op <- graphics::par(mfrow = c(1, 3),
                    mar  = c(3.5, 3.5, 2, 0.5),
                    mgp  = c(2, 0.7, 0))
plot(fit)
graphics::par(op)
grDevices::dev.off()

info <- file.info(png_path)
message(sprintf(
    "[render_figure1] PNG -> %s (%s bytes, mtime %s)",
    png_path,
    format(info$size, big.mark = ","),
    format(info$mtime, "%Y-%m-%d %H:%M:%S")
))
