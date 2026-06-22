## scripts/render_jss_pdf.R
##
## Render paper/fbrglm-jss-draft.Rmd via `rticles::jss_article` (LaTeX
## / PDF, the JSS submission format). The existing html_document
## pipeline (scripts/render_paper_pdf.R) is left untouched: this script
## works on a temporary copy of the Rmd that swaps the `output:` block
## and applies a handful of minimal LaTeX-compat fixes. The original
## Rmd is not modified.
##
## Usage: Rscript scripts/render_jss_pdf.R
##
## Requirements: rticles, tinytex (or another LaTeX engine on PATH).

project_root <- (function() {
    args <- commandArgs(trailingOnly = FALSE)
    a    <- grep("^--file=", args, value = TRUE)
    if (length(a)) return(dirname(dirname(normalizePath(sub("^--file=", "", a[1]),
                                                       mustWork = FALSE))))
    normalizePath(getwd())
})()

paper_dir <- file.path(project_root, "paper")
src_rmd   <- file.path(paper_dir, "fbrglm-jss-draft.Rmd")
tmp_rmd   <- file.path(paper_dir, ".fbrglm-jss-draft-jss.tmp.Rmd")
out_pdf   <- file.path(paper_dir, "fbrglm-jss-draft-jss.pdf")

if (!file.exists(src_rmd)) {
    stop("Source Rmd not found: ", src_rmd, call. = FALSE)
}
if (!requireNamespace("rticles", quietly = TRUE)) {
    stop("Package `rticles` is required for JSS output. ",
         "Install with install.packages('rticles').", call. = FALSE)
}
if (requireNamespace("tinytex", quietly = TRUE) &&
    !tinytex::is_tinytex() &&
    !nzchar(Sys.which("pdflatex"))) {
    stop("No LaTeX engine found. ",
         "Run tinytex::install_tinytex() or install a TeX distribution.",
         call. = FALSE)
}

message("[jss] reading ", src_rmd)
src <- paste(readLines(src_rmd, warn = FALSE), collapse = "\n")

## --- 1. Replace the active `output:` block with rticles::jss_article.
##        Matches the multi-line html_document block we ship in the Rmd
##        and substitutes the JSS single-line form. The match is
##        intentionally narrow so unrelated YAML keys are not touched.
out_block <- paste(
    "output:",
    "  html_document:",
    "    toc: false",
    "    number_sections: true",
    "    self_contained: true",
    sep = "\n"
)
if (!grepl(out_block, src, fixed = TRUE)) {
    warning("Could not locate the html_document output block in the source; ",
            "the temp Rmd may still try to render to html.", call. = FALSE)
}
src <- sub(out_block, "output: rticles::jss_article", src, fixed = TRUE)

## --- 2. Strip the raw HTML <style>...</style> block: it is for
##        WeasyPrint pagination and breaks LaTeX rendering.
src <- gsub("(?s)<style>.*?</style>", "", src, perl = TRUE)

## --- 3. kable tables are emitted with format = "html" for the
##        WeasyPrint path. Swap to "latex" so pandoc gets actual
##        LaTeX tabular code rather than raw HTML it has to drop.
src <- gsub('format\\s*=\\s*"html"', 'format = "latex"', src)

## --- 3.5 Substitute the handful of non-ASCII glyphs in the source
##        with their LaTeX math-mode / dash equivalents. pdflatex
##        without a Unicode-aware engine fails on raw lambda / theta /
##        Delta / multiplication-sign characters; replacing them at
##        source time avoids hauling in XeLaTeX or extra LaTeX
##        packages just to make these glyphs render.
##        Each replacement uses the 4-backslash form so the resulting
##        string literally contains a single backslash before the
##        LaTeX macro name.
## With fixed = TRUE, gsub keeps `\\` in the replacement literally; we
## need exactly one backslash in the substituted text, so the R source
## literal here contains two characters (`\` once).
## --- Section headings come first: replace headings that contain λ
##     with an ASCII spelling before the body-level Greek-letter
##     substitution runs. Otherwise pandoc wraps section titles in
##     \texorpdfstring{...}{...} a second time, the bookmark text
##     becomes empty, and hyperref later tripped on `\lambda` inside
##     the .aux file.
src <- sub("## λ selection as part of the model object",
           "## Lambda selection as part of the model object",
           src, fixed = TRUE)
src <- sub("## λ-selection rules",
           "## Lambda-selection rules",
           src, fixed = TRUE)
src <- sub("## Negative binomial regression (fixed θ)",
           "## Negative binomial regression (fixed theta)",
           src, fixed = TRUE)

## Two `×` glyphs appear inside R string literals that drive
## `knitr::kable(col.names = c(...))` — the runtime-table column
## headers `"fbrglm (× over raw)"` etc. The general substitution
## below would inject `\texorpdfstring{$\times$}{x}` into those
## R string literals, where `\t` and `\$` then get re-interpreted
## by the R parser (the `\t` becomes a literal tab character) and
## the resulting kable cell is unreadable. Replace the column-header
## phrase with a plain-ASCII equivalent BEFORE the global pass so
## the runtime-table headers render cleanly.
src <- gsub("(× over raw)", "(ratio)", src, fixed = TRUE)

## Greek-letter substitutes are wrapped in `\texorpdfstring{...}{...}`
## so they survive moving arguments such as section headings and PDF
## bookmarks; the plain ASCII spelling is used for bookmark text and
## the math version for the rendered heading.
src <- gsub("—", "---", src, fixed = TRUE)  # em dash
src <- gsub("×", "\\texorpdfstring{$\\times$}{x}",      src, fixed = TRUE)
src <- gsub("λ", "\\texorpdfstring{$\\lambda$}{lambda}", src, fixed = TRUE)
src <- gsub("θ", "\\texorpdfstring{$\\theta$}{theta}",   src, fixed = TRUE)
src <- gsub("Δ", "\\texorpdfstring{$\\Delta$}{Delta}",   src, fixed = TRUE)

## --- 3.7 Make every `{r ..., echo = FALSE}` table chunk emit its
##        kable output as raw LaTeX rather than letting knitr wrap it
##        in a CodeChunk environment (which leaks knitr's
##        KNITR_ASIS_OUTPUT_TOKEN HTML comment into the .tex). Every
##        chunk in this Rmd that uses `echo = FALSE` is a kable
##        chunk, so the blanket substitution is safe.
src <- gsub(", echo = FALSE\\}", ", echo = FALSE, results = 'asis'}",
            src, perl = TRUE)

## --- 3.75 Several of the manuscript tables have enough columns to
##         overflow the JSS page width when rendered as a plain LaTeX
##         tabular. Inject a tiny `.jss_kable` wrapper that, for the
##         LaTeX path, wraps the rendered tabular in `\resizebox{...}{!}`
##         so the table is scaled down to the text width. This is done
##         without going through kableExtra so the JSS template's
##         `tabu.sty` (which requires xcolor with the `[table]` option
##         to define `\CT@setup`) does not have to be touched.
##         For non-LaTeX builds the wrapper is a no-op. The wrapper is
##         appended to the existing setup chunk; then every
##         `knitr::kable(` call in the body is rewritten to
##         `.jss_kable(`. Rewrite first, inject second — if the helper
##         is injected first, the global rewrite would replace the
##         `knitr::kable(...)` inside it as well, producing an infinitely
##         recursive `.jss_kable` -> `.jss_kable` chain that overflows
##         the evaluation stack at render time.
src <- gsub("knitr::kable(", ".jss_kable(", src, fixed = TRUE)
kable_helper <- paste(
    "",
    ".jss_kable <- function(...) {",
    "    k <- knitr::kable(...)",
    "    if (!identical(attr(k, \"format\"), \"latex\")) return(k)",
    "    raw <- paste(as.character(k), collapse = \"\\n\")",
    "    pat <- \"(?s)(\\\\\\\\begin\\\\{tabular\\\\}.*?\\\\\\\\end\\\\{tabular\\\\})\"",
    "    m <- regmatches(raw, regexpr(pat, raw, perl = TRUE))",
    "    if (!length(m)) return(k)",
    "    box_open <- paste0(",
    "        \"\\\\resizebox{\\\\ifdim\\\\width>\\\\linewidth\",",
    "        \"\\\\linewidth\\\\else\\\\width\\\\fi}{!}{%\\n\"",
    "    )",
    "    box_close <- \"}\"",
    "    wrapped <- paste0(",
    "        substr(raw, 1, regexpr(pat, raw, perl = TRUE) - 1L),",
    "        box_open, m, \"\\n\", box_close,",
    "        substr(raw, regexpr(pat, raw, perl = TRUE) +",
    "               attr(regexpr(pat, raw, perl = TRUE), \"match.length\"),",
    "               nchar(raw))",
    "    )",
    "    structure(wrapped,",
    "              format = \"latex\",",
    "              class  = c(\"knitr_kable\", \"character\"))",
    "}",
    sep = "\n"
)
setup_open <- "```{r setup, include = FALSE}\n"
if (grepl(setup_open, src, fixed = TRUE)) {
    src <- sub(setup_open,
               paste0(setup_open, kable_helper, "\n"),
               src, fixed = TRUE)
} else {
    warning("Could not locate the setup chunk to inject the JSS kable helper.",
            call. = FALSE)
}

## --- 3.8 Two section headings contain backtick code spans whose
##        underscored tokens (`nobs_info`, `rank_info`, `as_glmnet()`,
##        `as_cv_glmnet()`) push pandoc into a \texorpdfstring{...}{...}
##        section title. The bookmark-text argument then trips
##        hyperref's underscore handling and the build fails. Plain
##        prose section titles avoid this without changing the
##        substantive content; the field names are referenced in the
##        body text immediately below each heading.
src <- sub("## `nobs_info` and `rank_info`",
           "## Reporting fields: nobs and rank bookkeeping",
           src, fixed = TRUE)
src <- sub("## `as_glmnet()` / `as_cv_glmnet()`",
           "## Accessor functions for the underlying glmnet fit",
           src, fixed = TRUE)
## Appendix A.3 heading carries `on_new_levels`, whose underscore
## blows up hyperref's bookmark file once pandoc embeds the section
## title into the .out file. Plain prose avoids the trip.
src <- sub("## A.3. predict(fit) and on_new_levels",
           "## A.3. Prediction and novel-level handling",
           src, fixed = TRUE)

## --- 3.6 The JSS class template reads `$title.formatted$` from the
##        YAML, not the simple `$title$` we use for the html_document
##        build. Replace the single-string title with the structured
##        form expected by rticles::jss_article so `\title{}` is not
##        emitted empty.
old_title <- 'title: "Safe Formula-Based Workflows for Regularized Generalized Linear Models in R"'
new_title <- paste(
    "title:",
    "  formatted: \"Safe Formula-Based Workflows for Regularized Generalized Linear Models in R\"",
    "  plain:     \"Safe Formula-Based Workflows for Regularized GLMs in R\"",
    "  short:     \"Safe Formula-Based Regularized GLMs\"",
    sep = "\n"
)
src <- sub(old_title, new_title, src, fixed = TRUE)

## --- 3.62 Same story for keywords: the JSS template reads
##          `$keywords.formatted$` / `$keywords.plain$`, but the
##          html_document YAML uses a flat list. Translate to the
##          structured form so the JSS keyword block is populated.
old_keywords <- paste(
    "keywords:",
    "  - \"regularized generalized linear models\"",
    "  - \"glmnet\"",
    "  - \"formula interface\"",
    "  - \"R\"",
    "  - \"prediction\"",
    sep = "\n"
)
new_keywords <- paste(
    "keywords:",
    "  formatted: [regularized generalized linear models, glmnet, formula interface, R, prediction]",
    "  plain:     [regularized generalized linear models, glmnet, formula interface, R, prediction]",
    sep = "\n"
)
src <- sub(old_keywords, new_keywords, src, fixed = TRUE)

## --- 3.65 Pandoc >= 3.1 emits `\pandocbounded{\includegraphics{...}}`
##         for figure inclusion but only defines the macro in some
##         output templates. The JSS class does not. Provide a no-op
##         fallback in the preamble so figures compile.
##         The rticles JSS template already auto-loads booktabs /
##         longtable / array / multirow / colortbl / xcolor before
##         `\begin{document}`, so kableExtra::kable_styling() does not
##         need any further preamble injection — the only addition
##         here is the pandocbounded shim.
src <- sub("  \\usepackage{amsmath}",
           "  \\usepackage{amsmath}\n  \\providecommand{\\pandocbounded}[1]{#1}",
           src, fixed = TRUE)

writeLines(src, tmp_rmd)
message("[jss] wrote temp Rmd to ", tmp_rmd)

## --- 1.5 Copy JSS class file, BibTeX style, and logo from the
##         rticles template into paper/ so LaTeX can find them at
##         compile time. rmarkdown::draft() would normally do this on
##         a fresh skeleton; we are bypassing draft() to keep one Rmd
##         source-of-truth, so we copy the assets explicitly.
jss_skel <- system.file("rmarkdown", "templates", "jss", "skeleton",
                        package = "rticles")
jss_assets <- c("jss.cls", "jss.bst", "jsslogo.jpg")
copied_assets <- character()
for (a in jss_assets) {
    s <- file.path(jss_skel, a)
    d <- file.path(paper_dir, a)
    if (file.exists(s) && !file.exists(d)) {
        file.copy(s, d, overwrite = FALSE)
        copied_assets <- c(copied_assets, d)
    }
}
if (length(copied_assets)) {
    message("[jss] copied JSS assets to paper/: ",
            paste(basename(copied_assets), collapse = ", "))
}

## --- 4. Render via rticles::jss_article.
message("[jss] rmarkdown::render() -> ", basename(out_pdf))
rendered <- rmarkdown::render(
    tmp_rmd,
    output_format = rticles::jss_article(),
    output_file   = basename(out_pdf),
    output_dir    = paper_dir,
    quiet         = TRUE,
    clean         = TRUE
)

if (!file.exists(out_pdf)) {
    stop("rticles::jss_article render reported success but ",
         out_pdf, " is missing.", call. = FALSE)
}
info <- file.info(out_pdf)
message(sprintf(
    "[jss] PDF -> %s (%s bytes, mtime %s)",
    out_pdf,
    format(info$size, big.mark = ","),
    format(info$mtime, "%Y-%m-%d %H:%M:%S")
))

## --- 5. Cleanup. unlink temp Rmd and any same-stem intermediate
##        artifacts pandoc/knitr may have left behind (.tex, .log, ...).
stem <- file.path(paper_dir, tools::file_path_sans_ext(basename(tmp_rmd)))
for (ext in c("", ".tex", ".log", ".knit.md", ".utf8.md")) {
    unlink(paste0(stem, ext))
}
unlink(tmp_rmd)
## Remove JSS assets we copied in step 1.5 (do not delete a checked-in copy).
for (p in copied_assets) unlink(p)

message("[jss] done")
