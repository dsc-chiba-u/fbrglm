# `paper/` — manuscript skeleton

Target venue: [SoftwareX](https://www.sciencedirect.com/journal/softwarex)
(Elsevier).

The manuscript was previously targeted at Journal of Statistical
Software; JSS returned an editorial rejection on 2026-07-14 as
out-of-scope (interface / workflow contributions are not published by
JSS). The JSS draft snapshot is preserved in git under tag
`jss-submission-v1`.

## Files

```
paper/
  fbrglm-softwarex.Rmd   # the draft, SoftwareX section order
  references.bib         # bib entries derived from citation() in R
  README.md              # this file
```

## Build

```sh
Rscript scripts/render_paper_pdf.R
```

Writes `paper/fbrglm-softwarex.pdf` (and `fbrglm-softwarex.tex`) next
to the Rmd. Both are gitignored.

Requirements: an installed LaTeX distribution. The R-ecosystem
default is `tinytex::install_tinytex()`, which the driver expects.
Any system TeX Live with `pdflatex` on `PATH` also works.

The template is `rticles::elsevier_article` with `journal: SoftwareX`
in the YAML front matter and a small preamble that defines
`\pkg{}` / `\proglang{}` / `\code{}` shims so bib entries carrying
the JSS-style markup still typeset cleanly under `elsarticle`.

## Section order (SoftwareX standard)

1. Motivation and significance
2. Software description (architecture + functionalities + metadata)
3. Illustrative example
4. Impact
5. Conclusions

The Software metadata table is placed at the end of section 2 per
SoftwareX submission conventions.

## Benchmark inputs

The manuscript is compact enough that the benchmark figures / tables
from the
[`fbrglm-experiments`](https://github.com/dsc-chiba-u/fbrglm-experiments)
companion repository are summarized in prose rather than embedded.
The reader is pointed to the Zenodo DOI of the companion repository
(also listed in the Software metadata table) for the full replication
material.

## SoftwareX submission checklist

The submission package consists of:

1. **Manuscript source.** `fbrglm-softwarex.Rmd` and `references.bib`.
   Re-render with `Rscript scripts/render_paper_pdf.R` before
   submitting.
2. **Package source.** `fbrglm` itself, from
   <https://github.com/dsc-chiba-u/fbrglm> (Zenodo:
   `10.5281/zenodo.21015223`).
3. **Replication material.** The
   [`fbrglm-experiments`](https://github.com/dsc-chiba-u/fbrglm-experiments)
   companion repository (Zenodo: `10.5281/zenodo.21016035`) provides
   the smoke tests, small benchmarks, manuscript tables, and figures
   referenced in the paper.
