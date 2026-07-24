## scripts/render_paper_pdf.R
##
## Render paper/fbrglm-softwarex.Rmd to PDF via rticles::elsevier_article
## (tinytex / LaTeX). Output lands in paper/ and is gitignored.
##
## Usage:
##   Rscript scripts/render_paper_pdf.R

## --- locate the project root ----------------------------------------
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
rmd_path  <- file.path(paper_dir, "fbrglm-softwarex.Rmd")
pdf_path  <- file.path(paper_dir, "fbrglm-softwarex.pdf")

if (!file.exists(rmd_path)) {
    stop("Manuscript source not found: ", rmd_path, call. = FALSE)
}
if (!requireNamespace("rmarkdown", quietly = TRUE)) {
    stop("Package 'rmarkdown' is required.", call. = FALSE)
}
if (!requireNamespace("rticles", quietly = TRUE)) {
    stop("Package 'rticles' is required.", call. = FALSE)
}

message("[render_paper_pdf] rendering ", rmd_path)
rmarkdown::render(rmd_path,
                  output_format = "rticles::elsevier_article",
                  output_file   = basename(pdf_path),
                  output_dir    = paper_dir,
                  quiet         = FALSE)

if (!file.exists(pdf_path)) {
    stop("PDF output was not created at ", pdf_path, call. = FALSE)
}

info <- file.info(pdf_path)
message(sprintf(
    "[render_paper_pdf] PDF -> %s (%s bytes, mtime %s)",
    pdf_path,
    format(info$size, big.mark = ","),
    format(info$mtime, "%Y-%m-%d %H:%M:%S")
))
message("[render_paper_pdf] done")
