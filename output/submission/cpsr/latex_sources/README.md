# CPSR portable LaTeX sources

Each directory is an independently compilable Springer Nature `sn-jnl`
source tree. From within a directory, run:

```sh
latexmk -pdf -interaction=nonstopmode -halt-on-error <file>.tex
```

The bibliography, class, BibTeX style, runtime style files, and every figure
are bundled locally. All graphics paths are relative; no path points to the
author's computer. The source trees were compiled in isolated temporary
directories during packaging and their page counts were compared with the
corresponding repository renders. The manuscript and both supplementary
variants are anonymous.
