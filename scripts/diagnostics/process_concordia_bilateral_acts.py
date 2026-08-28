#!/usr/bin/env python3
"""Processa a coleta bruta do Concórdia sem modificar os JSONs de origem."""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import re
import unicodedata
from collections import Counter, defaultdict
from datetime import datetime
from pathlib import Path
from typing import Any, Iterable


PROJECT_ROOT = Path(__file__).resolve().parents[2]
RAW_BASE = PROJECT_ROOT / "data" / "raw" / "concordia_bilateral_acts"
PROCESSED_BASE = (
    PROJECT_ROOT / "data" / "processed" / "diagnostics" / "concordia_bilateral_acts"
)
API_BASE = "https://aplicacao.itamaraty.gov.br/ApiConcordia"
PORTAL_BASE = "https://concordia.itamaraty.gov.br"

STRATEGIC_PATTERNS = [
    r"\bparceria estrategica\b",
    r"\bplano (?:de )?acao conjunta\b",
    r"\bplano decenal\b",
    r"\bcomissao .{0,80}\balto nivel\b",
    r"\bdialogo estrategico\b",
    r"\bagenda estrategica\b",
]

INSTRUMENT_PATTERNS = [
    ("Memorando de Entendimento", r"\bmemorando de entendimento\b"),
    ("Ajuste Complementar", r"\bajuste complementar\b"),
    ("Protocolo Complementar", r"\bprotocolo complementar\b"),
    ("Programa Executivo", r"\bprograma[- ]executivo\b"),
    ("Plano de Ação", r"\bplano (?:de )?acao\b"),
    ("Plano Decenal", r"\bplano decenal\b"),
    ("Comunicado Conjunto", r"\bcomunicado conjunto\b"),
    ("Declaração Conjunta", r"\bdeclaracao conjunta\b"),
    ("Troca de Notas", r"\btroca de notas\b"),
    ("Tratado", r"\btratado\b"),
    ("Convenção", r"\bconvencao\b"),
    ("Protocolo", r"\bprotocolo\b"),
    ("Acordo", r"\bacordo\b"),
    ("Ata", r"\bata\b"),
    ("Programa", r"\bprograma\b"),
]


def strip_accents(value: str) -> str:
    return "".join(
        char
        for char in unicodedata.normalize("NFKD", value)
        if not unicodedata.combining(char)
    )


def normalize_text(value: str | None) -> str:
    text = strip_accents(value or "").lower()
    text = re.sub(r"[^a-z0-9]+", " ", text)
    return re.sub(r"\s+", " ", text).strip()


def infer_instrument_type(title: str) -> str:
    normalized = normalize_text(title)
    for label, pattern in INSTRUMENT_PATTERNS:
        if re.search(pattern, normalized):
            return label
    return "Outro/não classificado"


def json_load(path: Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8"))


def latest_run() -> Path:
    runs = sorted(path for path in RAW_BASE.iterdir() if path.is_dir())
    if not runs:
        raise FileNotFoundError(f"Nenhuma execução encontrada em {RAW_BASE}")
    return runs[-1]


def parse_date(value: str | None) -> tuple[str, int | None, bool]:
    if not value:
        return "", None, False
    try:
        parsed = datetime.strptime(value, "%d/%m/%Y")
    except ValueError:
        return value, None, True
    return parsed.strftime("%Y-%m-%d"), parsed.year, False


def nested_id_title(value: Any) -> tuple[str, str]:
    if not isinstance(value, dict):
        return "", ""
    identifier = value.get("Id")
    return ("" if identifier is None else str(identifier), value.get("Titulo") or "")


def join_values(values: Iterable[Any]) -> str:
    return " | ".join(str(value).strip() for value in values if str(value).strip())


def write_csv(path: Path, rows: list[dict[str, Any]], fieldnames: list[str]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", encoding="utf-8", newline="") as stream:
        writer = csv.DictWriter(stream, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--raw-run",
        type=Path,
        help="Pasta de uma execução bruta; por padrão usa a mais recente.",
    )
    args = parser.parse_args()

    raw_run = (args.raw_run or latest_run()).resolve()
    manifest = json_load(raw_run / "run_manifest.json")
    run_id = raw_run.name
    output_dir = PROCESSED_BASE / run_id
    output_dir.mkdir(parents=True, exist_ok=True)
    partner_ids = manifest["partners"]

    details: dict[int, dict[str, Any]] = {}
    for path in sorted((raw_run / "details").glob("act_*.json")):
        details[int(path.stem.removeprefix("act_"))] = json_load(path)

    rows: list[dict[str, Any]] = []
    for partner in partner_ids:
        partner_slug = normalize_text(partner).replace(" ", "_")
        for page_path in sorted((raw_run / "searches" / partner_slug).glob("page_*.json")):
            page = json_load(page_path)
            for item in page.get("Items", []):
                act_id = int(item["Id"])
                detail = details.get(act_id, {})
                date_iso, year, invalid_date = parse_date(
                    detail.get("DataCelebracao") or item.get("DataCelebracao")
                )
                subjects = detail.get("Assuntos") or item.get("Assuntos") or []
                subject_names = [entry.get("Nome", "") for entry in subjects]
                principal_subjects = [
                    entry.get("Nome", "")
                    for entry in subjects
                    if bool(entry.get("IsPrincipal"))
                ]
                other_parties = detail.get("OutrasPartes") or item.get("OutrasPartes") or []
                documents = detail.get("Documentos") or item.get("Documentos") or []
                full_document = detail.get("DocumentoIntegra") or item.get("DocumentoIntegra")
                full_document_id = (
                    full_document.get("Id") if isinstance(full_document, dict) else None
                )
                amendment_ids = [entry.get("Id") for entry in detail.get("Emendas", [])]
                amended_ids = [entry.get("Id") for entry in detail.get("Emendendados", [])]
                replaced_id, replaced_title = nested_id_title(detail.get("AcordoSubstituido"))
                replacing_id, replacing_title = nested_id_title(detail.get("AcordoSubstituiu"))
                title = detail.get("Titulo") or item.get("Titulo") or ""
                normalized_title = normalize_text(title)
                strategic_match = next(
                    (
                        pattern
                        for pattern in STRATEGIC_PATTERNS
                        if re.search(pattern, normalized_title)
                    ),
                    "",
                )
                agreement_type = detail.get("TipoAcordo") or item.get("TipoAcordo") or ""
                another_party = detail.get("OutraParte") or item.get("OutraParte") or ""
                partner_in_parties = partner in [str(value).strip() for value in other_parties]
                row = {
                    "query_partner": partner,
                    "query_partner_id": partner_ids[partner],
                    "act_id": act_id,
                    "title": title,
                    "normalized_title": normalized_title,
                    "instrument_type_derived": infer_instrument_type(title),
                    "date_celebration": date_iso,
                    "year": year if year is not None else "",
                    "invalid_date": invalid_date,
                    "agreement_type": agreement_type,
                    "status": (
                        detail.get("Vigencia", {}).get("Vigencia", "")
                        if isinstance(detail.get("Vigencia"), dict)
                        else item.get("Vigencia", "")
                    ),
                    "another_party": another_party,
                    "other_parties": join_values(other_parties),
                    "n_other_parties": len(other_parties),
                    "partner_in_other_parties": partner_in_parties,
                    "subject_names": join_values(subject_names),
                    "principal_subjects": join_values(principal_subjects),
                    "n_subjects": len(set(subject_names)),
                    "signatory_brazil": detail.get("SignatarioBrasil") or "",
                    "signatory_other_party": join_values(
                        entry.get("NomeSignatario", "")
                        for entry in detail.get("SignatarioOutraParte", [])
                    ),
                    "celebration_location": detail.get("LocalCelebracao") or "",
                    "celebration_country": detail.get("NomePaisCelebracao") or "",
                    "direct_publication": detail.get("IsPublicacaoDireta"),
                    "amendment_ids": join_values(amendment_ids),
                    "amended_instrument_ids": join_values(amended_ids),
                    "replaced_instrument_id": replaced_id,
                    "replaced_instrument_title": replaced_title,
                    "replacing_instrument_id": replacing_id,
                    "replacing_instrument_title": replacing_title,
                    "has_explicit_revision_relation": bool(
                        amendment_ids or amended_ids or replaced_id or replacing_id
                    ),
                    "amendment_or_revision_title": bool(
                        re.search(
                            r"\b(emenda|protocolo alterando|revisao|aditamento|modifica)",
                            normalized_title,
                        )
                    ),
                    "strategic_instrument": bool(strategic_match),
                    "strategic_rule_match": strategic_match,
                    "record_url": f"{PORTAL_BASE}/detalhamento-acordo/{act_id}",
                    "full_document_id": full_document_id or "",
                    "full_document_url": (
                        f"{API_BASE}/Documento/download/{full_document_id}"
                        if full_document_id
                        else ""
                    ),
                    "n_additional_documents": len(documents),
                    "raw_search_file": str(page_path.relative_to(PROJECT_ROOT)),
                    "raw_detail_file": str(
                        (raw_run / "details" / f"act_{act_id}.json").relative_to(
                            PROJECT_ROOT
                        )
                    ),
                }
                rows.append(row)

    within_query_counts = Counter((row["query_partner"], row["act_id"]) for row in rows)
    partners_per_act: dict[int, set[str]] = defaultdict(set)
    for row in rows:
        partners_per_act[int(row["act_id"])].add(str(row["query_partner"]))
    title_date_counts = Counter(
        (row["query_partner"], row["normalized_title"], row["date_celebration"])
        for row in rows
        if row["normalized_title"]
    )

    for row in rows:
        row["duplicate_id_within_query"] = (
            within_query_counts[(row["query_partner"], row["act_id"])] > 1
        )
        row["n_partner_queries_for_act"] = len(partners_per_act[int(row["act_id"])])
        row["duplicate_id_across_partner_queries"] = (
            row["n_partner_queries_for_act"] > 1
        )
        row["same_title_date_duplicate"] = (
            title_date_counts[
                (row["query_partner"], row["normalized_title"], row["date_celebration"])
            ]
            > 1
        )
        row["missing_date"] = not bool(row["date_celebration"])
        row["missing_counterparty"] = not bool(row["another_party"])
        row["outside_requested_window"] = not (
            manifest["window"]["start_year"]
            <= int(row["year"] or -9999)
            <= manifest["window"]["end_year"]
        )
        row["analytic_bilateral"] = bool(
            row["agreement_type"] == "BL"
            and row["partner_in_other_parties"]
            and not row["missing_date"]
            and not row["outside_requested_window"]
        )

    analytic_rows = [row.copy() for row in rows if row["analytic_bilateral"]]
    package_counts = Counter(
        (row["query_partner"], row["date_celebration"]) for row in analytic_rows
    )
    for row in analytic_rows:
        package_size = package_counts[(row["query_partner"], row["date_celebration"])]
        row["same_day_package_size"] = package_size
        row["in_same_day_package"] = package_size >= 2

    subject_rows: list[dict[str, Any]] = []
    for row in analytic_rows:
        subjects = [value.strip() for value in row["subject_names"].split("|") if value.strip()]
        principal = {
            value.strip()
            for value in row["principal_subjects"].split("|")
            if value.strip()
        }
        for subject in sorted(set(subjects)):
            subject_rows.append(
                {
                    "query_partner": row["query_partner"],
                    "act_id": row["act_id"],
                    "date_celebration": row["date_celebration"],
                    "year": row["year"],
                    "subject": subject,
                    "is_principal": subject in principal,
                }
            )

    all_fields = list(rows[0].keys()) if rows else []
    analytic_fields = list(analytic_rows[0].keys()) if analytic_rows else []
    all_path = output_dir / "concordia_search_hits_2000_2014.csv"
    analytic_path = output_dir / "concordia_bilateral_acts_2000_2014.csv"
    subject_path = output_dir / "concordia_bilateral_act_subjects_2000_2014.csv"
    write_csv(all_path, rows, all_fields)
    write_csv(analytic_path, analytic_rows, analytic_fields)
    write_csv(
        subject_path,
        subject_rows,
        ["query_partner", "act_id", "date_celebration", "year", "subject", "is_principal"],
    )

    output_manifest = {
        "raw_run": str(raw_run.relative_to(PROJECT_ROOT)),
        "processed_at": datetime.now().astimezone().isoformat(timespec="seconds"),
        "decision_rules": {
            "analytic_bilateral": "TipoAcordo == BL; parceiro consultado consta em OutrasPartes; data válida na janela",
            "same_day_package": "dois ou mais atos bilaterais da mesma díade na mesma data",
            "strategic_instrument": STRATEGIC_PATTERNS,
            "instrument_type": "classificação derivada do título; não é campo nativo da API",
            "multilateral_handling": "preservado em search_hits; excluído do painel bilateral",
        },
        "counts": {
            "search_hits": len(rows),
            "unique_act_ids_all_hits": len({row["act_id"] for row in rows}),
            "analytic_bilateral_rows": len(analytic_rows),
            "unique_analytic_act_ids": len({row["act_id"] for row in analytic_rows}),
            "subject_rows": len(subject_rows),
        },
        "outputs": {},
    }
    for output_path in (all_path, analytic_path, subject_path):
        output_manifest["outputs"][str(output_path.relative_to(PROJECT_ROOT))] = {
            "sha256": sha256(output_path),
            "bytes": output_path.stat().st_size,
        }
    manifest_path = output_dir / "processing_manifest.json"
    manifest_path.write_text(
        json.dumps(output_manifest, ensure_ascii=False, indent=2) + "\n",
        encoding="utf-8",
    )
    print(output_dir)


if __name__ == "__main__":
    main()
