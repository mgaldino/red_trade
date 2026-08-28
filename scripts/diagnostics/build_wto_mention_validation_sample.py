#!/usr/bin/env python3
"""Constrói a amostra auditável de 20 menções/falsos positivos do piloto OMC.

Os casos são escolhidos entre títulos que contêm Brasil e um parceiro, mas
cuja própria sintaxe oficial indica pergunta, resposta, objeção, relatório de
terceiro ou contencioso bilateral. A validação final continua sendo feita no
PDF, não no título.
"""

from __future__ import annotations

import csv
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INPUT = ROOT / "data" / "processed" / "wto_coauthorship" / "wto_title_search_results_2000_2014.csv"
OUTPUT = ROOT / "data" / "processed" / "wto_coauthorship" / "wto_mention_validation_sample_20.csv"

# Seleção fixa e versionada para tornar a auditoria exatamente reproduzível.
CATALOGUE_IDS = [
    "128049", "125627", "121883", "96991", "42271",
    "80918", "89561", "74369", "91865", "94881",
    "88674", "62444", "57238", "53721", "16369",
    "96450", "95090", "95091", "43525", "88943",
]


def main() -> None:
    with INPUT.open(encoding="utf-8", newline="") as handle:
        source = {row["catalogue_id"]: row for row in csv.DictReader(handle)}
    missing = sorted(set(CATALOGUE_IDS) - set(source))
    if missing:
        raise RuntimeError(f"IDs ausentes da coleta preservada: {missing}")

    fields = [
        "validation_stratum", "catalogue_id", "symbol", "family_root", "title",
        "date", "query_partners", "heuristic_authors", "english_url",
        "manual_classification", "manual_authors", "manual_evidence",
        "manual_notes", "reviewed_at",
    ]
    rows = []
    for catalogue_id in CATALOGUE_IDS:
        row = source[catalogue_id]
        rows.append(
            {
                "validation_stratum": "mention_or_false_positive",
                "catalogue_id": catalogue_id,
                "symbol": row["symbol"],
                "family_root": row["family_root"],
                "title": row["title"],
                "date": row["date"],
                "query_partners": row["query_partners"],
                "heuristic_authors": row["author_countries_heuristic"],
                "english_url": row["english_url"],
                "manual_classification": "PENDING",
                "manual_authors": "",
                "manual_evidence": "",
                "manual_notes": "",
                "reviewed_at": "",
            }
        )

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)
    print({"rows": len(rows), "output": str(OUTPUT.relative_to(ROOT))})


if __name__ == "__main__":
    main()
