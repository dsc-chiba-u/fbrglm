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

## Build target

The active build target is `html_document` because a LaTeX engine
(`tinytex` / TeX Live) is not installed in the local environment. The
YAML metadata is already in JSS structure; flipping the `output:`
block to `rticles::jss_article` and installing a LaTeX distribution
produces the JSS PDF form from the same source.

## Building

Rendered HTML / PDF outputs and the `*_files/` / `*_cache/`
directories that `knitr` produces are **not** tracked in git.
Regenerate them from the manuscript source.

HTML only:

```sh
R -q -e 'rmarkdown::render("paper/fbrglm-jss-draft.Rmd")'
```

HTML **plus** a PDF (via `weasyprint`):

```sh
Rscript scripts/render_paper_pdf.R
```

That helper writes `paper/fbrglm-jss-draft.html` and
`paper/fbrglm-jss-draft.pdf` next to the Rmd. Both are gitignored.

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
