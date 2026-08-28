#!/usr/bin/env python3
"""Gera manifesto SHA-256 determinístico para os brutos do piloto OMC."""

from __future__ import annotations

import hashlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RAW_ROOT = ROOT / "data" / "raw" / "wto_coauthorship"
OUTPUT = RAW_ROOT / "2026-08-28" / "checksums.sha256"


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def main() -> None:
    paths = sorted(
        path for path in RAW_ROOT.rglob("*")
        if path.is_file() and path != OUTPUT
    )
    lines = [f"{sha256(path)}  {path.relative_to(ROOT)}" for path in paths]
    OUTPUT.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print({"files_hashed": len(paths), "output": str(OUTPUT.relative_to(ROOT))})


if __name__ == "__main__":
    main()
