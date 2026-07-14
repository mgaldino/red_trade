#!/usr/bin/env python3
"""Collect and scan mechanism evidence for Brazil-China rank/status cue, 2009-2011.

This script downloads official raw sources used in the evidence package, extracts MRE/FUNAG
PDF text with `pdftotext -layout` when available, scans Fala.BR public filtered text zips for
MRE-China rank/status leads, and writes checksums for raw files. It does not edit the manuscript.
"""
from __future__ import annotations

import csv
import hashlib
import io
import os
import re
import shutil
import subprocess
import sys
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RAW = ROOT / "data/raw/mechanism_evidence_china_2009_2011"
REPORT = ROOT / "reports/mechanism_evidence_china_2009_2011"

MRE_SOURCES = {
    "Resenha_numero_104_1_2009.pdf": "https://www.funag.gov.br/chdd/images/Resenhas/Novas/Resenha_numero_104_1_2009.pdf",
    "resenha106_1_2010.pdf": "https://www.funag.gov.br/chdd/images/Resenhas/Novas/resenha106_1_2010.pdf",
    "Resenha108_1Sem_2011.pdf": "https://www.funag.gov.br/chdd/images/Resenhas/Novas/Resenha108_1Sem_2011.pdf",
    "Resenha109_2Sem_2011.pdf": "https://www.funag.gov.br/chdd/images/Resenhas/Novas/Resenha109_2Sem_2011.pdf",
}
CAMARA = {
    "camara_noticias_222695_2011.html": "https://www.camara.leg.br/noticias/222695-comissao-aprova-acordo-de-direitos-civil-e-comercial-entre-brasil-e-china/"
}
FALABR_URL = "https://dadosabertos-download.cgu.gov.br/FalaBR/Arquivos_FalaBR_Filtrado/Arquivos_csv_{year}.zip"

ORG_PAT = re.compile(r"(\bMRE\b|Rela[cç][oõ]es Exteriores|Itamaraty|Minist[eé]rio das Rela[cç][oõ]es Exteriores)", re.I)
CHINA_PAT = re.compile(r"China|chin[eê]s|chinesa|chineses|sino-?brasil|Pequim|Xangai|Hong Kong|Taiwan", re.I)
RANK_PAT = re.compile(r"maior parceiro|principal parceiro|primeiro parceiro|maior destino|principal destino|top export destination|largest trade partner|largest commercial partner|maior mercado|primeira parceira", re.I)
POLICY_PAT = re.compile(r"pol[ií]tica externa|diplom[aá]tica|diplomacia|parceria estrat[eé]gica|aproxima[cç][aã]o|prioridade|coopera[cç][aã]o|rela[cç][oõ]es bilaterais|Plano de A[cç][aã]o Conjunta|COSBAN", re.I)


def download(url: str, path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists() and path.stat().st_size > 0:
        return
    with urllib.request.urlopen(url) as r, open(path, "wb") as f:
        shutil.copyfileobj(r, f)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def extract_pdf_text(pdf: Path) -> None:
    out = pdf.with_suffix(".txt")
    if out.exists() and out.stat().st_size > 0:
        return
    if shutil.which("pdftotext") is None:
        print(f"pdftotext not found; skipping {pdf}", file=sys.stderr)
        return
    subprocess.run(["pdftotext", "-layout", str(pdf), str(out)], check=True)


def scan_falabr(years=range(2015, 2027)) -> None:
    falabr_raw = RAW / "falabr"
    hits, rank_hits, counts, zips = [], [], [], []
    for year in years:
        zp = falabr_raw / f"Arquivos_csv_{year}.zip"
        download(FALABR_URL.format(year=year), zp)
        zips.append({"file": str(zp.relative_to(ROOT)), "year": year, "sha256": sha256(zp), "size_bytes": zp.stat().st_size})
        total = org_hits = china_hits = rank_count = 0
        with zipfile.ZipFile(zp) as z:
            for name in z.namelist():
                bn = os.path.basename(name)
                if not (bn.endswith(".csv") and (f"_Pedidos_csv_{year}.csv" in bn or f"_Recursos_csv_{year}.csv" in bn)):
                    continue
                with z.open(name) as f:
                    text = io.TextIOWrapper(f, encoding="utf-16", errors="replace", newline="")
                    reader = csv.DictReader((line.replace("\x00", "") for line in text), delimiter=";")
                    for row in reader:
                        total += 1
                        org = " ".join(str(row.get(c, "")) for c in ["OrgaoDestinatario", "ÓrgãoDestinatario", "Orgao", "Instituicao"])
                        body = " ".join(str(v or "") for v in row.values())
                        if ORG_PAT.search(org):
                            org_hits += 1
                        if ORG_PAT.search(org) and CHINA_PAT.search(body):
                            china_hits += 1
                            rec = {k: row.get(k, "") for k in ["IdPedido", "ProtocoloPedido", "OrgaoDestinatario", "Situacao", "DataRegistro", "ResumoSolicitacao", "DetalhamentoSolicitacao", "DataResposta", "Resposta", "Decisao", "IdRecurso", "DescRecurso", "RespostaRecurso"]}
                            rec.update({"zip_year": year, "zip_member": name, "match_rank": bool(RANK_PAT.search(body)), "match_policy": bool(POLICY_PAT.search(body))})
                            hits.append(rec)
                            if RANK_PAT.search(body):
                                rank_count += 1
                                rank_hits.append(rec)
        counts.append({"year": year, "rows_scanned": total, "mre_rows": org_hits, "mre_china_rows": china_hits, "mre_china_rank_rows": rank_count})
    write_csv(REPORT / "falabr_mre_china_hits.csv", hits)
    write_csv(REPORT / "falabr_mre_china_rank_hits.csv", rank_hits)
    write_csv(REPORT / "falabr_scan_counts.csv", counts)
    write_csv(REPORT / "falabr_zip_checksums.csv", zips)


def write_csv(path: Path, rows: list[dict]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    keys = []
    for row in rows:
        for key in row:
            if key not in keys:
                keys.append(key)
    with open(path, "w", encoding="utf-8", newline="") as f:
        if not keys:
            return
        w = csv.DictWriter(f, fieldnames=keys)
        w.writeheader()
        w.writerows(rows)


def write_raw_checksums() -> None:
    rows = []
    for path in sorted(RAW.rglob("*")):
        if path.is_file():
            rows.append({"path": str(path.relative_to(ROOT)), "sha256": sha256(path), "size_bytes": path.stat().st_size})
    write_csv(REPORT / "raw_checksums.csv", rows)


def main() -> None:
    for name, url in MRE_SOURCES.items():
        path = RAW / "mre_resenhas" / name
        download(url, path)
        extract_pdf_text(path)
    for name, url in CAMARA.items():
        download(url, RAW / "camara" / name)
    scan_falabr()
    write_raw_checksums()


if __name__ == "__main__":
    main()
