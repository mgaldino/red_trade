#!/usr/bin/env python3
"""Generate deterministic CPSR submission sources from paper_v4.Rmd.

This script does not run the targets pipeline or re-estimate any model. It reads the
active manuscript, makes journal-format derivatives, and writes build sources under
output/submission/cpsr/build. The canonical manuscript remains paper_v4.Rmd.
"""

from __future__ import annotations

import argparse
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = ROOT / "submission" / "cpsr" / "cpsr_submission_config.json"
DEFAULT_SOURCE = ROOT / "paper_v4.Rmd"
DEFAULT_BUILD = ROOT / "output" / "submission" / "cpsr" / "build"
DEFAULT_BIBLIOGRAPHY = ROOT / "synth-trade-china.bib"


def read_json(path: Path) -> dict:
    with path.open("r", encoding="utf-8") as handle:
        return json.load(handle)


def split_rmd(source: str) -> tuple[str, str]:
    lines = source.splitlines(keepends=True)
    if not lines or lines[0].strip() != "---":
        raise ValueError("paper_v4.Rmd must begin with a YAML delimiter")
    for index in range(1, len(lines)):
        if lines[index].strip() == "---":
            return "".join(lines[: index + 1]), "".join(lines[index + 1 :])
    raise ValueError("Could not find the closing YAML delimiter in paper_v4.Rmd")


def yaml_quote(value: str) -> str:
    return json.dumps(value, ensure_ascii=False)


def build_yaml(config: dict, variant: str) -> str:
    if variant not in {"main", "inline", "supplement"}:
        raise ValueError(f"Unknown variant: {variant}")

    abstract_lines: list[str] = []
    abstract_labels = ("Purpose", "Methods", "Results", "Conclusion")
    for index, label in enumerate(abstract_labels):
        # A Markdown hard line break preserves the required structured labels
        # without creating four widely spaced abstract paragraphs.
        line_break = "  " if index < len(abstract_labels) - 1 else ""
        abstract_lines.append(
            f"  **{label}:** {config['abstract'][label]}{line_break}"
        )

    keywords = "\n".join(f"  - {yaml_quote(item)}" for item in config["keywords"])
    # Pandoc resolves custom templates from the generated Rmd directory rather
    # than from knit_root_dir. The default build directory is four levels below
    # the repository root.
    template = "../../../../submission/cpsr/template/cpsr-sn-pandoc.tex"

    return "\n".join(
        [
            "---",
            f"title: {yaml_quote(config['title'])}",
            f"short-title: {yaml_quote(config['short_title'])}",
            "anonymous: true",
            "output:",
            "  bookdown::pdf_document2:",
            "    number_sections: true",
            "    toc: false",
            "    latex_engine: pdflatex",
            "    keep_tex: true",
            "    citation_package: natbib",
            f"    template: {yaml_quote(template)}",
            "    pandoc_args:",
            "      - --top-level-division=section",
            "abstract: |",
            *abstract_lines,
            "keywords:",
            keywords,
            'bibliography: "cpsr_references.bib"',
            'biblio-style: "sn-basic"',
            "link-citations: true",
            # Preserve Springer's indented paragraph style. Without this flag,
            # Pandoc loads parskip.sty, whose stretchable glue can become very
            # large when combined with the class's flush-bottom pagination.
            "indent: true",
            "header-includes:",
            # Use Springer's normal-body theorem style. Pandoc/bookdown emits
            # these theorem environments as direct macros rather than
            # \begin/\end groups, so an italic-body style would leak into the
            # prose following the first lemma.
            "  - \\theoremstyle{thmstylethree}",
            "  - \\newtheorem{modelproposition}{Proposition}",
            "  - \\newtheorem{modelcorollary}{Corollary}",
            "  - \\newtheorem{modellemma}{Lemma}",
            "  - \\let\\proposition\\modelproposition",
            "  - \\let\\endproposition\\endmodelproposition",
            "  - \\let\\corollary\\modelcorollary",
            "  - \\let\\endcorollary\\endmodelcorollary",
            "  - \\let\\lemma\\modellemma",
            "  - \\let\\endlemma\\endmodellemma",
            "  - \\newcommand{\\pospart}[1]{\\left[#1\\right]_{+}}",
            "---",
            "",
        ]
    )


def declarations_text(config: dict) -> str:
    return "\n".join(
        [
            "# Statements and Declarations {-}",
            "",
            "## Funding {-}",
            "",
            "Funding information is provided on the separate title page to preserve double anonymity.",
            "",
            "## Competing Interests {-}",
            "",
            config["competing_interests"],
            "",
            "## Ethics Approval {-}",
            "",
            config["ethics"],
            "",
            "## Data, Materials, and Code Availability {-}",
            "",
            config["data_code_availability"],
            "",
            "## Author Contribution {-}",
            "",
            "The sole author was responsible for all aspects of the work. Full contribution information is provided on the separate title page.",
        ]
    )


def normalize_body(body: str, config: dict) -> str:
    body = re.sub(r"(?m)^Word count:.*\n", "", body, count=1)
    diagnostic_table_chunk = "```{r brazil-sdid-diagnostic-summary"
    if body.count(diagnostic_table_chunk) != 1:
        raise ValueError("Expected the compact Brazil SDiD diagnostic table chunk once")
    diagnostic_table_anchor = "\\clearpage\n\n" + diagnostic_table_chunk
    if diagnostic_table_anchor not in body:
        body = body.replace(
            "\\FloatBarrier\n\\newpage\n\n" + diagnostic_table_chunk,
            diagnostic_table_chunk,
            1,
        )
        body = body.replace(
            diagnostic_table_chunk,
            diagnostic_table_anchor,
            1,
        )
    body = re.sub(
        r"(?m)^####\s+(.+?)\s*$",
        lambda match: f"\\medskip\n\n\\noindent\\textbf{{{match.group(1)}.}}",
        body,
    )

    refs = "# References {-}\n\n::: {#refs}\n:::"
    if refs not in body:
        raise ValueError("Expected references placeholder was not found")
    body = body.replace(refs, "\\bibliography{cpsr_references}", 1)

    declaration_anchor = "\\clearpage\n\n\\bibliography{cpsr_references}"
    if declaration_anchor not in body:
        raise ValueError("Could not place Statements and Declarations before references")
    body = body.replace(
        declaration_anchor,
        declarations_text(config)
        + "\n\n\\clearpage\n\n\\bibliography{cpsr_references}",
        1,
    )
    return body


def deduplicate_bibliography(source: str) -> tuple[str, list[str]]:
    """Keep the first complete BibTeX entry for each case-insensitive key."""
    lines = source.splitlines(keepends=True)
    output: list[str] = []
    duplicate_keys: list[str] = []
    seen: set[str] = set()
    index = 0

    while index < len(lines):
        match = re.match(r"^\s*@[A-Za-z]+\s*\{\s*([^,\s]+)\s*,", lines[index])
        if not match:
            output.append(lines[index])
            index += 1
            continue

        entry: list[str] = []
        balance = 0
        while index < len(lines):
            line = lines[index]
            entry.append(line)
            balance += line.count("{") - line.count("}")
            index += 1
            if balance == 0:
                break
        if balance != 0:
            raise ValueError(f"Unbalanced BibTeX entry: {match.group(1)}")

        key = match.group(1)
        normalized_key = key.casefold()
        if normalized_key in seen:
            duplicate_keys.append(key)
            while index < len(lines) and not lines[index].strip():
                index += 1
            continue
        seen.add(normalized_key)
        output.extend(entry)

    return "".join(output).rstrip() + "\n", duplicate_keys


def replace_appendix_crossrefs_for_standalone_main(text: str) -> str:
    replacements: list[tuple[str, str]] = [
        (
            r"Appendix Figure \\@ref\(fig:appendix-brazil-china-ideal-points\)",
            "Online Resource 1",
        ),
        (
            r"Appendix Tables \\@ref\(tab:sdid-unit-weights-complete\), "
            r"\\@ref\(tab:sdid-time-weights\), \\@ref\(tab:sdid-donor-sensitivity\), "
            r"and \\@ref\(tab:sdid-window-sensitivity\)",
            "Online Resource 1",
        ),
        (
            r"Appendix Figure \\@ref\(fig:plot-ddd-pretrends\)",
            "Online Resource 1",
        ),
        (
            r"Figure \\@ref\(fig:public-cue-pre-treatment-distance\) in the Appendix",
            "Online Resource 1",
        ),
        (
            r"Appendix Table \\@ref\(tab:public-cue-sdid-results\)",
            "Online Resource 1",
        ),
        (
            r"Appendix Table \\@ref\(tab:public-cue-pooled-ife\)",
            "Online Resource 1",
        ),
        (
            r"Appendix Tables \\@ref\(tab:cross-country-duration-table\) and "
            r"\\@ref\(tab:cross-country-audit-table\)",
            "Online Resource 1",
        ),
        (
            r"Figure \\@ref\(fig:plot-latam\)",
            "Online Resource 1",
        ),
    ]

    for pattern, replacement in replacements:
        text, count = re.subn(pattern, replacement, text, count=1)
        if count != 1:
            raise ValueError(f"Expected exactly one main-text cross-reference match: {pattern}")

    remaining = re.findall(r"Appendix[^\n.]*\\@ref\([^\)]+\)", text)
    if remaining:
        raise ValueError(
            "Unconverted appendix cross-references remain in standalone main text: "
            + " | ".join(remaining)
        )
    return text


def force_appendix_section_page_breaks(appendix: str) -> str:
    return re.sub(
        r"(?m)^##\s+(.+?)\s*$",
        lambda match: "\\clearpage\n\n## " + match.group(1) + " {-}",
        appendix,
    )


def tex_escape(value: str) -> str:
    accent_map = {
        "á": r"\'{a}",
        "Á": r"\'{A}",
        "ã": r"\~{a}",
        "Ã": r"\~{A}",
        "â": r"\^{a}",
        "é": r"\'{e}",
        "É": r"\'{E}",
        "í": r"\'{i}",
        "ó": r"\'{o}",
        "õ": r"\~{o}",
        "ú": r"\'{u}",
        "ç": r"\c{c}",
        "Ç": r"\c{C}",
        "–": "--",
        "—": "---",
        "’": "'",
        "“": "``",
        "”": "''",
    }
    special = {
        "&": r"\&",
        "%": r"\%",
        "$": r"\$",
        "#": r"\#",
        "_": r"\_",
        "{": r"\{",
        "}": r"\}",
        "~": r"\textasciitilde{}",
        "^": r"\textasciicircum{}",
    }
    output: list[str] = []
    for char in value:
        if char in accent_map:
            output.append(accent_map[char])
        elif char in special:
            output.append(special[char])
        else:
            output.append(char)
    return "".join(output)


def simple_tex_preamble(title: str = "") -> str:
    pdf_title = tex_escape(title)
    return "\n".join(
        [
            r"\documentclass[11pt]{article}",
            r"\usepackage[T1]{fontenc}",
            r"\usepackage[utf8]{inputenc}",
            r"\usepackage[margin=1in]{geometry}",
            r"\usepackage{parskip}",
            r"\usepackage[hidelinks]{hyperref}",
            rf"\hypersetup{{pdftitle={{{pdf_title}}}}}",
            r"\setlength{\parindent}{0pt}",
            r"\begin{document}",
        ]
    )


def title_page_tex(config: dict) -> str:
    author = config["author"]
    lines = [
        simple_tex_preamble("CPSR Title Page"),
        r"\thispagestyle{empty}",
        r"\begin{center}",
        rf"{{\Large\bfseries {tex_escape(config['title'])}\par}}",
        r"\vspace{1.5cm}",
        rf"{{\large {tex_escape(author['given'] + ' ' + author['family'])}\par}}",
        rf"{tex_escape(author['department'])}\par",
        rf"{tex_escape(author['institution'])}\par",
        rf"{tex_escape(author['city'] + ', ' + author['state'] + ', ' + author['country'])}\par",
        rf"Corresponding author: \href{{mailto:{author['email']}}}{{{tex_escape(author['email'])}}}\par",
        rf"ORCID: \href{{https://orcid.org/{author['orcid']}}}{{{tex_escape(author['orcid'])}}}\par",
        r"\end{center}",
        r"\section*{Acknowledgments}",
        tex_escape(config["acknowledgments"]),
        r"\section*{Statements and Declarations}",
        r"\textbf{Funding.} " + tex_escape(config["funding"]),
        r"\textbf{Competing interests.} " + tex_escape(config["competing_interests"]),
        r"\textbf{Ethics approval.} " + tex_escape(config["ethics"]),
        r"\textbf{Data, materials, and code availability.} "
        + tex_escape(config["data_code_availability"]),
        r"\textbf{Author contribution.} " + tex_escape(config["author_contributions"]),
        r"\end{document}",
        "",
    ]
    return "\n\n".join(lines)


def cover_letter_tex(config: dict) -> str:
    author = config["author"]
    title = tex_escape(config["title"])
    lines = [
        simple_tex_preamble("Cover Letter to Chinese Political Science Review"),
        r"\thispagestyle{empty}",
        tex_escape(config["submission_date_long"]),
        r"\vspace{0.6cm}",
        tex_escape(config["editor_in_chief"]) + r"\\Editor-in-Chief\\" + tex_escape(config["journal"]),
        r"\vspace{0.6cm}",
        "Dear Professor Guo,",
        (
            "I am pleased to submit ``"
            + title
            + "'' for consideration as an "
            + tex_escape(config["article_type"])
            + r" in \emph{"
            + tex_escape(config["journal"])
            + "}."
        ),
        (
            "The manuscript explains when a continuous change in trade exposure becomes a "
            "politically usable status cue. It develops a formal mechanism linking public "
            "recognition of trade rank to political attention and then evaluates the argument "
            "with synthetic difference-in-differences evidence from Brazil, resolution-level "
            "United Nations voting, media and official-discourse evidence, and a cross-country "
            "interactive fixed-effects analysis."
        ),
        (
            "The paper is a strong fit for the journal's generalist mission because it connects "
            "international political economy, status, foreign-policy decision making, and causal "
            "inference. China is the central empirical case, but the contribution speaks to a "
            "broader political-science question: how publicly legible rank changes alter the "
            "recognition practices and diplomatic choices of third countries."
        ),
        (
            "An earlier version was posted as a preprint on "
            + tex_escape(config["preprint"]["repository"])
            + " ("
            + r"\url{" + config["preprint"]["doi"] + "}"
            + "). Springer Nature's preprint policy states that posting a preprint does not "
            "constitute prior publication. The submitted manuscript has been substantially "
            "revised in theory, design, diagnostics, and scope."
        ),
        (
            "The manuscript is not under consideration elsewhere. I am the sole author and "
            "approve this submission. The files include a double-anonymized manuscript, a "
            "separate title page, and supporting information prepared in both full and condensed "
            "forms. An anonymized replication archive can be supplied during peer review."
        ),
        "Thank you for considering the manuscript.",
        "Sincerely,",
        tex_escape(author["given"] + " " + author["family"]) + r"\\" + tex_escape(author["institution"]) + r"\\" + tex_escape(author["email"]),
        r"\end{document}",
        "",
    ]
    return "\n\n".join(lines)


def appendix_cover_tex(config: dict, kind: str, public: bool = False) -> str:
    author = config["author"]
    if kind == "full":
        heading = "Supporting Appendix: Full Version"
        explanation = (
            "This file contains the complete supporting appendix. It is the version to use "
            "when the journal does not impose an appendix-length constraint."
        )
        included = config["appendix_sections"]
        omitted: list[str] = []
    elif kind == "short":
        heading = "Supporting Appendix: Condensed Version"
        explanation = (
            "This file contains the condensed supporting appendix. The complete diagnostics, "
            "tables, prompt documentation, and robustness analyses are available in "
            + config["anonymous_online_resource_label"]
            + "."
        )
        included = config["short_appendix_sections"]
        omitted = [
            item for item in config["appendix_sections"] if item not in set(included)
        ]
    elif kind == "online":
        heading = "Online Resource 1: Full Supplementary Information"
        explanation = (
            "This file contains the complete supplementary information and is numbered "
            "independently from the manuscript."
        )
        included = config["appendix_sections"]
        omitted = []
    else:
        raise ValueError(f"Unknown appendix cover kind: {kind}")

    lines = [
        simple_tex_preamble(heading),
        r"\thispagestyle{empty}",
        r"\begin{center}",
        rf"{{\Large\bfseries {tex_escape(heading)}\par}}",
        r"\vspace{0.5cm}",
        rf"{{\large {tex_escape(config['title'])}\par}}",
        r"\vspace{0.3cm}",
        rf"\emph{{Prepared for {tex_escape(config['journal'])}}}",
    ]
    if public:
        lines.extend(
            [
                r"\vspace{0.6cm}",
                tex_escape(author["given"] + " " + author["family"]) + r"\par",
                tex_escape(author["institution"]) + r"\par",
                tex_escape(author["email"]) + r"\par",
            ]
        )
    lines.extend([r"\end{center}", r"\vspace{0.8cm}", tex_escape(explanation)])

    if public:
        if config["public_supplement_url"]:
            lines.append(
                r"\textbf{Public URL:} \url{" + config["public_supplement_url"] + "}"
            )
        else:
            lines.append(
                r"\textbf{Public URL:} To be inserted after the supplement is posted on the author's site."
            )

    lines.extend([r"\section*{Included sections}", r"\begin{itemize}"])
    lines.extend(r"\item " + tex_escape(item) for item in included)
    lines.append(r"\end{itemize}")
    if omitted:
        lines.extend(
            [
                r"\section*{Available in Online Resource 1}",
                r"\begin{itemize}",
            ]
        )
        lines.extend(r"\item " + tex_escape(item) for item in omitted)
        lines.append(r"\end{itemize}")
    lines.extend([r"\end{document}", ""])
    return "\n\n".join(lines)


def write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(content, encoding="utf-8", newline="\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--source", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--bibliography", type=Path, default=DEFAULT_BIBLIOGRAPHY)
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD)
    args = parser.parse_args()

    config = read_json(args.config)
    source = args.source.read_text(encoding="utf-8")
    _, body = split_rmd(source)
    body = normalize_body(body, config)

    marker = "\n# Appendix\n"
    if body.count(marker) != 1:
        raise ValueError("Expected exactly one top-level '# Appendix' marker")
    main_body, appendix_body = body.split(marker, 1)

    standalone_main = replace_appendix_crossrefs_for_standalone_main(main_body)
    standalone_main += "\n"

    inline_appendix = force_appendix_section_page_breaks(appendix_body)
    inline_marker = "\n\\appendix\n\n# Appendix {-}\n"
    inline_full = main_body + inline_marker + inline_appendix

    supplement_marker = "\n# Supplementary Information {-}\n\n"
    supplement_numbering = "\n".join(
        [
            r"\setcounter{figure}{0}",
            r"\renewcommand{\thefigure}{S\arabic{figure}}",
            r"\setcounter{table}{0}",
            r"\renewcommand{\thetable}{S\arabic{table}}",
            r"\setcounter{equation}{0}",
            r"\renewcommand{\theequation}{S\arabic{equation}}",
            "",
        ]
    )
    supplement_full = (
        main_body
        + supplement_marker
        + supplement_numbering
        + force_appendix_section_page_breaks(appendix_body)
    )

    build_dir = args.build_dir
    build_dir.mkdir(parents=True, exist_ok=True)
    write(
        build_dir / "cpsr_manuscript_anonymous.Rmd",
        build_yaml(config, "main") + standalone_main,
    )
    write(
        build_dir / "cpsr_full_inline_anonymous.Rmd",
        build_yaml(config, "inline") + inline_full,
    )
    write(
        build_dir / "cpsr_full_supplement_anonymous.Rmd",
        build_yaml(config, "supplement") + supplement_full,
    )
    write(build_dir / "cpsr_title_page.tex", title_page_tex(config))
    write(build_dir / "cpsr_cover_letter.tex", cover_letter_tex(config))
    write(
        build_dir / "cpsr_appendix_full_cover.tex",
        appendix_cover_tex(config, "full"),
    )
    write(
        build_dir / "cpsr_appendix_short_cover.tex",
        appendix_cover_tex(config, "short"),
    )
    write(
        build_dir / "cpsr_online_resource_anonymous_cover.tex",
        appendix_cover_tex(config, "online"),
    )
    write(
        build_dir / "cpsr_online_supplement_public_cover.tex",
        appendix_cover_tex(config, "online", public=True),
    )
    bibliography, duplicate_bib_keys = deduplicate_bibliography(
        args.bibliography.read_text(encoding="utf-8")
    )
    write(build_dir / "cpsr_references.bib", bibliography)

    provenance = {
        "canonical_source": str(args.source.resolve()),
        "config": str(args.config.resolve()),
        "canonical_bibliography": str(args.bibliography.resolve()),
        "bibliography_duplicate_keys_removed": duplicate_bib_keys,
        "generated_sources": sorted(path.name for path in build_dir.glob("*.Rmd"))
        + sorted(path.name for path in build_dir.glob("*.tex"))
        + sorted(path.name for path in build_dir.glob("*.bib")),
        "does_not_run_targets_pipeline": True,
    }
    write(
        build_dir / "source_provenance.json",
        json.dumps(provenance, indent=2, ensure_ascii=False) + "\n",
    )


if __name__ == "__main__":
    main()
