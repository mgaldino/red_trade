#!/usr/bin/env python3
"""Audit the anonymous CPSR main manuscript with Pangram 4.

The submitted text is extracted from the already-rendered anonymous PDF.  API
responses are saved verbatim; a task receipt prevents an accidental second
billed submission when polling is resumed.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import requests


ROOT = Path(__file__).resolve().parents[2]
PDF = ROOT / "output/submission/cpsr/final/CPSR_Manuscript_Anonymous.pdf"
OUT = ROOT / "quality_reports/pangram/2026-09-22_cpsr_anonymous"
INPUT = OUT / "submitted_text.txt"
RECEIPT = OUT / "task_receipt.json"
RAW = OUT / "pangram_response_raw.json"
SECTION_RECEIPT = OUT / "section_bulk_receipt.json"
SECTION_RAW = OUT / "section_bulk_response_raw.json"
REPORT = OUT / "pangram_full_report.md"
BASE = "https://text.external-api.pangram.com"
MODEL = "pangram-4"
HEADINGS = (
    "Abstract",
    "Introduction",
    "Theory and Hypotheses",
    "Data and Design",
    "Brazil SDiD Evidence",
    "Brazilian Media Salience",
    "Cross-Country Evidence Beyond Brazil",
    "Conclusion",
)
LIGATURES = {
    "\x1c": "fi",
    "\x1b": "ff",
    "\x1e": "ffi",
    "\x1d": "fl",
    "\x10": '“',
    "\x11": '”',
    "\x15": "–",
    "\x16": "—",
    "\x14": "[",
    "\x1a": "[",
    "\x01": "]",
}


def utc_now() -> str:
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def save_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def section_spans(text: str) -> list[tuple[str, int, int]]:
    found = []
    for name in HEADINGS:
        prefix = "" if name == "Abstract" else r"(?:[1-7]\s+)?"
        match = re.search(r"(?m)^\s*" + prefix + re.escape(name) + r"\s*$", text)
        if match is None:
            raise ValueError(f"Heading not found in analyzed text: {name}")
        found.append((name, match.start()))
    if [start for _, start in found] != sorted(start for _, start in found):
        raise ValueError("Major headings occur out of order")
    return [(name, start, found[i + 1][1] if i + 1 < len(found) else len(text))
            for i, (name, start) in enumerate(found)]


def prepare() -> None:
    if not PDF.is_file():
        raise FileNotFoundError(PDF)
    if RECEIPT.exists() or RAW.exists():
        if not INPUT.exists():
            raise RuntimeError("An existing API task has no saved input text")
        print(f"Existing submission retained: {INPUT}")
        return
    extracted = subprocess.check_output(["pdftotext", str(PDF), "-"], text=True)
    if "Statements and Declarations" not in extracted:
        raise ValueError("Expected end-of-body heading not found")
    body = extracted.split("Statements and Declarations", 1)[0]
    if "Abstract" not in body:
        raise ValueError("Abstract missing from PDF extraction")
    if re.search(r"(?im)^\s*Appendix\s*$", body):
        raise ValueError("Appendix detected in main-manuscript PDF")
    if re.search(r"(?i)Manoel Galdino|mgaldino@|University of S[aã]o Paulo", body):
        raise ValueError("Author identifying text detected in PDF extraction")
    for bad, good in LIGATURES.items():
        body = body.replace(bad, good)
    # Remove page-number/form-feed combinations, preserving the actual prose.
    body = re.sub(r"(?m)^\s*\d+\s*\f", "\n", body)
    body = body.replace("\f", "\n")
    body = re.sub(r"(?m)^\s*\d+\s*$", "", body)
    body = re.sub(r"(?m)^\s*Keywords:.*(?:\n(?!\n)[^\n]+)*", "", body, count=1)
    body = body[body.index("Abstract"):]
    # Preserve hard paragraph breaks; unwrap PDF lines inside paragraphs.
    paragraphs = [re.sub(r"\s*\n\s*", " ", block).strip()
                  for block in re.split(r"\n\s*\n", body)]
    text = "\n\n".join(block for block in paragraphs if block) + "\n"
    # Heading lines must remain identifiable after unwrapping.
    for name in HEADINGS:
        label = name if name == "Abstract" else r"[1-7]\s+" + re.escape(name)
        text = re.sub(r"(?m)(^|\n\n)(" + label + r")\s+", r"\1\2\n\n", text)
    section_spans(text)
    if any(ord(char) < 32 and char not in "\n\t\r" for char in text):
        raise ValueError("Unresolved PDF extraction control characters")
    OUT.mkdir(parents=True, exist_ok=True)
    INPUT.write_text(text, encoding="utf-8")
    print(f"Prepared {len(text.split()):,} words, {len(text):,} characters: {INPUT}")


def api_session() -> requests.Session:
    key = os.environ.get("PANGRAM_API_KEY")
    if not key:
        raise RuntimeError("PANGRAM_API_KEY is not set")
    session = requests.Session()
    session.headers.update({"x-api-key": key})
    return session


def submit() -> None:
    if RAW.exists() or RECEIPT.exists():
        print("Existing task/result found; skipping billed submission")
        return
    if not INPUT.exists():
        prepare()
    session = api_session()
    catalog = session.get(f"{BASE}/models", timeout=30)
    catalog.raise_for_status()
    models = catalog.json()["models"]
    if MODEL not in models:
        raise RuntimeError(f"{MODEL} is unavailable; enabled models: {models}")
    response = session.post(
        f"{BASE}/task",
        json={"text": INPUT.read_text(encoding="utf-8"), "model": MODEL,
              "public_dashboard_link": False},
        timeout=120,
    )
    if not response.ok:
        raise RuntimeError(f"Pangram submission HTTP {response.status_code}: {response.text[:1200]}")
    payload = response.json()
    if not payload.get("task_id"):
        raise RuntimeError(f"Pangram returned no task_id: {payload}")
    save_json(RECEIPT, {
        "submitted_at_utc": utc_now(), "task_id": payload["task_id"],
        "model": MODEL, "source_pdf": str(PDF), "source_pdf_sha256": sha256(PDF),
        "submitted_text": str(INPUT), "submitted_text_sha256": sha256(INPUT),
        "submitted_words": len(INPUT.read_text(encoding="utf-8").split()),
        "submitted_characters": len(INPUT.read_text(encoding="utf-8")),
        "scope": "Abstract through Conclusion; no appendix, declarations, or references",
        "api_submission_response": payload,
    })
    print(f"Submitted task {payload['task_id']}; receipt saved: {RECEIPT}")


def poll(max_seconds: int = 540) -> None:
    if RAW.exists():
        print(f"Existing complete response retained: {RAW}")
        return
    if not RECEIPT.exists():
        raise RuntimeError("No task receipt; run --submit first")
    task_id = json.loads(RECEIPT.read_text(encoding="utf-8"))["task_id"]
    session = api_session()
    deadline = time.monotonic() + max_seconds
    while time.monotonic() < deadline:
        response = session.get(f"{BASE}/task/{task_id}", timeout=60)
        response.raise_for_status()
        payload = response.json()
        stage = payload.get("stage")
        if stage == "STAGE_SUCCESS":
            save_json(RAW, payload)
            print(f"Saved complete Pangram response: {RAW}")
            return
        if stage == "STAGE_FAILED":
            save_json(OUT / "pangram_failed_response.json", payload)
            raise RuntimeError(f"Pangram task failed: {payload.get('headline')}")
        print(f"Pangram stage: {stage}", flush=True)
        time.sleep(5)
    raise TimeoutError(f"Pangram task still running: {task_id}")


def submit_sections() -> None:
    if SECTION_RECEIPT.exists() or SECTION_RAW.exists():
        print("Existing section task/result found; skipping billed submission")
        return
    if not INPUT.exists():
        prepare()
    text = INPUT.read_text(encoding="utf-8")
    items = [{"id": name, "text": text[start:end]}
             for name, start, end in section_spans(text)]
    session = api_session()
    response = session.post(f"{BASE}/bulk", json={"items": items, "model": MODEL}, timeout=120)
    if not response.ok:
        raise RuntimeError(f"Pangram bulk submission HTTP {response.status_code}: {response.text[:1200]}")
    payload = response.json()
    if not payload.get("bulk_id"):
        raise RuntimeError(f"Pangram returned no bulk_id: {payload}")
    save_json(SECTION_RECEIPT, {
        "submitted_at_utc": utc_now(), "bulk_id": payload["bulk_id"],
        "model": MODEL, "submitted_text_sha256": sha256(INPUT),
        "section_names": [item["id"] for item in items],
        "section_words": {item["id"]: len(item["text"].split()) for item in items},
        "api_submission_response": payload,
    })
    print(f"Submitted section bulk job {payload['bulk_id']}; receipt saved: {SECTION_RECEIPT}")


def poll_sections(max_seconds: int = 540) -> None:
    if SECTION_RAW.exists():
        print(f"Existing complete section results retained: {SECTION_RAW}")
        return
    if not SECTION_RECEIPT.exists():
        raise RuntimeError("No section bulk receipt; run --submit-sections first")
    receipt = json.loads(SECTION_RECEIPT.read_text(encoding="utf-8"))
    bulk_id = receipt["bulk_id"]
    session = api_session()
    deadline = time.monotonic() + max_seconds
    while time.monotonic() < deadline:
        response = session.get(f"{BASE}/bulk/{bulk_id}", timeout=60)
        response.raise_for_status()
        payload = response.json()
        status = payload.get("status")
        if status in ("succeeded", "failed", "partial"):
            result = session.get(f"{BASE}/bulk/{bulk_id}/results",
                                 params={"offset": 0, "limit": 100}, timeout=120)
            result.raise_for_status()
            data = result.json()
            save_json(SECTION_RAW, {"status": payload, "results": data})
            print(f"Saved complete section bulk response: {SECTION_RAW}; status={status}")
            return
        print(f"Pangram section job: {status}", flush=True)
        time.sleep(5)
    raise TimeoutError(f"Pangram section job still running: {bulk_id}")


def report() -> None:
    if not RAW.exists() or not RECEIPT.exists():
        raise RuntimeError("Completed raw response and task receipt required")
    data = json.loads(RAW.read_text(encoding="utf-8"))
    receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
    if data.get("stage") != "STAGE_SUCCESS":
        raise ValueError("Response is not successful")
    if data.get("version", "").split(".")[0] != "4":
        raise ValueError(f"Unexpected Pangram version: {data.get('version')}")
    returned = data.get("text", "")
    spans = section_spans(returned)
    windows = data.get("windows", [])
    if not windows:
        raise ValueError("Pangram returned no segment windows")
    for window in windows:
        lo, hi = window["start_index"], window["end_index"]
        if returned[lo:hi] != window["text"]:
            raise ValueError(f"Window offsets do not match returned text: {lo}-{hi}")
    if abs(sum(data[k] for k in ("fraction_ai", "fraction_ai_assisted", "fraction_human")) - 1) > 0.002:
        raise ValueError("Document fractions do not sum to one")
    lines = [
        "# Pangram 4 — manuscrito anônimo CPSR, corpo principal",
        "",
        f"Data da submissão (UTC): {receipt['submitted_at_utc']}",
        f"PDF de origem: `{PDF.relative_to(ROOT)}`",
        f"SHA-256 do PDF: `{receipt['source_pdf_sha256']}`",
        f"Texto efetivamente enviado: [submitted_text.txt](submitted_text.txt)",
        f"SHA-256 do texto enviado: `{receipt['submitted_text_sha256']}`",
        f"Resposta completa da API: [pangram_response_raw.json](pangram_response_raw.json); SHA-256: `{sha256(RAW)}`",
        f"Respostas completas das chamadas por seção: [section_bulk_response_raw.json](section_bulk_response_raw.json); SHA-256: `{sha256(SECTION_RAW)}`" if SECTION_RAW.exists() else "Chamadas por seção: indisponíveis.",
        f"Task ID: `{receipt['task_id']}`; modelo solicitado: `{MODEL}`; versão retornada: `{data['version']}`",
        f"Escopo: {receipt['scope']}. O texto foi extraído do PDF anônimo, com correção dos caracteres de ligatura e retirada de numeração de página e palavras-chave.",
        f"Tamanho enviado: {receipt['submitted_words']:,} palavras, {receipt['submitted_characters']:,} caracteres.",
        "",
        "## Resultado global, como devolvido pelo Pangram",
        "",
        f"- Headline: **{data.get('headline')}**",
        f"- Prediction: {data.get('prediction')}",
        f"- Prediction short: `{data.get('prediction_short')}`",
        f"- `fraction_ai`: **{data['fraction_ai']:.4f}**",
        f"- `fraction_ai_assisted`: **{data['fraction_ai_assisted']:.4f}**",
        f"- `fraction_human`: **{data['fraction_human']:.4f}**",
        f"- Segmentos AI / assisted / human: {data.get('num_ai_segments')} / {data.get('num_ai_assisted_segments')} / {data.get('num_human_segments')}",
        "",
        "As três frações são proporções de caracteres classificados em cada categoria, não probabilidades de autoria do documento. `ai_assistance_score` é uma medida contínua de envolvimento de IA em cada trecho, não a probabilidade do rótulo exibido.",
        "",
        "## Por seção (cálculo derivado dos segmentos da resposta global)",
        "",
        "As fronteiras das seções foram localizadas no texto devolvido pela API. Quando um segmento cruza uma fronteira, seu peso é dividido pela sobreposição em caracteres. Os números por seção não são chamadas independentes ao Pangram.",
        "",
        "| Seção | Caracteres | IA | Assistida | Humana | Score médio dos segmentos | Segmentos com sobreposição |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    label_class = {"AI-Generated": "ai", "AI-Assisted": "assisted", "Human Written": "human"}
    for name, start, end in spans:
        weights = {"ai": 0, "assisted": 0, "human": 0}
        score_sum = 0.0
        weighted = 0
        segments = 0
        for window in windows:
            overlap = max(0, min(end, window["end_index"]) - max(start, window["start_index"]))
            if overlap:
                segments += 1
                weighted += overlap
                weights[label_class[window["label"]]] += overlap
                score_sum += overlap * window["ai_assistance_score"]
        if not weighted:
            raise ValueError(f"No windows overlap section {name}")
        lines.append(f"| {name} | {end-start:,} | {weights['ai']/weighted:.1%} | "
                     f"{weights['assisted']/weighted:.1%} | {weights['human']/weighted:.1%} | "
                     f"{score_sum/weighted:.3f} | {segments} |")
    if SECTION_RAW.exists():
        section_data = json.loads(SECTION_RAW.read_text(encoding="utf-8"))
        items = section_data["results"].get("items", [])
        expected = [name for name, _, _ in spans]
        by_id = {item["id"]: item for item in items}
        if set(by_id) != set(expected) or section_data["results"].get("failed_items"):
            raise ValueError("Section bulk results are incomplete or have failures")
        lines += [
            "",
            "## Scores nativos por seção (chamadas independentes)",
            "",
            "Cada seção foi submetida separadamente em uma tarefa bulk. Estas frações e classificações vêm diretamente do Pangram; por isso podem diferir da tabela derivada das janelas da chamada global. O JSON de bulk preserva integralmente a resposta de cada seção, inclusive todos os seus segmentos.",
            "",
            "| Seção | Versão | Headline | Prediction short | IA | Assistida | Humana | Segmentos |",
            "|---|---|---|---|---:|---:|---:|---:|",
        ]
        for name in expected:
            result = by_id[name].get("result")
            if not result or result.get("version", "").split(".")[0] != "4":
                raise ValueError(f"Missing successful Pangram 4 result for {name}")
            lines.append(f"| {name} | {result['version']} | {result.get('headline')} | "
                         f"{result.get('prediction_short')} | {result['fraction_ai']:.1%} | "
                         f"{result['fraction_ai_assisted']:.1%} | "
                         f"{result['fraction_human']:.1%} | {len(result.get('windows', []))} |")
        lines += ["", "### Explicações textuais devolvidas por seção", ""]
        for name in expected:
            lines += [f"- **{name}:** {by_id[name]['result'].get('prediction')}"]
    lines += [
        "",
        "## Todos os segmentos retornados pelo Pangram",
        "",
        "Abaixo estão todos os campos de cada `window`, incluindo o texto integral, sem truncamento. O JSON preserva ainda os campos globais e o texto completo retornado pela API.",
        "",
    ]
    for idx, window in enumerate(windows, 1):
        lo, hi = window["start_index"], window["end_index"]
        touched = [name for name, start, end in spans if min(end, hi) > max(start, lo)]
        lines += [
            f"### Segmento {idx} — {', '.join(touched)}",
            "",
            f"- Rótulo: **{window['label']}**; `ai_assistance_score`: **{window['ai_assistance_score']:.4f}**; confiança: {window['confidence']}.",
            f"- Índices: [{lo}, {hi}); palavras: {window.get('word_count')}; tokens: {window.get('token_length')}.",
            f"- `is_humanized`: {window.get('is_humanized')}; `humanizer_score`: {window.get('humanizer_score')}.",
            "",
            "```text",
            window["text"].rstrip(),
            "```",
            "",
        ]
    lines += [
        "## Limites de interpretação",
        "",
        "O modelo avalia padrões do texto, não conhece o processo real de escrita. Resultados locais podem ser afetados por fórmulas, legendas, tabelas, citações e artefatos remanescentes da extração de PDF. A análise não fornece um score nativo por parágrafo; a resolução máxima da resposta são os segmentos acima. O próprio modelo recomenda texto simples ou DOCX quando disponível e indica extensão mínima de cerca de duas frases por segmento.",
        "",
        "## Fontes da API e do modelo",
        "",
        "- https://docs.pangram.com/api-reference/ai-detection",
        "- https://www.pangram.com/research/model-card/pangram-4",
        "",
    ]
    REPORT.write_text("\n".join(lines), encoding="utf-8")
    print(f"Report saved: {REPORT}; {len(windows)} full segments")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("prepare", "submit", "poll", "submit-sections",
                                           "poll-sections", "report", "run"))
    args = parser.parse_args()
    if args.action in ("prepare", "run"):
        prepare()
    if args.action in ("submit", "run"):
        submit()
    if args.action in ("poll", "run"):
        poll()
    if args.action in ("submit-sections", "run"):
        submit_sections()
    if args.action in ("poll-sections", "run"):
        poll_sections()
    if args.action in ("report", "run"):
        report()


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        raise SystemExit(1)
