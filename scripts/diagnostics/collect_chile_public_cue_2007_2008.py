#!/usr/bin/env python3
"""Focused, reproducible Chile public-cue audit for the 2007-2008 M2 window.

Collecting creates immutable publisher raws, robots responses and a run
manifest. Building reads only the specified raw manifest and verifies its
checksums; it does not call targets or modify the 14-country legacy files.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
import subprocess
import unicodedata

import collect_status_cue_salience_extension as protocol

from collect_status_cue_salience_extension import (
    INVENTORY, LEGACY_COUNTRIES, LEGACY_EVIDENCE, ROOT, RobotsCache,
    candidate_url_hash, fetch_checked, norm, raw_text, read_csv, rel, sha,
    source_row, stamp, utc_now, write_csv, write_json_new, write_new,
)

RAW = ROOT / "data/raw/status_cue_salience/chile_2007_2008"
PROCESSED = ROOT / "data/processed/status_cue_salience"
REPORTS = ROOT / "quality_reports/status_cue_salience"
CANDIDATES = ROOT / "scripts/diagnostics/chile_public_cue_2007_2008_candidates.json"
QUERIES = RAW / "web_discovery_queries.json"
STEM = "chile_public_cue_2007_2008"
CONTEXT_URLS = {
    "sice_chile_china_chronology": "https://sice.oas.org/TPD/CHL_CHN/CHL_CHN_e.ASP",
    "subrei_china_agreement": "https://www.subrei.gob.cl/acuerdos-comerciales/acuerdos-comerciales-vigentes/china",
}
BASE_RAW_TEXT = protocol.raw_text


def raw_text(path: Path) -> str:
    """Preserve the original reading order of the user-supplied Safari print."""
    if path.suffix.lower() == ".pdf" and "chl_bcn_2007_10_01" in path.parts:
        result = subprocess.run(["pdftotext", "-raw", str(path), "-"], capture_output=True, text=True, timeout=45, check=False)
        return result.stdout if result.returncode == 0 else ""
    return BASE_RAW_TEXT(path)


# The shared protocol's source_row resolves raw_text in its defining module.
protocol.raw_text = raw_text


def sample() -> dict[str, str]:
    rows = [r for r in read_csv(INVENTORY) if r["iso3c"] == "CHL"]
    if len(rows) != 1 or rows[0]["first_entry"] != "2007" or rows[0]["displaced_at_first"] != "USA":
        raise ValueError("Chile M2 inventory entry/incumbent changed; reassess scope")
    return rows[0]


def candidates() -> list[dict[str, object]]:
    rows = json.loads(CANDIDATES.read_text(encoding="utf-8"))["candidates"]
    if len({r["source_id"] for r in rows}) != len(rows):
        raise ValueError("Duplicate source_id")
    for r in rows:
        if r["iso3c"] != "CHL" or r["publication_date"][:4] not in {"2007", "2008"}:
            raise ValueError(f"Out-of-window candidate: {r['source_id']}")
        if len(r["excerpt_under_25_words"].split()) >= 25:
            raise ValueError(f"Quote exceeds limit: {r['source_id']}")
    return rows


def capture(url: str, source_id: str, year: str, run: Path, robots: RobotsCache) -> dict[str, object]:
    result = fetch_checked(url, robots)
    body = result.pop("body", None)
    if body is not None:
        ctype = str(result.get("headers", {}).get("Content-Type", "")).casefold()
        suffix = ".pdf" if body.startswith(b"%PDF") else ".html" if "html" in ctype or b"<html" in body[:1000].lower() else ".bin"
        path = RAW / "CHL" / year / source_id / (stamp() + suffix)
        write_new(path, body)
        result.update({"raw_file": rel(path), "sha256": sha(path), "size_bytes": len(body)})
    final_url = str(result.get("final_url", url))
    decision, robots_file = robots.check(final_url) if final_url.startswith("https://") else ("insecure_redirect_stop", "")
    result["robots_status"] = decision
    result["robots_file"] = robots_file
    if robots_file and (ROOT / robots_file).is_file():
        result["robots_sha256"] = sha(ROOT / robots_file)
    result["source_id"] = source_id
    result["accessed_at"] = utc_now()
    return result


def capture_user_bcn_pdf(url: str, source_id: str) -> dict[str, object]:
    matches = [
        p for p in (ROOT / "quality_reports").glob("*.pdf")
        if unicodedata.normalize("NFC", p.name) == "Observatorio Asia Pacífico.pdf"
    ]
    if len(matches) != 1:
        raise ValueError("Expected one user-supplied Observatorio Asia Pacífico.pdf in quality_reports")
    supplied = matches[0]
    data = supplied.read_bytes()
    if not data.startswith(b"%PDF"):
        raise ValueError("User-supplied BCN file is not a PDF")
    path = RAW / "CHL" / "2007" / source_id / (stamp() + ".pdf")
    write_new(path, data)
    if sha(path) != sha(supplied):
        raise ValueError("PDF copy checksum mismatch")
    return {
        "url": url, "final_url": url, "status": "ok",
        "capture_method": "user_supplied_safari_print_pdf",
        "robots_status": "no_automated_publisher_fetch",
        "source_file": rel(supplied), "source_file_sha256": sha(supplied),
        "raw_file": rel(path), "sha256": sha(path), "size_bytes": len(data),
        "source_id": source_id, "accessed_at": utc_now(),
    }


def collect(rows: list[dict[str, object]]) -> Path:
    run = RAW / "runs" / stamp()
    run.mkdir(parents=True, exist_ok=False)
    robots = RobotsCache(run)
    manifest: dict[str, object] = {
        "run_at": utc_now(),
        "inventory": rel(INVENTORY),
        "inventory_sha256": sha(INVENTORY),
        "candidate_config": rel(CANDIDATES),
        "candidate_config_sha256": sha(CANDIDATES),
        "candidate_url_sha256": candidate_url_hash(rows),
        "query_log": rel(QUERIES),
        "query_log_sha256": sha(QUERIES),
        "sources": [],
        "context": [],
        "prior_blocked_attempts": [],
        "gdelt": {"status": "pre_2017_not_covered", "reason": "GDELT DOC 2.0 article discovery has documented useful coverage from 2017; no 2007-2008 request was made."},
    }
    for previous in sorted(RAW.glob("runs/*/manifest.json")):
        old = json.loads(previous.read_text(encoding="utf-8"))
        for record in old.get("sources", []):
            if record.get("source_id") == "chl_bcn_2007_10_01" and record.get("status") != "ok":
                manifest["prior_blocked_attempts"].append({"manifest": rel(previous), "sha256": sha(previous), "status": record["status"]})
    for c in rows:
        if c["source_id"] == "chl_bcn_2007_10_01":
            record = capture_user_bcn_pdf(str(c["url"]), str(c["source_id"]))
        else:
            record = capture(str(c["url"]), str(c["source_id"]), str(c["publication_date"])[:4], run, robots)
        manifest["sources"].append(record)
        print(f"{c['source_id']}: {record['status']}")
    for source_id, url in CONTEXT_URLS.items():
        record = capture(url, source_id, "context", run, robots)
        manifest["context"].append(record)
        print(f"{source_id}: {record['status']}")
    path = run / "manifest.json"
    write_json_new(path, manifest)
    return path


def verify_preserved_raws(manifest: dict[str, object], rows: list[dict[str, object]]) -> None:
    if {r["source_id"] for r in manifest["sources"]} != {r["source_id"] for r in rows}:
        raise ValueError("Candidate/manifest source mismatch")
    for r in list(manifest["sources"]) + list(manifest["context"]):
        raw = r.get("raw_file")
        if raw and (not (ROOT / raw).is_file() or sha(ROOT / raw) != r["sha256"]):
            raise ValueError(f"Raw checksum mismatch: {raw}")
        robots_file = r.get("robots_file")
        if robots_file and (not (ROOT / robots_file).is_file() or sha(ROOT / robots_file) != r["robots_sha256"]):
            raise ValueError(f"Robots checksum mismatch: {robots_file}")
    for previous in manifest.get("prior_blocked_attempts", []):
        if sha(ROOT / previous["manifest"]) != previous["sha256"]:
            raise ValueError(f"Prior blocked-attempt manifest mismatch: {previous['manifest']}")


def rebind_manifest(previous_path: Path, rows: list[dict[str, object]]) -> Path:
    """Bind corrected manual fields to the same URL set and hash-verified raws."""
    previous = json.loads(previous_path.read_text(encoding="utf-8"))
    for key, value in {
        "inventory_sha256": sha(INVENTORY),
        "candidate_url_sha256": candidate_url_hash(rows),
        "query_log_sha256": sha(QUERIES),
    }.items():
        if previous[key] != value:
            raise ValueError(f"Cannot reuse raws after {key} changed")
    verify_preserved_raws(previous, rows)
    run = RAW / "runs" / stamp()
    run.mkdir(parents=True, exist_ok=False)
    manifest = dict(previous)
    manifest["candidate_config_sha256"] = sha(CANDIDATES)
    manifest["rebound_at"] = utc_now()
    manifest["reused_from_manifest"] = {"path": rel(previous_path), "sha256": sha(previous_path)}
    path = run / "manifest.json"
    write_json_new(path, manifest)
    return path


def verify_manifest(path: Path, rows: list[dict[str, object]]) -> dict[str, object]:
    manifest = json.loads(path.read_text(encoding="utf-8"))
    expected = {
        "inventory_sha256": sha(INVENTORY),
        "candidate_config_sha256": sha(CANDIDATES),
        "candidate_url_sha256": candidate_url_hash(rows),
        "query_log_sha256": sha(QUERIES),
    }
    for key, value in expected.items():
        if manifest[key] != value:
            raise ValueError(f"Manifest input drift: {key}")
    verify_preserved_raws(manifest, rows)
    reused = manifest.get("reused_from_manifest")
    if reused and sha(ROOT / reused["path"]) != reused["sha256"]:
        raise ValueError(f"Reused-from manifest mismatch: {reused['path']}")
    return manifest


def build(path: Path, rows: list[dict[str, object]]) -> None:
    manifest = verify_manifest(path, rows)
    country = sample()
    fetches = {r["source_id"]: r for r in manifest["sources"]}
    evidence = []
    accepted: list[tuple[dict[str, object], dict[str, str]]] = []
    status = []
    for c in rows:
        fetch = fetches[c["source_id"]]
        row, count = source_row(c, fetch, country)
        evidence.append(row)
        if count:
            accepted.append((c, row))
        raw = ROOT / str(fetch.get("raw_file", ""))
        visible = raw_text(raw) if fetch.get("status") == "ok" and raw.is_file() else ""
        checks = {
            "sha256_ok": bool(raw.is_file() and sha(raw) == fetch.get("sha256")),
            "date_marker_ok": bool(c["date_marker"] and norm(str(c["date_marker"])) in norm(visible + (raw.read_bytes().decode("utf-8", "replace") if raw.is_file() else ""))),
            "claim_markers_ok": bool(c["content_markers"] and all(norm(str(m)) in norm(visible) for m in c["content_markers"])),
            "quote_ok": len(str(c["excerpt_under_25_words"]).split()) < 25 and norm(str(c["excerpt_under_25_words"])) in norm(visible),
        }
        status.append({"source_id": c["source_id"], "fetch_status": fetch["status"], "robots_status": fetch["robots_status"], "counted": count, **checks})
    publishers = {str(c["publisher_id"]) for c, _ in accepted}
    code = "high" if len(publishers) >= 2 else "medium" if accepted else "unknown"
    accepted_ids = {c["source_id"] for c, _ in accepted}
    if code != "high" or "chl_mundomaritimo_2007_02_19" not in accepted_ids or not {"chl_direcon_2007_05_q1_report", "chl_bcn_2007_10_01"} & accepted_ids:
        raise ValueError("Independent 2007 news and official sources did not verify; inspect raws before coding")
    qlog = json.loads(QUERIES.read_text(encoding="utf-8"))["queries"]
    if len(qlog) < 4 or any(q["iso3c"] != "CHL" for q in qlog):
        raise ValueError("Insufficient or out-of-scope query log")
    official_types = {"official", "official_speech", "official_statistics", "official_release"}
    source_types = {"newspaper", "business_news", "national_news_agency", "local_news"}
    country_row = {
        "iso3c": "CHL", "country_name": "Chile", "entry_year": "2007",
        "n_newspaper_sources_strong": str(sum(c["source_type"] in source_types for c, _ in accepted)),
        "n_official_sources_strong": str(sum(c["source_type"] in official_types for c, _ in accepted)),
        "n_total_strong_or_moderate": str(len(accepted)),
        "has_explicit_export_rank_label": "true",
        "has_explicit_generic_trade_partner_label": "false",
        "has_official_uptake": str(any(c["source_type"] in official_types for c, _ in accepted)).lower(),
        "has_newspaper_uptake": str(any(c["source_type"] in source_types for c, _ in accepted)).lower(),
        "salience_code": code, "negative_case_candidate": "no",
        "coding_rationale": "Independent 2007 Chilean news (El Mercurio via MundoMarítimo) and official DIRECON/BCN publications explicitly call China the first/main destination of national exports; 2008 Emol/EFE and El Mercurio reports corroborate. Counted claims concern goods-export destinations.",
        "remaining_gaps": "SUBREI page displayed as January 2007 has a chronology anomaly and is excluded. A December 2008 DIRECON release puts the US first in total two-way trade, a different metric. The DIRECON 2007 report ranks the EU bloc above China but China first among individual countries. Monthly/quarterly/semester cues do not by themselves verify the annual ITPD-E rank; treatment remains defined by the inventory.",
        "search_windows_tried": "2007-2008", "n_queries_logged": str(len(qlog)),
    }
    with LEGACY_EVIDENCE.open(encoding="utf-8-sig", newline="") as f:
        evidence_fields = list(csv.DictReader(f).fieldnames or []) + ["metric_in_source", "search_window"]
    with LEGACY_COUNTRIES.open(encoding="utf-8-sig", newline="") as f:
        country_fields = list(csv.DictReader(f).fieldnames or []) + ["search_windows_tried", "n_queries_logged"]
    evidence_path = PROCESSED / f"{STEM}_source_evidence.csv"
    country_path = PROCESSED / f"{STEM}_country_code.csv"
    write_csv(evidence_path, evidence_fields, evidence)
    write_csv(country_path, country_fields, [country_row])
    write_reports(path, manifest, rows, evidence, country_row, status, qlog)
    outputs = [
        evidence_path, country_path,
        PROCESSED / f"{STEM}_SOURCES.yaml",
        PROCESSED / f"{STEM}_DATA_DICTIONARY.md",
        REPORTS / f"{STEM}_collection_log.md",
        REPORTS / f"{STEM}.md",
    ]
    build_manifest = {
        "built_at": utc_now(),
        "script": {"path": rel(Path(__file__)), "sha256": sha(Path(__file__))},
        "inventory": {"path": rel(INVENTORY), "sha256": sha(INVENTORY)},
        "candidate_config": {"path": rel(CANDIDATES), "sha256": sha(CANDIDATES)},
        "query_log": {"path": rel(QUERIES), "sha256": sha(QUERIES)},
        "raw_manifest": {"path": rel(path), "sha256": sha(path)},
        "outputs": [{"path": rel(p), "sha256": sha(p)} for p in outputs],
    }
    (PROCESSED / f"{STEM}_build_manifest.json").write_text(json.dumps(build_manifest, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Built {code}: {len(accepted)} counted sources; {len(qlog)} queries")


def write_reports(path: Path, manifest: dict[str, object], rows: list[dict[str, object]], evidence: list[dict[str, str]], country: dict[str, str], status: list[dict[str, object]], queries: list[dict[str, object]]) -> None:
    sources = {s["source_id"]: s for s in manifest["sources"]}
    yes = {s["source_id"] for s in status if s["counted"]}
    dates_2007 = [c["publication_date"] for c in rows if c["source_id"] in yes and str(c["publication_date"]).startswith("2007")]
    dates_2008 = [c["publication_date"] for c in rows if c["source_id"] in yes and str(c["publication_date"]).startswith("2008")]
    log = [
        "# Chile public-cue collection log, 2007–2008", "",
        f"Collected at {manifest['run_at']} (UTC). Raw manifest: `{rel(path)}`. Inventory entry: 2007; incumbent: United States; source: `{rel(INVENTORY)}`.",
        f"Exact executed discovery queries and returned URLs: `{rel(QUERIES)}` ({len(queries)} queries; SHA-256 `{sha(QUERIES)}`). Searches covered English and Spanish, local press and Chilean official sites, plus the displaced United States.",
        "Search results were only leads. Countability requires the preserved publisher raw, in-window date, Chilean local/official source, explicit rank claim and SHA-256 verification.",
        "GDELT DOC 2.0 was not queried: useful article coverage begins in 2017, after this 2007–2008 window. The automated BCN publisher request stopped at robots.txt; the user later supplied a Safari PDF print of the complete page. No paywall, CAPTCHA, robots denial or other access restriction was bypassed.",
        "", "## Capture and validation", "",
        "| Source ID | HTTP/robots | Raw SHA-256 | Date | Claim | Count |",
        "|---|---|---|---|---|---|",
    ]
    if manifest.get("reused_from_manifest"):
        log.insert(3, f"Manual coding was rebound at {manifest['rebound_at']} from `{manifest['reused_from_manifest']['path']}` after all preserved raw and robots checksums were verified; original source access times are retained.")
    for s in status:
        fetch = sources[s["source_id"]]
        digest = fetch.get("sha256", "none")
        log.append(f"| {s['source_id']} | {s['fetch_status']} / {s['robots_status']} | `{digest}` | {s['date_marker_ok']} | {s['claim_markers_ok']} | {s['counted']} |")
    log += [
        "", "## Exceptions", "",
        f"- BCN automated-access stops are preserved in {len(manifest.get('prior_blocked_attempts', []))} prior immutable run manifests. The source counted here is the PDF supplied by the user from Safari, not a publisher HTML download; the PDF itself shows the source URL, 2007 article date, and full claim.",
        "- DIRECON's original 2007 first-quarter PDF is mirrored by the OAS/SICE and has a May 2007 cover, without an exact publication day. Its PDF metadata was created on 4 May 2007. The 2007-05 field has month precision. It reports China ahead of the US among individual countries, while the EU bloc is higher in a separate aggregate comparison.",
        "- SUBREI/DIRECON page displaying 25 January 2007 describes completed services negotiations and the start of investment negotiations. The official Chile-China agreement chronology and the OAS SICE timeline place those events in 2008 and 2009. The page is preserved but excluded because its displayed date is unreliable.",
        "- DIRECON release of 15 December 2008 says the United States was first in January–September total bilateral trade. The denominator is exports plus imports; it does not reverse the ranking of national goods-export destinations.",
        "- Emol carries an EFE dispatch. Its current export-destination statement counts as local publication, while the forecast that China would later become the first total-trade partner is not treated as an observed rank.",
        "- MundoMarítimo attributes its 2007 and 2008 stories to El Mercurio; they are one publisher family for independence counting. The 2007 DIRECON and BCN publications are separate official sources.",
        "", "## Reproduction", "",
        f"`python3 scripts/diagnostics/collect_chile_public_cue_2007_2008.py --build --manifest {rel(path)}`",
        f"`python3 scripts/diagnostics/collect_chile_public_cue_2007_2008.py --validate --manifest {rel(path)}`",
        "Use --collect for a new immutable capture run or --reuse-manifest for changed manual coding with identical source URLs. Collection may yield different pages as websites change. The recorded build is offline and hash-bound.",
    ]
    (REPORTS / f"{STEM}_collection_log.md").write_text("\n".join(log) + "\n", encoding="utf-8")
    report = [
        "# Chile: public cue na janela 2007–2008", "",
        f"**Resultado: `{country['salience_code']}` na janela de entrada M2 de 2007 e ano seguinte.** A codificação resulta de notícia chilena e publicações oficiais independentes de 2007, todas com rótulo explícito de principal destino das exportações; fontes de 2008 repetem o cue. O inventário goods-only aponta 2007 como primeira entrada e os Estados Unidos como parceiro antes no topo. Esta auditoria mede visibilidade pública, não altera a série de tratamento.",
        "", "Tabela 1. Documentos contemporâneos sobre a posição da China como destino das exportações chilenas.", "",
        "| Publicação | Fonte | Métrica/período referido | Uso na codificação |",
        "|---|---|---|---|",
        "| 19/02/2007 | [MundoMarítimo/El Mercurio](https://live.mundomaritimo.cl/noticias/china-parte-2007-como-principal-destino-de-exportaciones-chilenas) | Exportações nacionais de bens, janeiro de 2007; China acima dos EUA | Conta; notícia forte |",
        "| maio de 2007 (dia não indicado) | [DIRECON, relatório do primeiro trimestre](https://sice.oas.org/ctyindex/chl/DIRECON20071_s.pdf) | Exportações nacionais de bens, primeiro trimestre; China primeiro país individual, União Europeia primeiro bloco | Conta; relatório oficial forte |",
        "| 01/10/2007 | [Biblioteca do Congresso Nacional](https://www.bcn.cl/observatorio/asiapacifico/noticias/a-un-ano-del-tlc-con-china) | Exportações nacionais de bens, primeiro semestre de 2007 | Conta; PDF da página salvo pelo usuário |",
        "| 15/04/2008 | [Emol/EFE](https://www.emol.com/noticias/nacional/2008/04/15/300440/chile-impulsa-su-imagen-en-china-con-semana-de-actividades-en-shanghai.html) | Principal destino atual das exportações; primeiro parceiro comercial total apenas previsão | Conta só o cue de destino exportador |",
        "| 19/05/2008 | [MundoMarítimo/El Mercurio](https://live.mundomaritimo.cl/noticias/japon-es-el-segundo-destino-de-las-exportaciones-chilenas-desplazando-a-estados-unidos) | Exportações nacionais de bens, abril de 2008; China primeira, Japão segundo, EUA terceiro | Conta; mesma família editorial da notícia de 2007 |",
        "", f"As datas de publicação **contadas** são {', '.join(dates_2007)} em 2007 e {', '.join(dates_2008)} em 2008; `2007-05` registra somente mês e ano. `high` decorre da notícia de El Mercurio e de publicações oficiais de 2007; não é preciso tratar as duas republicações de El Mercurio como independentes.",
        "", "## Definição de rank e exclusões", "",
        "A página [SUBREI/DIRECON exibida como 25/01/2007](https://www.subrei.gob.cl/sala-de-prensa/noticias/detalhe-noticias/2007/01/26/comienzan-negociaciones-para-capitulo-de-inversiones-del-tlc-entre-chile-y-china) contém uma afirmação de primeiro destino exportador, mas descreve negociações de investimento posteriores. A [cronologia do acordo da SUBREI](https://www.subrei.gob.cl/acuerdos-comerciales/acuerdos-comerciales-vigentes/china) data o acordo de serviços de abril de 2008, e a [cronologia SICE/OEA](https://sice.oas.org/TPD/CHL_CHN/CHL_CHN_e.ASP) coloca o começo das negociações de investimentos em janeiro de 2009. O item fica como `DO_NOT_COUNT` por anomalia de data.",
        "Em [15/12/2008, DIRECON/SUBREI](https://www.subrei.gob.cl/sala-de-prensa/noticias/detalle-noticias/2008/12/16/el-comercio-entre-chile-y-estados-unidos-crecio-155-) disse que os EUA seguiam em primeiro no **intercâmbio comercial total** em janeiro–setembro de 2008. Essa métrica soma fluxos de comércio; as fontes positivas tratam do destino das exportações. Registramos a diferença de denominador, sem transformar o comunicado em contradição do rank de exportação.",
        "O relatório DIRECON de maio de 2007 também traz a União Europeia como primeiro **bloco** de destino, à frente da China. Na comparação entre países individuais, que corresponde à unidade do inventário M2, a China aparece acima dos EUA. Essa diferença de unidade fica explícita na codificação.",
        "Os textos de 2007 e 2008 se referem a mês ou semestre em vários trechos. Eles comprovam que o rótulo público já circulava nesses anos; o ano de entrada anual continua vindo do inventário ITPD-E. A previsão de Emol/EFE sobre China vir a liderar o comércio total em 2008 não é observação desse resultado.",
        "A página da BCN não foi coletada automaticamente após a falha no acesso a `robots.txt`. O PDF completo foi salvo e fornecido pelo usuário em 22/09/2026; ele contém URL, data da matéria, texto e autoria, e foi copiado sem alteração para `data/raw/` com hash SHA-256. O relatório DIRECON foi obtido por coleta automatizada com verificação de `robots.txt` e pode ser reproduzido sem o PDF do usuário.",
        "", "## Arquivos e escopo", "",
        f"Fontes, consultas e hashes: `{rel(path)}`, `{rel(QUERIES)}` e `{rel(PROCESSED / (STEM + '_build_manifest.json'))}`. Linhas prontas para uma futura fusão: `{rel(PROCESSED / (STEM + '_source_evidence.csv'))}` e `{rel(PROCESSED / (STEM + '_country_code.csv'))}`.",
        "Nenhum arquivo da codificação legada dos 14 países, manuscrito, alvo ou modelo foi modificado; a fusão com a tabela legada permanece uma decisão separada.",
    ]
    # Keep report links and source text within one citation location each.
    report = [line.replace("/noticias/detalhe-noticias/", "/noticias/detalle-noticias/") for line in report]
    (REPORTS / f"{STEM}.md").write_text("\n".join(report) + "\n", encoding="utf-8")
    source_lines = [
        "# Chile 2007–2008 source manifest", "# Local/official publisher documents; no redistribution license asserted.", "sources:"
    ]
    for c in rows:
        fetch = sources[c["source_id"]]
        source_lines += [
            f"  - id: {c['source_id']}",
            f"    name: {json.dumps(c['source_name'], ensure_ascii=False)}",
            f"    url: {json.dumps(c['url'], ensure_ascii=False)}",
            f"    access_method: {'user_supplied_safari_print_pdf' if c['source_id'] == 'chl_bcn_2007_10_01' else 'robots_checked_https'}",
            "    requires_credentials: false",
            "    license: original publisher terms",
            f"    publication_date_claimed: {json.dumps(c['publication_date'])}",
            f"    publication_date_precision: {'month' if c['source_id'] == 'chl_direcon_2007_05_q1_report' else 'day'}",
            f"    date_accessed: {json.dumps(fetch['accessed_at'])}",
            f"    metric_in_source: {c['metric_in_source']}",
            f"    raw_file: {json.dumps(fetch.get('raw_file', ''))}",
            f"    sha256: {json.dumps(fetch.get('sha256', ''))}",
            f"    counted: {str(c['source_id'] in yes).lower()}",
        ]
    (PROCESSED / f"{STEM}_SOURCES.yaml").write_text("\n".join(source_lines) + "\n", encoding="utf-8")
    dictionary = """# Chile public-cue 2007–2008 data dictionary

The source-evidence CSV keeps the 25 legacy fields in their original order and
adds `metric_in_source` and `search_window`, as in the 48-country extension.
Each row is one candidate publisher document, including excluded documents.
`notes` starts with `DO_NOT_COUNT` when the document fails countability.
The country-code CSV keeps the 14 legacy fields and adds
`search_windows_tried` and `n_queries_logged`.

`entry_year=2007` is the goods-only ITPD-E first-entry year from the inventory,
not a year inferred from the press. `salience_code=high` means two independent
strong/moderate sources in the 2007–2008 publication window. A repeated item from
the same publisher family does not establish independence. The search log counts
executed web-discovery queries; GDELT was unavailable for these years.

The DIRECON report's `publication_date=2007-05` is month precision, as printed
on its cover; no publication day was invented. The BCN publisher page could
not be fetched automatically after its robots check failed. The user supplied
a complete Safari PDF print; that PDF is copied byte-for-byte to `data/raw/`,
with its provenance recorded in the raw manifest. Its source date (2007) is
distinct from its capture date (2026).
"""
    (PROCESSED / f"{STEM}_DATA_DICTIONARY.md").write_text(dictionary, encoding="utf-8")


def validate(path: Path, rows: list[dict[str, object]]) -> None:
    verify_manifest(path, rows)
    record = json.loads((PROCESSED / f"{STEM}_build_manifest.json").read_text(encoding="utf-8"))
    for item in record["outputs"]:
        if sha(ROOT / item["path"]) != item["sha256"]:
            raise ValueError(f"Output checksum mismatch: {item['path']}")
    for item in (record["script"], record["inventory"], record["candidate_config"], record["query_log"], record["raw_manifest"]):
        if sha(ROOT / item["path"]) != item["sha256"]:
            raise ValueError(f"Build-input checksum mismatch: {item['path']}")
    countries = read_csv(PROCESSED / f"{STEM}_country_code.csv")
    evidence = read_csv(PROCESSED / f"{STEM}_source_evidence.csv")
    if len(countries) != 1 or countries[0]["iso3c"] != "CHL" or countries[0]["entry_year"] != "2007" or countries[0]["salience_code"] != "high":
        raise ValueError("Chile country code mismatch")
    if len(evidence) != len(rows) or any(r["iso3c"] != "CHL" or r["search_window"] != "2007-2008" for r in evidence):
        raise ValueError("Chile source evidence mismatch")
    if countries[0]["negative_case_candidate"] != "no":
        raise ValueError("Negative-case flag mismatch")
    print("PASS: raw/robots/input/output hashes, source count, window and country code")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--collect", action="store_true")
    parser.add_argument("--reuse-manifest", type=Path)
    parser.add_argument("--build", action="store_true")
    parser.add_argument("--validate", action="store_true")
    parser.add_argument("--manifest", type=Path)
    args = parser.parse_args()
    rows = candidates()
    sample()
    if not (args.collect or args.reuse_manifest or args.build or args.validate):
        parser.error("Choose --collect, --reuse-manifest, --build and/or --validate")
    if args.collect and args.reuse_manifest:
        parser.error("--collect and --reuse-manifest are mutually exclusive")
    if args.collect:
        path = collect(rows)
    elif args.reuse_manifest:
        old = ROOT / args.reuse_manifest if not args.reuse_manifest.is_absolute() else args.reuse_manifest
        path = rebind_manifest(old, rows)
    else:
        path = ROOT / args.manifest if args.manifest and not args.manifest.is_absolute() else args.manifest
    if path is None:
        parser.error("--manifest is required without --collect")
    if args.build:
        build(path, rows)
    if args.validate:
        validate(path, rows)
    print(f"Manifest: {rel(path)}")


if __name__ == "__main__":
    main()
