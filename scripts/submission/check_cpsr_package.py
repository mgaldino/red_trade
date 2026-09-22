#!/usr/bin/env python3
"""Validate, document, hash, and package the CPSR submission artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import time
import zipfile
from pathlib import Path

from pypdf import PdfReader


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = ROOT / "submission" / "cpsr" / "cpsr_submission_config.json"
DEFAULT_BUILD = ROOT / "output" / "submission" / "cpsr" / "build"
DEFAULT_FINAL = ROOT / "output" / "submission" / "cpsr" / "final"

GUIDELINES_URL = "https://link.springer.com/journal/41111/submission-guidelines"
TEMPLATE_URL = (
    "https://www.springernature.com/gp/authors/campaigns/latex-author-support/"
    "see-where-our-services-will-take-you/18782940"
)


def words(value: str) -> list[str]:
    return re.findall(r"\b[\w’'-]+\b", value, flags=re.UNICODE)


PDF_TEXT_TRANSLATION = str.maketrans(
    {
        "\x15": "-",
        "\x16": "-",
        "\x1b": "ff",
        "\x1c": "fi",
        "\x1d": "fl",
        "\x1e": "ffi",
        "\x1f": "ffl",
    }
)


def normalize_pdf_text(value: str) -> str:
    return re.sub(r"\s+", " ", value.translate(PDF_TEXT_TRANSLATION)).strip()


def audit_pdf_text(value: str) -> str:
    translated = value.translate(PDF_TEXT_TRANSLATION).replace("\r\n", "\n").replace("\r", "\n")
    return re.sub(r"[\x00-\x08\x0b-\x0c\x0e-\x1f]", "", translated)


def page_starts_with_heading(value: str, heading: str) -> bool:
    translated = value.translate(PDF_TEXT_TRANSLATION)
    lines = [re.sub(r"\s+", " ", line).strip() for line in translated.splitlines()]
    lines = [line for line in lines if line]
    wanted = normalize_pdf_text(heading)
    return any(line == wanted for line in lines[:8]) or wanted == normalize_pdf_text(" ".join(lines[:2]))


def pdf_text(path: Path) -> str:
    reader = PdfReader(path)
    return "\n".join(page.extract_text() or "" for page in reader.pages)


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def fixed_zip(output: Path, files: list[Path], epoch: int, base: Path) -> None:
    date_time = time.gmtime(epoch)[:6]
    output.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(
        output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
    ) as archive:
        for path in sorted(files, key=lambda item: item.name.casefold()):
            info = zipfile.ZipInfo(path.relative_to(base).as_posix(), date_time=date_time)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            info.create_system = 3
            archive.writestr(info, path.read_bytes(), compresslevel=9)


def require(condition: bool, message: str, checks: list[str]) -> None:
    if not condition:
        raise AssertionError(message)
    checks.append(message)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD)
    parser.add_argument("--final-dir", type=Path, default=DEFAULT_FINAL)
    args = parser.parse_args()

    config = json.loads(args.config.read_text(encoding="utf-8"))
    final = args.final_dir
    build = args.build_dir
    checks: list[str] = []

    expected = {
        "main": final / "CPSR_Manuscript_Anonymous.pdf",
        "inline": final / "CPSR_Manuscript_with_Full_Appendix_Anonymous.pdf",
        "full": final / "CPSR_Appendix_Full_Anonymous.pdf",
        "short": final / "CPSR_Appendix_Short_Anonymous.pdf",
        "online": final / "CPSR_Online_Resource_1_Anonymous.pdf",
        "public": final / "CPSR_Online_Supplement_Public.pdf",
        "title": final / "CPSR_Title_Page.pdf",
        "letter": final / "CPSR_Cover_Letter.pdf",
    }
    for label, path in expected.items():
        require(path.is_file() and path.stat().st_size > 0, f"{label} PDF exists", checks)

    source_zip = final / "CPSR_LaTeX_Sources.zip"
    require(
        source_zip.is_file() and source_zip.stat().st_size > 0,
        "portable LaTeX source ZIP exists",
        checks,
    )
    with zipfile.ZipFile(source_zip) as archive:
        source_names = archive.namelist()
        require(
            all(not Path(name).is_absolute() and ".." not in Path(name).parts for name in source_names),
            "source ZIP contains only relative safe paths",
            checks,
        )
        for directory in (
            "manuscript_anonymous",
            "manuscript_with_full_appendix_anonymous",
            "online_resource_1_anonymous",
        ):
            require(
                any(name.startswith(directory + "/") and name.endswith(".tex") for name in source_names),
                f"source ZIP contains TeX for {directory}",
                checks,
            )
        require(
            "SOURCE_MANIFEST.sha256" in source_names,
            "source ZIP contains its checksum manifest",
            checks,
        )

    abstract = " ".join(config["abstract"].values())
    abstract_n = len(words(abstract))
    keyword_n = len(config["keywords"])
    require(150 <= abstract_n <= 250, f"abstract has {abstract_n} words (required: 150-250)", checks)
    require(4 <= keyword_n <= 6, f"keywords count is {keyword_n} (required: 4-6)", checks)

    extracted_texts = {name: pdf_text(path) for name, path in expected.items()}
    texts = {
        name: normalize_pdf_text(value) for name, value in extracted_texts.items()
    }
    for name, path in expected.items():
        # Keep audit text synchronized with the PDFs on every build. These
        # derivatives are not submission files, but make content and anonymity
        # checks inspectable without relying on a particular PDF viewer.
        (final / f"{path.stem}.txt").write_text(
            audit_pdf_text(extracted_texts[name]).rstrip() + "\n",
            encoding="utf-8",
            newline="\n",
        )
    main_text = texts["main"]
    for label in ("Purpose", "Methods", "Results", "Conclusion"):
        require(label in main_text, f"main PDF contains structured abstract label: {label}", checks)
    methods_model_sentence = (
        "I develop a formal model in which public recognition increases the salience "
        "of a new trade rank"
    )
    require(
        main_text.index("Methods:")
        < main_text.index(methods_model_sentence)
        < main_text.index("Results:"),
        "formal-model sentence appears in Methods",
        checks,
    )
    require(
        "The cross-country results are mixed, but interpreted as consistent with the model."
        in main_text,
        "main PDF contains the approved cross-country abstract result",
        checks,
    )
    require(
        config["appendix_sections"][0] not in main_text,
        "standalone main PDF excludes appendix content",
        checks,
    )

    for heading in config["appendix_sections"]:
        require(heading in texts["full"], f"full appendix contains: {heading}", checks)
        require(heading in texts["online"], f"online resource contains: {heading}", checks)
    for heading in config["short_appendix_sections"]:
        require(heading in texts["short"], f"short appendix contains: {heading}", checks)
    omitted = [
        heading
        for heading in config["appendix_sections"]
        if heading not in set(config["short_appendix_sections"])
    ]
    short_reader = PdfReader(expected["short"])
    for heading in omitted:
        require(
            not any(
                page_starts_with_heading(page.extract_text() or "", heading)
                for page in short_reader.pages[1:]
            ),
            f"short appendix content omits: {heading}",
            checks,
        )

    anonymous_outputs = ("main", "inline", "full", "short", "online")
    identity_patterns = {
        "author given name": r"\bManoel\b",
        "author family name": r"\bGaldino\b",
        "author email": re.escape(config["author"]["email"]),
        "author ORCID": re.escape(config["author"]["orcid"]),
        "preprint DOI": re.escape(config["preprint"]["doi"].removeprefix("https://doi.org/")),
    }
    for output_name in anonymous_outputs:
        reader = PdfReader(expected[output_name])
        metadata_blob = " ".join(str(value or "") for value in (reader.metadata or {}).values())
        searchable = texts[output_name] + "\n" + metadata_blob
        for label, pattern in identity_patterns.items():
            require(
                re.search(pattern, searchable, flags=re.IGNORECASE) is None,
                f"{output_name} PDF contains no {label}",
                checks,
            )

    for source in build.glob("*_anonymous.Rmd"):
        source_text = source.read_text(encoding="utf-8")
        for label, pattern in identity_patterns.items():
            require(
                re.search(pattern, source_text, flags=re.IGNORECASE) is None,
                f"{source.name} contains no {label}",
                checks,
            )

    page_counts = {
        name: len(PdfReader(path).pages) for name, path in expected.items()
    }
    require(page_counts["main"] < page_counts["inline"], "body-only PDF is shorter than full inline PDF", checks)
    require(page_counts["short"] < page_counts["full"], "condensed appendix is shorter than full appendix", checks)

    checklist_path = final / "CPSR_Submission_Checklist.md"
    confirmations = [
        "Confirm the funding statement, grant/process number, and acknowledgment wording on the title page.",
        "Confirm the competing-interests declaration and the statement that the manuscript is not under consideration elsewhere.",
        "Confirm the preprint title and DOI disclosed in the cover letter.",
        "Add the final public URL to `public_supplement_url` only after choosing a non-identifying review strategy or after peer review; then rebuild.",
        "Upload the title page separately from every file sent for double-anonymous review.",
    ]
    page_lines = "\n".join(
        f"- `{path.name}`: {page_counts[name]} pages" for name, path in expected.items()
    )
    check_lines = "\n".join(f"- [x] {item}" for item in checks)
    confirmation_lines = "\n".join(f"- [ ] {item}" for item in confirmations)
    checklist = f"""# Chinese Political Science Review submission checklist

Generated from `paper_v4.Rmd` on {config['submission_date_iso']}. The build reads existing project outputs and does **not** execute `targets::tar_make()`.

## Automated checks

{check_lines}

## Journal-fit and format decisions

- Journal: {config['journal']}.
- Springer Nature class: `sn-jnl` with `referee,sn-basic` options (double-spaced review layout and author-year Springer Basic references).
- Structured abstract: {abstract_n} words across Purpose, Methods, Results, and Conclusion (journal range: 150-250).
- Keywords: {keyword_n}: {', '.join(config['keywords'])} (journal range: 4-6).
- The manuscript, appendices, and Online Resource 1 are anonymous. The title page and cover letter carry author identity.
- `CPSR_LaTeX_Sources.zip` contains three independently compiled portable source trees with local figures, bibliography, and vendored Springer runtime files.
- No explicit overall manuscript word limit or appendix word limit was found on the journal's current submission-guidelines page. Both the full and condensed appendix routes are retained so the package can be adapted if the portal or editor imposes a file-specific limit.
- Guidelines checked: <{GUIDELINES_URL}>
- Official Springer Nature LaTeX package: <{TEMPLATE_URL}>

## PDF inventory

{page_lines}

- `CPSR_LaTeX_Sources.zip`: portable, isolated-compile-verified LaTeX sources.

## Author confirmations before upload

{confirmation_lines}

## Recommended upload routes

1. Default route: anonymous manuscript + separate title page + cover letter + full anonymous appendix.
2. Condensed route, if an editor or portal imposes an appendix limit: anonymous manuscript + separate title page + cover letter + condensed anonymous appendix + anonymous Online Resource 1.
3. `CPSR_Online_Supplement_Public.pdf` is the author-identified website version. Do not upload it as a double-anonymous review file.
"""
    checklist_path.write_text(checklist, encoding="utf-8", newline="\n")

    full_files = [
        expected["main"],
        expected["title"],
        expected["letter"],
        expected["full"],
    ]
    short_files = [
        expected["main"],
        expected["title"],
        expected["letter"],
        expected["short"],
        expected["online"],
    ]
    fixed_zip(
        final / "CPSR_Submission_Full_Appendix.zip",
        full_files,
        int(config["source_date_epoch"]),
        final,
    )
    fixed_zip(
        final / "CPSR_Submission_Short_Appendix.zip",
        short_files,
        int(config["source_date_epoch"]),
        final,
    )

    artifact_files = sorted(
        [path for path in final.iterdir() if path.is_file() and path.name not in {"manifest.sha256", "artifact_manifest.json"}],
        key=lambda item: item.name.casefold(),
    )
    manifest = {
        "canonical_source": "paper_v4.Rmd",
        "journal": config["journal"],
        "generated_on": config["submission_date_iso"],
        "targets_pipeline_run": False,
        "abstract_word_count": abstract_n,
        "keyword_count": keyword_n,
        "public_supplement_url_configured": bool(config["public_supplement_url"]),
        "artifacts": [
            {
                "file": path.name,
                "bytes": path.stat().st_size,
                "sha256": sha256(path),
            }
            for path in artifact_files
        ],
    }
    (final / "artifact_manifest.json").write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
    )
    (final / "manifest.sha256").write_text(
        "".join(f"{sha256(path)}  {path.name}\n" for path in artifact_files),
        encoding="utf-8",
    )

    print(f"Validated {len(checks)} checks")
    print(f"Abstract words: {abstract_n}; keywords: {keyword_n}")
    for name, count in page_counts.items():
        print(f"{name}: {count} pages")


if __name__ == "__main__":
    main()
