#!/usr/bin/env python3
"""Codifica o piloto OMC após a validação manual, sem acesso à rede.

Este arquivo produz uma série *provisória* a partir das buscas de título por
pares. Ela serve para testar a mensuração e a viabilidade do desenho, não para
substituir um censo de todas as submissões brasileiras.
"""

from __future__ import annotations

import csv
import re
from collections import Counter
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
IN_RECORDS = ROOT / "data" / "processed" / "wto_coauthorship" / "wto_title_search_results_2000_2014.csv"
VALIDATION_FILES = [
    ROOT / "data" / "processed" / "wto_coauthorship" / "wto_manual_validation_results_40.csv",
    ROOT / "data" / "processed" / "wto_coauthorship" / "wto_mention_validation_results_20.csv",
]
OUT_DIR = ROOT / "data" / "processed" / "wto_coauthorship"

PARTNERS = ("CHN", "IND", "ZAF", "MEX", "IDN", "TUR", "ARG")
COUNTRY_PATTERNS = {
    "BRA": r"\bBrazil\b",
    "CHN": r"\bChina\b",
    "IND": r"\bIndia\b",
    "ZAF": r"\bSouth Africa\b",
    "MEX": r"\bMexico\b",
    "IDN": r"\bIndonesia\b",
    "TUR": r"\bTurkey\b",
    "ARG": r"\bArgentina\b",
}

STRICT_MARKERS = (
    "communication from", "communications from", "submission from", "submission by",
    "proposal by", "proposal from", "paper from", "paper by", "paper presented by",
    "discussion paper presented by", "non-paper presented by", "textual contribution",
)
STATEMENT_MARKERS = ("joint statement", "statement of", "statement by")
RELATIONAL_PATTERNS = (
    r"\brequest (?:for|to join|by).*consultations?\b",
    r"\brequest for the establishment of a panel\b",
    r"\brequest by .* for arbitration\b",
    r"\bquestions? (?:from|posed by|to)\b",
    r"\b(?:replies|responses?) (?:from|by|to)\b",
    r"\bnotification of objection\b",
    r"\bresponse to measures proposed\b",
    r"\bnote by the secretariat\b",
    r"\breport of the panel\b",
    r"\bpanel report\b",
    r"\bmutually agreed solution\b",
    r"\bconstitution of the panel\b",
    r"\bcomments from .* on issues raised by\b",
)


def read_csv(path: Path) -> list[dict[str, str]]:
    with path.open(encoding="utf-8", newline="") as handle:
        return list(csv.DictReader(handle))


def write_csv(path: Path, rows: list[dict[str, str]], fields: list[str] | None = None) -> None:
    if not rows:
        raise RuntimeError(f"Sem linhas para escrever: {path}")
    fields = fields or list(rows[0])
    with path.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def protect_hong_kong(text: str) -> str:
    return re.sub(r"Hong Kong,?\s+China", "HONG_KONG_WTO_MEMBER", text, flags=re.I)


def countries_in(text: str) -> set[str]:
    protected = protect_hong_kong(text)
    found = {iso for iso, pattern in COUNTRY_PATTERNS.items() if re.search(pattern, protected, re.I)}
    if "HONG_KONG_WTO_MEMBER" in protected:
        found.add("HKG")
    return found


def author_segment(title: str, category: str) -> str:
    """Extrai a lista provável de autores; evita usar países do assunto."""
    lower = title.lower()
    candidates: list[tuple[int, str]] = []
    markers = list(STRICT_MARKERS) + ["statement of", "statement by", "joint statement by", "letter from"]
    for marker in markers:
        position = lower.rfind(marker)
        if position >= 0:
            candidates.append((position, marker))

    # Formato excepcional: "Communication to [body] from [countries]".
    if "communication to " in lower and " from " in lower:
        position = lower.rfind(" from ")
        candidates.append((position, "from"))

    # Formato excepcional: "Joint Proposal ... - By Brazil, ...".
    if "joint proposal" in lower and " - by " in lower:
        position = lower.rfind(" - by ")
        candidates.append((position, "- by"))

    if candidates:
        position, marker = max(candidates)
        segment = title[position + len(marker) :].strip(" :-")
        return segment.split(" - ", 1)[0].strip()

    if category == "FORMAL_JOINT_STATEMENT" and " - " in title:
        return title.rsplit(" - ", 1)[-1].strip()
    if "communication " in lower:
        position = lower.rfind("communication ")
        return title[position + len("communication ") :].split(" - ", 1)[0].strip()
    return ""


def title_rule(row: dict[str, str]) -> dict[str, str]:
    title = row["title"]
    lower = title.lower()
    symbol = row["symbol"]

    if re.search(r"^WT/DS", symbol, re.I) or any(re.search(pattern, lower) for pattern in RELATIONAL_PATTERNS):
        category = "RELATIONAL_OR_DISPUTE_EXCLUDED"
        strict = False
        broad = False
    elif "letter from" in lower:
        category = "FORMAL_JOINT_LETTER"
        strict = False
        broad = True
    elif any(marker in lower for marker in STATEMENT_MARKERS):
        category = "FORMAL_JOINT_STATEMENT"
        strict = False
        broad = True
    elif "joint proposal" in lower or any(marker in lower for marker in STRICT_MARKERS):
        category = "NEGOTIATION_SUBMISSION"
        strict = True
        broad = True
    elif re.search(r"\bcommunication\s+(?:Brazil|Argentina|China|India|South Africa|Mexico|Indonesia|Turkey)\b", title, re.I):
        category = "NEGOTIATION_SUBMISSION"
        strict = True
        broad = True
    elif "joint statement on" in lower:
        category = "FORMAL_JOINT_STATEMENT"
        strict = False
        broad = True
    else:
        category = "UNRESOLVED_TITLE_ROLE"
        strict = False
        broad = False

    segment = author_segment(title, category)
    authors = countries_in(segment)
    inferred = set()
    ambiguity = ""

    # A interface abrevia títulos longos. Para os demais parceiros, a busca
    # exata do próprio título sustenta a imputação dentro de uma lista autoral.
    # Para CHN, "Hong Kong, China" torna essa imputação ambígua.
    if "[...]" in title and category in {"NEGOTIATION_SUBMISSION", "FORMAL_JOINT_STATEMENT", "FORMAL_JOINT_LETTER"}:
        query_partners = set(filter(None, row["query_partners"].split(";")))
        for partner in query_partners:
            if partner == "CHN" and "HKG" in authors and "CHN" not in authors:
                ambiguity = "CHN_query_may_be_HKG"
                continue
            if partner not in authors:
                authors.add(partner)
                inferred.add(partner)

    partner_authors = sorted(set(PARTNERS) & authors)
    is_joint = "BRA" in authors and bool(partner_authors)
    return {
        "coding_source": "title_rule_unvalidated",
        "coded_category": category,
        "coded_authors": ";".join(sorted(authors)),
        "coded_partner_authors": ";".join(partner_authors),
        "authors_inferred_from_truncated_query": ";".join(sorted(inferred)),
        "china_hong_kong_ambiguity": ambiguity,
        "is_joint_document": "1" if is_joint else "0",
        "in_strict_universe": "1" if strict and is_joint else "0",
        "in_broad_coordination_universe": "1" if broad and is_joint else "0",
    }


def validation_map() -> dict[str, dict[str, str]]:
    result: dict[str, dict[str, str]] = {}
    for path in VALIDATION_FILES:
        for row in read_csv(path):
            result[row["catalogue_id"]] = row
    return result


def manual_rule(row: dict[str, str]) -> dict[str, str]:
    classification = row["manual_classification"]
    joint = row["manual_is_joint_document"] == "1"
    strict = row["manual_in_strict_universe"] == "1"
    broad = joint and classification not in {"DISPUTE_ACTION", "RELATIONAL_NOT_COAUTHOR"}
    broad = broad and not classification.endswith("NOT_COAUTHOR")
    authors = set(filter(None, row["manual_authors"].split(";")))
    return {
        "coding_source": "manual_pdf_first_page_or_full_text",
        "coded_category": classification,
        "coded_authors": ";".join(sorted(authors)),
        "coded_partner_authors": ";".join(sorted(set(PARTNERS) & authors)),
        "authors_inferred_from_truncated_query": "",
        "china_hong_kong_ambiguity": "",
        "is_joint_document": "1" if joint else "0",
        "in_strict_universe": "1" if strict else "0",
        "in_broad_coordination_universe": "1" if broad else "0",
    }


def canonical_family(family_root: str) -> str:
    symbols = [piece.strip() for piece in family_root.split(";")]
    priorities = (r"^TN/", r"^G/AG/NG/", r"^JOB", r"^IP/", r"^WT/GC/")
    for pattern in priorities:
        for symbol in symbols:
            if re.search(pattern, symbol, re.I):
                return symbol
    return symbols[0]


def build_events(rows: list[dict[str, str]], universe_field: str) -> list[dict[str, str]]:
    candidates = []
    for row in rows:
        if row[universe_field] != "1":
            continue
        authors = set(filter(None, row["coded_authors"].split(";")))
        for partner in PARTNERS:
            if {"BRA", partner} <= authors:
                candidates.append((row["canonical_family"], partner, row["date"], row))

    first_by_pair: dict[tuple[str, str], tuple[str, dict[str, str]]] = {}
    for family, partner, event_date, row in sorted(candidates, key=lambda x: (x[0], x[1], x[2], x[3]["catalogue_id"])):
        first_by_pair.setdefault((family, partner), (event_date, row))

    events = []
    for (family, partner), (event_date, row) in sorted(first_by_pair.items(), key=lambda item: (item[1][0], item[0])):
        authors = set(filter(None, row["coded_authors"].split(";")))
        events.append(
            {
                "canonical_family": family,
                "partner": partner,
                "event_date": event_date,
                "year": event_date[:4],
                "period_2009": "post" if int(event_date[:4]) >= 2009 else "pre",
                "window_2005_2012": "1" if 2005 <= int(event_date[:4]) <= 2012 else "0",
                "topic": row["topic"],
                "symbol_at_first_observed_pair_authorship": row["symbol"],
                "catalogue_id": row["catalogue_id"],
                "revision_type": row["revision_type"],
                "authors_at_event": ";".join(sorted(authors)),
                "china_without_india_or_south_africa": "1" if partner == "CHN" and not ({"IND", "ZAF"} & authors) else "0",
                "india_or_south_africa_without_china": "1" if partner in {"IND", "ZAF"} and "CHN" not in authors else "0",
                "coding_source": row["coding_source"],
                "coverage_note": "pair-conditioned title-search pilot; not a census",
            }
        )
    return events


def main() -> None:
    validations = validation_map()
    records = []
    for row in read_csv(IN_RECORDS):
        coding = manual_rule(validations[row["catalogue_id"]]) if row["catalogue_id"] in validations else title_rule(row)
        output = dict(row)
        output["canonical_family"] = canonical_family(row["family_root"])
        output.update(coding)
        records.append(output)

    strict_events = build_events(records, "in_strict_universe")
    broad_events = build_events(records, "in_broad_coordination_universe")
    summary_counter = Counter((row["coding_source"], row["coded_category"], row["in_strict_universe"]) for row in records)
    summary = [
        {"coding_source": source, "coded_category": category, "in_strict_universe": strict, "n_records": str(n)}
        for (source, category, strict), n in sorted(summary_counter.items())
    ]

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    write_csv(OUT_DIR / "wto_pilot_coded_records_2000_2014.csv", records)
    write_csv(OUT_DIR / "wto_strict_dyad_family_events_2000_2014.csv", strict_events)
    write_csv(OUT_DIR / "wto_broad_dyad_family_events_2000_2014.csv", broad_events)
    write_csv(OUT_DIR / "wto_coding_summary.csv", summary)
    print(
        {
            "records": len(records),
            "manually_validated_records": sum(row["coding_source"].startswith("manual") for row in records),
            "strict_records": sum(row["in_strict_universe"] == "1" for row in records),
            "strict_dyad_family_events": len(strict_events),
            "broad_dyad_family_events": len(broad_events),
            "unresolved_title_roles": sum(row["coded_category"] == "UNRESOLVED_TITLE_ROLE" for row in records),
        }
    )


if __name__ == "__main__":
    main()
