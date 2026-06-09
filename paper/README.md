# `paper/` — manuscript skeleton

Target venue: [Journal of Statistical Software](https://www.jstatsoft.org/)
(JSS).

## Files

```
paper/
  fbrglm-jss-draft.Rmd   # the draft, JSS section order
  references.bib         # bib entries derived from citation() in R
  README.md              # this file
```

## Build targets

Two pipelines render the same `fbrglm-jss-draft.Rmd`:

- **Development build** — `html_document` rendered to PDF via
  `weasyprint`. Fast, works without LaTeX, used for day-to-day
  drafting.
- **JSS submission build** — `rticles::jss_article` rendered via
  `pdflatex`. Targets the JSS class file and is the form to attach
  at submission time.

The source Rmd does not need to be edited to switch between them;
the JSS driver operates on a temporary copy and leaves the source
untouched.

## Building

Rendered HTML / PDF outputs and the `*_files/` / `*_cache/`
directories that `knitr` produces are **not** tracked in git.
Regenerate them from the manuscript source.

### Development (html_document + weasyprint)

```sh
Rscript scripts/render_paper_pdf.R
```

Writes `paper/fbrglm-jss-draft.html` and `paper/fbrglm-jss-draft.pdf`
next to the Rmd. Both are gitignored.

### JSS submission (rticles::jss_article + pdflatex)

```sh
Rscript scripts/render_jss_pdf.R
```

Writes `paper/fbrglm-jss-draft-jss.pdf` next to the Rmd, again
gitignored. The driver copies the JSS class file (`jss.cls`),
BibTeX style (`jss.bst`), and logo (`jsslogo.jpg`) from the
installed `rticles` template into `paper/` for the duration of the
render and removes them afterwards. It also applies a handful of
minimal LaTeX-compat substitutions on a temp copy of the Rmd
(structured `title` / `keywords` blocks, the `KNITR_ASIS_OUTPUT_TOKEN`
fix for kable tables, Greek-letter math-mode wrapping, and a
no-op fallback for `\pandocbounded`); the source Rmd is not modified.

Requirements: an installed LaTeX distribution. The R-ecosystem
default is `tinytex::install_tinytex()`, which the driver expects.
Any system TeX Live with `pdflatex` on `PATH` also works.

## Benchmark inputs

The Benchmark section of the draft reads markdown tables and PNG
figures directly from the
[`fbrglm-experiments`](https://github.com/dsc-chiba-u/fbrglm-experiments)
companion repository, which is expected to be checked out
separately. Its location is resolved at the top of the Rmd in this
order: (1) the `FBRGLM_EXP_ROOT` environment variable; (2) a sibling
directory `../fbrglm-experiments` next to the package checkout. If
neither resolves, the benchmark tables render an inline placeholder
note instead of failing the build. The runtime figure is referenced
via a sibling-relative path
(`../../fbrglm-experiments/results/figures/runtime_small.png`); for a
fully portable build, set `FBRGLM_EXP_ROOT` and copy the figure into
`paper/` at render time.

## JSS submission checklist

JSS (Journal of Statistical Software) is the **only** target for this
manuscript. Reference: <https://www.jstatsoft.org/>. The submission
package consists of:

1. **Manuscript source.** `fbrglm-jss-draft.Rmd` and `references.bib`.
   The Rmd's YAML metadata is already in JSS structure. Re-render with
   `output: rticles::jss_article` (after installing a LaTeX
   distribution, e.g. via `tinytex::install_tinytex()`) before
   submitting; the development build target is `html_document` purely
   because no LaTeX engine is configured locally.
2. **Package source.** `fbrglm` itself, from
   <https://github.com/dsc-chiba-u/fbrglm>. The current source passes
   `R CMD check --as-cran` modulo the two routine `New submission` /
   `unable to verify current time` NOTEs.
3. **Replication material.** The
   [`fbrglm-experiments`](https://github.com/dsc-chiba-u/fbrglm-experiments)
   companion repository provides the smoke tests, small benchmarks,
   manuscript tables, and figures referenced in the paper. Its README
   documents a single-command path from a fresh checkout to the
   manuscript tables and figures.
