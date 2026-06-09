# `paper/` — manuscript skeleton

Target venues, in priority order:

1. [Journal of Statistical Software](https://www.jstatsoft.org/) (JSS) —
   primary target. Standard format is the `rticles::jss_article`
   template; this skeleton renders to HTML for portability and will be
   swapped to that template once `rticles` is installed in the build
   environment.
2. [SoftwareX](https://www.sciencedirect.com/journal/softwarex) —
   fallback.

## Files

```
paper/
  fbrglm-jss-draft.Rmd   # the draft, JSS section order, html_document for now
  references.bib         # bib entries; placeholders marked TODO
  README.md              # this file
```

## Build target

This draft currently renders to `html_document` because the local
environment has no LaTeX engine. The YAML is already in JSS structure;
flip the `output:` block (see comments in `fbrglm-jss-draft.Rmd`) and
install `tinytex` to produce the JSS PDF form from the same source.

## Building

Rendered HTML / PDF outputs and the `*_files/` and `*_cache/` directories
that `knitr` produces are **not** tracked in git. Regenerate them from
the manuscript source.

HTML only:

```sh
R -q -e 'rmarkdown::render("paper/fbrglm-jss-draft.Rmd")'
```

HTML **plus** a PDF (via `weasyprint`):

```sh
Rscript scripts/render_paper_pdf.R
```

That helper writes `paper/fbrglm-jss-draft.html` and
`paper/fbrglm-jss-draft.pdf` next to the Rmd. Both are gitignored. To switch to the actual
JSS LaTeX template later:

1. `install.packages("rticles")`
2. Change the YAML header to `output: rticles::jss_article` and adjust
   author metadata to JSS conventions.

## Benchmark inputs

The Benchmark section of the draft reads markdown tables and PNG
figures directly from the
[`fbrglm-experiments`](https://github.com/dsc-chiba-u/fbrglm-experiments)
checked out separately. Its location is resolved at the top of the
Rmd in this order: (1) the `FBRGLM_EXP_ROOT` environment variable;
(2) a sibling directory `../fbrglm-experiments` next to the package
checkout. If neither resolves, the benchmark tables render an
inline placeholder note instead of failing the build. The runtime
figure is referenced via a sibling-relative path
(`../../fbrglm-experiments/results/figures/runtime_small.png`); for a
fully portable build, set `FBRGLM_EXP_ROOT` and copy the figure into
`paper/` at render time.

## JSS submission checklist

JSS (Journal of Statistical Software) is the **only** target for this
manuscript. Reference: <https://www.jstatsoft.org/>. The following
artefacts will need to be in place at submission time:

1. **Manuscript PDF and source**: the LaTeX class file `jss.cls` is
   provided by `rticles::jss_article`. The current draft renders to
   `html_document` because the local environment has no LaTeX engine;
   before submission, install a LaTeX distribution (e.g.
   `tinytex::install_tinytex()`), swap the YAML `output:` block in
   `fbrglm-jss-draft.Rmd` to `rticles::jss_article` (the YAML metadata
   is already laid out in JSS structure), and re-render. The source
   Rmd and the `.bib` will be included in the submission alongside the
   PDF.
2. **Package source**: `fbrglm` is the package described by the
   manuscript. Submission requires a clean `R CMD check --as-cran`,
   which the current source passes (only the two routine
   `New submission` / `unable to verify current time` NOTEs remain).
3. **Replication material**: the
   [`fbrglm-experiments`](https://github.com/dsc-chiba-u/fbrglm-experiments)
   companion repository provides the smoke tests, small benchmarks,
   manuscript tables, and figures referenced in the paper. JSS reviewers
   expect a single-command path from a fresh checkout to the
   manuscript tables / figures; that path is documented in the
   experiments README.

Rendered HTML / PDF outputs and the `*_files/` / `*_cache/`
directories that `knitr` produces are not committed in this repo.

## What still needs filling in

- Author affiliations, postal address, and ORCID for the JSS author
  block
- Submission date
- All `TODO:` markers in `fbrglm-jss-draft.Rmd` (e.g. cited
  practitioner papers, hardware / R-version footnote)
- `references.bib` entries still marked `TODO`:
  - `selectiveInference` Manual entry — install the package, then run
    `citation("selectiveInference")` and replace the placeholder
    fields.
  - `tibshirani2016selective` — verify volume, number, and pagination
    against the published JASA version.

  All other package citations (R, glmnet, glmnetUtils, parsnip,
  workflows, recipes, hardhat, broom) were generated from
  `citation()` in the local fbrglm-dev environment. Re-run
  `citation("<pkg>")` and update the version note when the manuscript
  is rebuilt against a newer package set. Do **not** fabricate
  citation fields.
