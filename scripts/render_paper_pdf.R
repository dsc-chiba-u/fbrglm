## scripts/render_paper_pdf.R
##
## Render paper/fbrglm-jss-draft.Rmd to HTML, then convert that HTML to
## PDF via `weasyprint`. Both outputs land in paper/ and are gitignored.
##
## Usage:
##   Rscript scripts/render_paper_pdf.R

## --- locate the project root ----------------------------------------
## Works whether the script is sourced or executed from anywhere.
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
rmd_path  <- file.path(paper_dir, "fbrglm-jss-draft.Rmd")
html_path <- file.path(paper_dir, "fbrglm-jss-draft.html")
pdf_path  <- file.path(paper_dir, "fbrglm-jss-draft.pdf")

if (!file.exists(rmd_path)) {
    stop("Manuscript source not found: ", rmd_path, call. = FALSE)
}

## --- locate weasyprint ----------------------------------------------
find_weasyprint <- function() {
    candidates <- c(
        Sys.which("weasyprint"),
        path.expand("~/anaconda3/bin/weasyprint"),
        path.expand("~/anaconda3/envs/fbrglm-dev/bin/weasyprint")
    )
    candidates <- candidates[nzchar(candidates)]
    for (p in candidates) {
        if (file.exists(p) && file.access(p, mode = 1L) == 0L) {
            return(p)
        }
    }
    NA_character_
}

weasyprint_bin <- find_weasyprint()
if (is.na(weasyprint_bin)) {
    stop(
        "weasyprint not found. Looked in PATH and:\n",
        "  ~/anaconda3/bin/weasyprint\n",
        "  ~/anaconda3/envs/fbrglm-dev/bin/weasyprint\n",
        "Install it (e.g. `conda install -c conda-forge weasyprint`) ",
        "or update find_weasyprint() in this script.",
        call. = FALSE
    )
}

## --- render Rmd -> HTML ---------------------------------------------
if (!requireNamespace("rmarkdown", quietly = TRUE)) {
    stop("Package 'rmarkdown' is required.", call. = FALSE)
}
message("[render_paper_pdf] rendering ", rmd_path)
rmarkdown::render(rmd_path,
                  output_format = "html_document",
                  output_file   = basename(html_path),
                  output_dir    = paper_dir,
                  quiet         = TRUE)
if (!file.exists(html_path)) {
    stop("HTML output was not created at ", html_path, call. = FALSE)
}
message("[render_paper_pdf] HTML  -> ", html_path)

## --- weasyprint HTML -> PDF -----------------------------------------
message("[render_paper_pdf] weasyprint: ", weasyprint_bin)
status <- system2(weasyprint_bin,
                  args  = c(shQuote(html_path), shQuote(pdf_path)),
                  stdout = TRUE, stderr = TRUE)
attr_status <- attr(status, "status")
if (!file.exists(pdf_path) || (!is.null(attr_status) && attr_status != 0L)) {
    msg <- paste(status, collapse = "\n")
    stop("weasyprint failed:\n", msg, call. = FALSE)
}

info <- file.info(pdf_path)
message(sprintf(
    "[render_paper_pdf] PDF   -> %s (%s bytes, mtime %s)",
    pdf_path,
    format(info$size, big.mark = ","),
    format(info$mtime, "%Y-%m-%d %H:%M:%S")
))
message("[render_paper_pdf] done")
