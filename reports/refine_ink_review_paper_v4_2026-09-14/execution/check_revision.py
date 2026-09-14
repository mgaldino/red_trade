#!/usr/bin/env python3
"""Mechanical revision checks; no estimation or analytical validation."""
from pathlib import Path
import hashlib
import json
import re
import subprocess
import argparse

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
parser = argparse.ArgumentParser()
parser.add_argument("--source", type=Path, default=ROOT / "paper_v4.Rmd")
args = parser.parse_args()
source = args.source.read_text(encoding="utf-8")
baseline = (OUT / "baseline/paper_v4.Rmd").read_text(encoding="utf-8")
protected = json.loads((OUT / "protected_reference_hashes.json").read_text())
checks = {}
checks["protected_files_unchanged"] = all(
    hashlib.sha256((ROOT / path).read_bytes()).hexdigest() == sha
    for path, sha in protected.items()
)
checks["git_diff_check"] = subprocess.run(
    ["git", "diff", "--check"], cwd=ROOT, capture_output=True, text=True
).returncode == 0
candidate_diff = subprocess.run(
    ["git", "diff", "--no-index", "--check", str(OUT / "baseline/paper_v4.Rmd"), str(args.source)],
    cwd=ROOT, capture_output=True, text=True
)
checks["candidate_whitespace_check"] = not (candidate_diff.stdout.strip() or candidate_diff.stderr.strip())
labels = re.findall(r"^```\{r\s+([^,}\s]+)", source, re.M)
checks["chunk_labels_unique"] = len(labels) == len(set(labels))
refs = re.findall(r"\\@ref\((?:fig|tab):([^)]*)\)", source)
checks["cross_references_resolve_to_chunks"] = set(refs) <= set(labels)
keys = set(re.findall(r"@\w+\s*\{\s*([^,\s]+)", (ROOT / "synth-trade-china.bib").read_text()))
citations = set(re.findall(r"(?<![\w\\])@([A-Za-z][\w:.-]*)", source)) - {"ref"}
# Sentence-final punctuation is outside an unbracketed Pandoc citation key.
citations = {c if c in keys else c.rstrip(".,;:") for c in citations}
missing = sorted(citations - keys)
checks["bibliographic_keys_resolve"] = not missing
old_abstract = re.search(r"^abstract:.*$", baseline, re.M).group()
new_abstract = re.search(r"^abstract:.*$", source, re.M).group()
report = {
    "checks": checks,
    "missing_bibliographic_keys": missing,
    "abstract_changed_requires_independent_numerical_gate": old_abstract != new_abstract,
    "source_path": str(args.source),
    "source_sha256": hashlib.sha256(args.source.read_bytes()).hexdigest(),
    "scope": "Mechanical source/diff/reference checks only; scientific and visual reviews are separate.",
}
(OUT / "mechanical_checks.json").write_text(json.dumps(report, indent=2) + "\n")
print(json.dumps(report, indent=2))
raise SystemExit(0 if all(checks.values()) else 1)
