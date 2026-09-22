#!/usr/bin/env python3
"""Create and verify portable Springer LaTeX source bundles.

The RMarkdown renders intentionally retain project paths while they are built in
the repository. This script rewrites every graphics reference to a local
``figures/`` directory, copies the deduplicated bibliography and vendored
Springer runtime files, verifies each source tree in an isolated temporary
directory, and writes a deterministic ZIP for submission.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import subprocess
import tempfile
import time
import zipfile
from pathlib import Path

from pypdf import PdfReader


ROOT = Path(__file__).resolve().parents[2]
DEFAULT_CONFIG = ROOT / "submission" / "cpsr" / "cpsr_submission_config.json"
DEFAULT_RAW = ROOT / "output" / "submission" / "cpsr" / "raw"
DEFAULT_BUILD = ROOT / "output" / "submission" / "cpsr" / "build"
DEFAULT_SOURCE = ROOT / "output" / "submission" / "cpsr" / "latex_sources"
DEFAULT_FINAL = ROOT / "output" / "submission" / "cpsr" / "final"
VENDOR = ROOT / "submission" / "cpsr" / "vendor"

GRAPHICS_PATTERN = re.compile(
    r"(\\includegraphics(?:\[[^\]]*\])?\{)([^}]+)(\})"
)
GRAPHICS_EXTENSIONS = (".pdf", ".png", ".jpg", ".jpeg", ".eps")
VENDOR_FILES = ("sn-jnl.cls", "sn-basic.bst", "cuted.sty", "appendix.sty")
VARIANTS = {
    "manuscript_anonymous": "cpsr_manuscript_anonymous",
    "manuscript_with_full_appendix_anonymous": "cpsr_full_inline_anonymous",
    "online_resource_1_anonymous": "cpsr_full_supplement_anonymous",
}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def resolve_graphic(reference: str) -> Path:
    candidate = Path(reference)
    if not candidate.is_absolute():
        candidate = ROOT / candidate
    if candidate.is_file():
        return candidate.resolve()
    if not candidate.suffix:
        for suffix in GRAPHICS_EXTENSIONS:
            with_suffix = candidate.with_suffix(suffix)
            if with_suffix.is_file():
                return with_suffix.resolve()
    raise FileNotFoundError(f"Could not resolve LaTeX graphic: {reference}")


def portable_tex(source: Path, destination: Path) -> list[Path]:
    text = source.read_text(encoding="utf-8")
    copied: dict[Path, str] = {}
    used_names: set[str] = set()

    def replace(match: re.Match[str]) -> str:
        resolved = resolve_graphic(match.group(2))
        if resolved not in copied:
            name = resolved.name
            if name in used_names:
                name = f"{resolved.stem}_{sha256(resolved)[:10]}{resolved.suffix}"
            used_names.add(name)
            copied[resolved] = f"figures/{name}"
        return match.group(1) + copied[resolved] + match.group(3)

    rewritten = GRAPHICS_PATTERN.sub(replace, text)
    if str(ROOT) in rewritten or re.search(r"/Users/|[A-Za-z]:\\\\", rewritten):
        raise AssertionError(f"Absolute local path remains in {source.name}")

    destination.mkdir(parents=True, exist_ok=True)
    (destination / source.name).write_text(rewritten, encoding="utf-8", newline="\n")
    figure_dir = destination / "figures"
    figure_dir.mkdir(parents=True, exist_ok=True)
    for original, relative in copied.items():
        shutil.copy2(original, destination / relative)
    return sorted(copied)


def copy_runtime(destination: Path, bibliography: Path) -> None:
    shutil.copy2(bibliography, destination / "cpsr_references.bib")
    for name in VENDOR_FILES:
        source = VENDOR / name
        if not source.is_file():
            raise FileNotFoundError(f"Missing vendored LaTeX runtime file: {source}")
        shutil.copy2(source, destination / name)
    shutil.copy2(VENDOR / "SOURCE.md", destination / "TEMPLATE_SOURCE.md")


def verify_variant(directory: Path, tex_name: str, expected_pages: int) -> None:
    with tempfile.TemporaryDirectory(prefix="cpsr-latex-source-") as temporary:
        work = Path(temporary) / directory.name
        shutil.copytree(directory, work)
        environment = os.environ.copy()
        environment.update(
            {
                "LANG": "en_US.UTF-8",
                "LC_ALL": "en_US.UTF-8",
                "TZ": "UTC",
                "SOURCE_DATE_EPOCH": "1790078400",
                "FORCE_SOURCE_DATE": "1",
                "OMP_NUM_THREADS": "1",
            }
        )
        subprocess.run(
            [
                "latexmk",
                "-pdf",
                "-interaction=nonstopmode",
                "-halt-on-error",
                tex_name,
            ],
            cwd=work,
            env=environment,
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        compiled = work / f"{Path(tex_name).stem}.pdf"
        page_count = len(PdfReader(compiled).pages)
        if page_count != expected_pages:
            raise AssertionError(
                f"Portable source page mismatch for {tex_name}: "
                f"expected {expected_pages}, compiled {page_count}"
            )


def fixed_zip(output: Path, source_root: Path, epoch: int) -> None:
    date_time = time.gmtime(epoch)[:6]
    files = sorted(
        (path for path in source_root.rglob("*") if path.is_file()),
        key=lambda path: path.relative_to(source_root).as_posix().casefold(),
    )
    with zipfile.ZipFile(
        output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9
    ) as archive:
        for path in files:
            relative = path.relative_to(source_root).as_posix()
            info = zipfile.ZipInfo(relative, date_time=date_time)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o100644 << 16
            info.create_system = 3
            archive.writestr(info, path.read_bytes(), compresslevel=9)


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--raw-dir", type=Path, default=DEFAULT_RAW)
    parser.add_argument("--build-dir", type=Path, default=DEFAULT_BUILD)
    parser.add_argument("--source-dir", type=Path, default=DEFAULT_SOURCE)
    parser.add_argument("--final-dir", type=Path, default=DEFAULT_FINAL)
    args = parser.parse_args()

    config = json.loads(args.config.read_text(encoding="utf-8"))
    bibliography = args.build_dir / "cpsr_references.bib"
    if not bibliography.is_file():
        raise FileNotFoundError(f"Missing generated bibliography: {bibliography}")

    if args.source_dir.exists():
        shutil.rmtree(args.source_dir)
    args.source_dir.mkdir(parents=True)

    report: dict[str, object] = {
        "source_date_epoch": int(config["source_date_epoch"]),
        "variants": {},
    }
    for directory_name, stem in VARIANTS.items():
        raw_tex = args.raw_dir / f"{stem}.tex"
        raw_pdf = args.raw_dir / f"{stem}.pdf"
        if not raw_tex.is_file() or not raw_pdf.is_file():
            raise FileNotFoundError(f"Missing rendered source pair for {stem}")
        destination = args.source_dir / directory_name
        graphics = portable_tex(raw_tex, destination)
        copy_runtime(destination, bibliography)
        expected_pages = len(PdfReader(raw_pdf).pages)
        verify_variant(destination, raw_tex.name, expected_pages)
        report["variants"][directory_name] = {
            "tex": raw_tex.name,
            "expected_pages": expected_pages,
            "graphics": len(graphics),
            "verified_isolated_compile": True,
        }

    readme = """# CPSR portable LaTeX sources

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
"""
    (args.source_dir / "README.md").write_text(
        readme, encoding="utf-8", newline="\n"
    )
    (args.source_dir / "verification.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False) + "\n",
        encoding="utf-8",
        newline="\n",
    )

    manifest_files = sorted(
        (path for path in args.source_dir.rglob("*") if path.is_file()),
        key=lambda path: path.relative_to(args.source_dir).as_posix().casefold(),
    )
    manifest_text = "".join(
        f"{sha256(path)}  {path.relative_to(args.source_dir).as_posix()}\n"
        for path in manifest_files
    )
    (args.source_dir / "SOURCE_MANIFEST.sha256").write_text(
        manifest_text, encoding="utf-8", newline="\n"
    )

    output = args.final_dir / "CPSR_LaTeX_Sources.zip"
    fixed_zip(output, args.source_dir, int(config["source_date_epoch"]))
    print(f"Portable LaTeX sources verified and packaged: {output}")


if __name__ == "__main__":
    main()
