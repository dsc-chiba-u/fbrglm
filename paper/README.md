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

## Building

Rendered HTML / PDF outputs and the `*_files/` and `*_cache/` directories
that `knitr` produces are **not** tracked in git. Regenerate them from
the manuscript source:

```sh
R -q -e 'rmarkdown::render("paper/fbrglm-jss-draft.Rmd")'
```

This produces `paper/fbrglm-jss-draft.html` (gitignored). To switch to the actual
JSS LaTeX template later:

1. `install.packages("rticles")`
2. Change the YAML header to `output: rticles::jss_article` and adjust
   author metadata to JSS conventions.

## Benchmark inputs

The Benchmark section of the draft reads markdown tables and PNG
figures directly from the
[`fbrglm-experiments`](https://github.com/dsc-chiba-u/fbrglm-experiments)
repository checked out at `/home/koki/dev/fbrglm-experiments`. The
absolute path is set once via `exp_dir` at the top of the Rmd; the
figures are referenced with relative paths
(`../../fbrglm-experiments/results/figures/...`). A more portable build
would copy the relevant artefacts into `paper/` at render time.

## What still needs filling in

- Author affiliations and ORCIDs for JSS author block
- Submission date
- All `TODO:` markers in `fbrglm-jss-draft.Rmd` (e.g. cited
  practitioner papers, hardware/R-version footnote)
- Every package citation in `references.bib` whose `note` field begins
  with `TODO:` — run `citation("<pkg>")` in R and update with the
  authoritative metadata before submission. Do **not** fabricate
  citation fields.
