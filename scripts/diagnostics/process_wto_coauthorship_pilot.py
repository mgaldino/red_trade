#!/usr/bin/env python3
"""Processa listas oficiais do WTO Documents Online para o piloto de coautoria.

Entrada: data/raw/wto_coauthorship/2026-08-28/search_title_*.json
Saídas: data/processed/wto_coauthorship/*.csv

Este script não acessa a rede. A classificação automática é apenas uma triagem
para validação manual; ela não é o outcome substantivo.
"""

from __future__ import annotations

import csv
import hashlib
import json
import re
from collections import defaultdict
from datetime import datetime
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
RAW_DIR = ROOT / "data" / "raw" / "wto_coauthorship" / "2026-08-28"
OUT_DIR = ROOT / "data" / "processed" / "wto_coauthorship"

COUNTRIES = {
    "Brazil": "BRA",
    "China": "CHN",
    "India": "IND",
    "South Africa": "ZAF",
    "Mexico": "MEX",
    "Indonesia": "IDN",
    "Turkey": "TUR",
    "Argentina": "ARG",
}
PRIMARY_PARTNERS = {"CHN", "IND", "ZAF"}

FORMAL_MARKERS = (
    "communication from",
    "communications from",
    "communication by",
    "joint communication",
    "proposal by",
    "proposal from",
    "draft proposal by",
    "joint proposal",
    "joint statement",
    "co-sponsors",
    "co-sponsoring",
    "submission from",
    "submission by",
)

EXCLUSION_PATTERNS = (
    r"request for consultations",
    r"request to join consultations",
    r"questions? (?:from|posed by).*(?:to|regarding)",
    r"replies? (?:from|by).*(?:to|questions)",
    r"response to measures proposed in joint statement",
    r"report on .*joint statement",
)


def clean(text: str | None) -> str:
    return re.sub(r"\s+", " ", text or "").strip()


def normalize_title(text: str | None) -> str:
    return clean(text).replace("[…]", "[...]")


def family_root(symbol: str) -> str:
    """Remove sufixos de revisão/addendum/corrigendum do símbolo oficial."""
    roots = []
    for part in re.split(r"\s*;\s*", symbol):
        root = re.sub(r"/(?:Rev|Add|Corr)\.?\d+$", "", part, flags=re.I)
        roots.append(root)
    return " ; ".join(roots)


def revision_type(symbol: str) -> str:
    tags = []
    if re.search(r"/Rev\.?\d+", symbol, re.I):
        tags.append("revision")
    if re.search(r"/Add\.?\d+", symbol, re.I):
        tags.append("addendum")
    if re.search(r"/Corr\.?\d+", symbol, re.I):
        tags.append("corrigendum")
    return ";".join(tags) if tags else "original_or_unspecified"


def authorship_segment(title: str) -> tuple[str, str]:
    """Extrai, de modo conservador, o trecho que parece listar signatários."""
    lower = title.lower()
    if any(re.search(pat, lower) for pat in EXCLUSION_PATTERNS):
        return "", "excluded_relational_or_response_document"

    matches = []
    for marker in FORMAL_MARKERS:
        start = lower.rfind(marker)
        if start >= 0:
            matches.append((start, marker))
    if not matches:
        return "", "no_formal_marker_in_title"

    start, marker = max(matches)
    after = title[start + len(marker) :].strip(" :-")

    if marker in {"joint statement", "joint proposal", "joint communication"}:
        # Em muitos registros o tema vem após o marcador e a lista de membros
        # aparece no último segmento separado por travessão.
        dash_parts = [clean(x) for x in after.split(" - ") if clean(x)]
        country_counts = [sum(name.lower() in p.lower() for name in COUNTRIES) for p in dash_parts]
        if dash_parts and max(country_counts, default=0) >= 2:
            after = dash_parts[country_counts.index(max(country_counts))]
    else:
        after = after.split(" - ", 1)[0]

    return clean(after), f"formal_marker:{marker}"


def countries_in(text: str) -> list[str]:
    lower = text.lower()
    return [iso for name, iso in COUNTRIES.items() if name.lower() in lower]


def infer_topic(symbol: str, title: str) -> str:
    prefix_map = (
        (r"^(TN/MA|JOB/MA)", "acesso_a_mercados_nama"),
        (r"^(TN/C|IP/C)", "trips_biodiversidade"),
        (r"^(TN/AG|G/AG)", "agricultura"),
        (r"^(S/|JOB/SERV|RD/SERV)", "servicos"),
        (r"^WT/BFA", "orcamento_secretariado"),
        (r"^WT/MIN", "conferencia_ministerial"),
        (r"^WT/GC", "conselho_geral"),
        (r"^(G/ADP|G/SCM)", "defesa_comercial"),
        (r"^WT/DS", "solucao_de_controversias"),
        (r"^G/TBT", "barreiras_tecnicas"),
        (r"^G/SPS", "medidas_sps"),
        (r"^G/C/W", "comercio_de_bens"),
        (r"^WT/COMTD", "comercio_e_desenvolvimento"),
    )
    for pattern, topic in prefix_map:
        if re.search(pattern, symbol, re.I):
            return topic
    return clean(title.split(" - ", 1)[0]).lower().replace(" ", "_")[:80]


def deterministic_rank(row: dict[str, str], stratum: str) -> str:
    key = f"wto-pilot-2026-08-28|{stratum}|{row['catalogue_id']}|{row['symbol']}"
    return hashlib.sha256(key.encode("utf-8")).hexdigest()


def read_raw() -> list[dict[str, object]]:
    rows_by_catalogue: dict[str, dict[str, object]] = {}
    for path in sorted(RAW_DIR.glob("search_title_*.json")):
        payload = json.loads(path.read_text(encoding="utf-8"))
        partner_match = re.search(r"Brazil AND (.+)$", payload["query"]["title_query"])
        partner_name = (partner_match.group(1) if partner_match else "").strip('"')
        query_partner = COUNTRIES.get(partner_name, partner_name)
        for record in payload["records"]:
            key = str(record["catalogue_id"])
            if key not in rows_by_catalogue:
                rows_by_catalogue[key] = {
                    **record,
                    "query_partners": set(),
                    "raw_files": set(),
                    "search_urls": set(),
                }
            rows_by_catalogue[key]["query_partners"].add(query_partner)
            rows_by_catalogue[key]["raw_files"].add(str(path.relative_to(ROOT)))
            rows_by_catalogue[key]["search_urls"].add(payload["search_url"])

    output = []
    for row in rows_by_catalogue.values():
        row["query_partners"] = sorted(row["query_partners"])
        row["raw_files"] = sorted(row["raw_files"])
        row["search_urls"] = sorted(row["search_urls"])
        output.append(row)
    return output


def classify(rows: list[dict[str, object]]) -> list[dict[str, str]]:
    output = []
    for raw in rows:
        title = normalize_title(str(raw["title_displayed"]))
        segment, reason = authorship_segment(title)
        author_countries = countries_in(segment)
        query_partners = list(raw["query_partners"])
        formal_partners = sorted((set(author_countries) & set(query_partners)) - {"BRA"})
        predicted_formal = "BRA" in author_countries and bool(formal_partners)
        date = datetime.strptime(str(raw["date"]), "%d/%m/%Y")
        symbol = clean(str(raw["symbol"]))
        output.append(
            {
                "catalogue_id": str(raw["catalogue_id"]),
                "symbol": symbol,
                "family_root": family_root(symbol),
                "revision_type": revision_type(symbol),
                "title": title,
                "date": date.date().isoformat(),
                "year": str(date.year),
                "period_2009": "post" if date.year >= 2009 else "pre",
                "window_2005_2012": "1" if 2005 <= date.year <= 2012 else "0",
                "body_label": clean(title.split(" - ", 1)[0]),
                "topic": infer_topic(symbol, title),
                "access": clean(str(raw["access"])),
                "pages": str(raw["pages"] or ""),
                "languages_available": ";".join(raw["languages_available"]),
                "english_url": str(raw["english_url"] or ""),
                "query_partners": ";".join(query_partners),
                "authorship_segment_heuristic": segment,
                "author_countries_heuristic": ";".join(author_countries),
                "formal_partners_heuristic": ";".join(formal_partners),
                "predicted_formal_coauthorship": "1" if predicted_formal else "0",
                "heuristic_reason": reason,
                "raw_files": ";".join(raw["raw_files"]),
            }
        )
    return sorted(output, key=lambda r: (r["date"], r["symbol"]), reverse=True)


def write_csv(path: Path, rows: list[dict[str, str]], fields: list[str] | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not rows:
        raise RuntimeError(f"Sem linhas para escrever: {path}")
    fields = fields or list(rows[0].keys())
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def build_validation_sample(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    accessible = [
        row
        for row in rows
        if row["english_url"]
        and row["access"].lower() in {"unrestricted", "derestricted"}
        and set(row["query_partners"].split(";")) & PRIMARY_PARTNERS
    ]
    positives = [r for r in accessible if r["predicted_formal_coauthorship"] == "1"]
    negatives = [r for r in accessible if r["predicted_formal_coauthorship"] == "0"]

    positives.sort(key=lambda r: deterministic_rank(r, "positive"))
    negatives.sort(key=lambda r: deterministic_rank(r, "negative"))
    if len(positives) < 20 or len(negatives) < 20:
        raise RuntimeError(
            f"Amostra insuficiente: positivos={len(positives)}, negativos={len(negatives)}"
        )

    sample = []
    for stratum, selected in (("coauthorship_candidate", positives[:20]), ("false_positive_candidate", negatives[:20])):
        for row in selected:
            sample.append(
                {
                    "validation_stratum": stratum,
                    "catalogue_id": row["catalogue_id"],
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
    return sample


def main() -> None:
    raw_rows = read_raw()
    classified = classify(raw_rows)
    validation = build_validation_sample(classified)

    write_csv(OUT_DIR / "wto_title_search_results_2000_2014.csv", classified)
    write_csv(OUT_DIR / "wto_manual_validation_sample_40.csv", validation)

    counts = defaultdict(int)
    for row in classified:
        counts[(row["period_2009"], row["predicted_formal_coauthorship"])] += 1
    summary = [
        {
            "period_2009": period,
            "predicted_formal_coauthorship": predicted,
            "n_records": str(n),
        }
        for (period, predicted), n in sorted(counts.items())
    ]
    write_csv(OUT_DIR / "wto_heuristic_support_summary.csv", summary)

    print(
        json.dumps(
            {
                "raw_unique_records": len(raw_rows),
                "classified_records": len(classified),
                "heuristic_positive": sum(r["predicted_formal_coauthorship"] == "1" for r in classified),
                "validation_rows": len(validation),
            },
            ensure_ascii=False,
        )
    )


if __name__ == "__main__":
    main()
