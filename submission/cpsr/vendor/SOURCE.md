# Springer Nature LaTeX template provenance

- Package: Springer Nature journal article LaTeX authoring template
- Template version: 3.1, December 2024
- Retrieved: 2026-09-22
- Official source: <https://www.springernature.com/gp/authors/campaigns/latex-author-support/see-where-our-services-will-take-you/18782940>
- Download URL used: <https://cms-resources.apps.public.k8s.springernature.io/springer-cms/rest/v1/content/18782940/data/v12>
- Downloaded ZIP SHA-256: `812e76dcaa9c28dc1bff1fb6065d51729b67d4ea140552a05088317414a3ecae`

The submission build vendors only the files needed for the CPSR package:

- `sn-jnl.cls`
- `sn-basic.bst`
- `sn-article-reference.tex` (unaltered reference copy of the official example)

The generated manuscript uses `\documentclass[referee,sn-basic]{sn-jnl}`. The
`referee` option supplies double-line spacing for peer review, while `sn-basic`
uses the Basic Springer Nature author-year reference style required by the
journal's name-year citation instructions.
