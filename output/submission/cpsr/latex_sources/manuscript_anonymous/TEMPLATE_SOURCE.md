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
- `cuted.sty` (runtime dependency required by `sn-jnl.cls`)
- `appendix.sty` (runtime dependency required by `sn-jnl.cls`)

`cuted.sty` was generated locally with `latex sttools.ins` from the CTAN
`sttools` source package retrieved on 2026-09-22 from
<https://mirrors.ctan.org/macros/latex/contrib/sttools.zip>. The downloaded ZIP
has SHA-256
`02569ee68ceec7548b7888add2da0dfa2574cb7097696eb3a2b458e08e999586`;
the generated `cuted.sty` has SHA-256
`afb346ec64f923bc7f8298c0d8bc9d0855705e7f970b1c693712a9b99108d205`.

`appendix.sty` was generated locally with `latex appendix.ins` from the CTAN
package retrieved on 2026-09-22 from
<https://mirrors.ctan.org/macros/latex/contrib/appendix.zip>. The downloaded ZIP
has SHA-256
`7383c9f35753d7e1f777a4f7626c89f6c7a6bf2095a4047de36f6af60ce7b63b`;
the generated `appendix.sty` has SHA-256
`f49c04b4146b0abbfea6865688574067f9f424b270859fa7e88c0410148dc95e`.

The generated manuscript uses
`\documentclass[referee,pdflatex,sn-basic]{sn-jnl}`. The `referee` option
supplies double-line spacing for peer review, `pdflatex` declares the build
engine expected by the official class, and `sn-basic` uses the Basic Springer
Nature author-year reference style required by the journal's name-year citation
instructions.

The Pandoc integration template also carries `submission/cpsr/template/common.latex`,
copied from Pandoc 3.7.0.2's default modular LaTeX template. Its `natbib` block
is removed because `sn-jnl.cls` already loads `natbib` and declares
`sn-basic`; retaining both declarations causes BibTeX to reject the duplicate
`\\bibstyle` entries.
