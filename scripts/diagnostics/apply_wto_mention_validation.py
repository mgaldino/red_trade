#!/usr/bin/env python3
"""Registra a validação manual de 20 menções/falsos positivos OMC."""

from __future__ import annotations

import csv
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INPUT = ROOT / "data" / "processed" / "wto_coauthorship" / "wto_mention_validation_sample_20.csv"
OUTPUT = ROOT / "data" / "processed" / "wto_coauthorship" / "wto_mention_validation_results_20.csv"


def d(classification: str, authors: str, evidence: str, notes: str) -> dict[str, str]:
    return {
        "manual_classification": classification,
        "manual_authors": authors,
        "manual_evidence": evidence,
        "manual_notes": notes,
        "manual_is_joint_document": "0",
        "manual_in_strict_universe": "0",
    }


DECISIONS = {
    "128049": d("BILATERAL_DISPUTE_NOT_COAUTHOR", "BRA", "p.1: pedido de consultas apresentado pelo Brasil contra a Indonésia.", "A Indonésia é demandada, não coautora."),
    "125627": d("BILATERAL_DISPUTE_NOT_COAUTHOR", "BRA", "p.1: comunicação do Brasil pedindo ingresso em consultas relativas à Indonésia.", "A Indonésia é parte do caso, não coautora."),
    "121883": d("BILATERAL_DISPUTE_NOT_COAUTHOR", "ARG", "p.1: comunicação da Argentina para ingressar em consultas sobre medidas do Brasil.", "Brasil é objeto, não coautor."),
    "96991": d("BILATERAL_DISPUTE_NOT_COAUTHOR", "BRA", "p.1: comunicação do Brasil à China e ao México para ingressar em consultas.", "China e México são destinatários/partes, não coautores."),
    "42271": d("BILATERAL_DISPUTE_NOT_COAUTHOR", "BRA", "p.1: pedido de consultas do Brasil contra a África do Sul.", "África do Sul é demandada, não coautora."),
    "80918": d("THIRD_PARTY_RESPONSE_NOT_COAUTHOR", "", "p.1: relatório/resposta do Secretariado às medidas de declaração anterior.", "Brasil, China, Índia e África do Sul apenas aparecem como autores da declaração respondida."),
    "89561": d("BILATERAL_QUESTION_NOT_COAUTHOR", "CHN", "p.1: perguntas da China ao Brasil, circuladas a pedido da China.", "Brasil é destinatário, não coautor."),
    "74369": d("BILATERAL_REPLY_NOT_COAUTHOR", "BRA", "p.1: respostas do Brasil a perguntas da China, circuladas a pedido do Brasil.", "China é autora das perguntas anteriores, não deste documento."),
    "91865": d("BILATERAL_QUESTION_NOT_COAUTHOR", "MEX", "p.1: perguntas do México ao Brasil, circuladas a pedido do México.", "Brasil é destinatário, não coautor."),
    "94881": d("BILATERAL_QUESTION_NOT_COAUTHOR", "CHN", "p.1: perguntas da China ao Brasil, circuladas a pedido da China.", "Brasil é destinatário, não coautor."),
    "88674": d("BILATERAL_DISPUTE_NOT_COAUTHOR", "ARG", "p.1: pedido de painel apresentado pela Argentina contra o Brasil.", "Brasil é demandado, não coautor."),
    "62444": d("BILATERAL_DISPUTE_NOT_COAUTHOR", "ARG", "p.1: pedido de consultas da Argentina ao Brasil.", "Brasil é demandado, não coautor."),
    "57238": d("BILATERAL_DISPUTE_NOT_COAUTHOR", "ARG", "p.1: comunicação da Argentina para ingressar em consultas sobre medidas do Brasil.", "Brasil é objeto da disputa, não coautor."),
    "53721": d("THIRD_COUNTRY_QUESTIONS_NOT_COAUTHOR", "", "p.1: perguntas de seguimento dos Estados Unidos ao Brasil e à Índia.", "Brasil e Índia são destinatários de perguntas sobre propostas distintas."),
    "16369": d("THIRD_COUNTRY_QUESTIONS_NOT_COAUTHOR", "", "p.1: perguntas das Comunidades Europeias ao Brasil e à Índia.", "Brasil e Índia são destinatários, não coautores."),
    "96450": d("THIRD_COUNTRY_QUESTIONS_NOT_COAUTHOR", "", "p.1: perguntas dos Estados Unidos ao Brasil e à Índia.", "Brasil e Índia são destinatários, não coautores."),
    "95090": d("THIRD_COUNTRY_QUESTIONS_NOT_COAUTHOR", "", "p.1: perguntas do Canadá ao Brasil e à Índia.", "Brasil e Índia são destinatários, não coautores."),
    "95091": d("THIRD_COUNTRY_QUESTIONS_NOT_COAUTHOR", "", "p.1: perguntas da Austrália ao Brasil e à Índia.", "Brasil e Índia são destinatários, não coautores."),
    "43525": d("BILATERAL_OBJECTION_NOT_COAUTHOR", "HKG", "p.1: objeção de Hong Kong, China à certificação da lista do Brasil.", "Brasil é objeto; HKG não é CHN."),
    "88943": d("BILATERAL_DISPUTE_NOT_COAUTHOR", "IND", "p.1: pedido de consultas da Índia contra direitos antidumping do Brasil.", "Brasil é demandado, não coautor."),
}


def main() -> None:
    with INPUT.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    ids = {row["catalogue_id"] for row in rows}
    if ids != set(DECISIONS):
        raise RuntimeError(f"Amostra e decisões divergem: {sorted(ids ^ set(DECISIONS))}")

    fields = list(rows[0].keys())
    for field in ("manual_is_joint_document", "manual_in_strict_universe"):
        if field not in fields:
            fields.append(field)
    for row in rows:
        row.update(DECISIONS[row["catalogue_id"]])
        row["reviewed_at"] = date.today().isoformat()

    with OUTPUT.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    print({"rows": len(rows), "validated_false_positives": len(rows)})


if __name__ == "__main__":
    main()
