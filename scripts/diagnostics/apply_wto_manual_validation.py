#!/usr/bin/env python3
"""Aplica as decisões da validação manual dos 40 PDFs do piloto OMC.

As decisões abaixo foram tomadas a partir da primeira página e, quando
necessário, do texto integral dos PDFs oficiais preservados em
data/raw/wto_coauthorship/2026-08-28/validation_pdfs/.  O script mantém a
amostra sorteada original intacta e produz um arquivo separado, auditável.

Convenções:
- CHN é a República Popular da China.
- HKG é Hong Kong, China, membro distinto da OMC.
- Grupos (por exemplo, African Group) não são expandidos para países.
- ``strict`` inclui propostas, papers, comunicações e contribuições negociais.
- Declarações/cartas, disputas e meras menções ficam fora do outcome estrito.
"""

from __future__ import annotations

import csv
from datetime import date
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
INPUT = ROOT / "data" / "processed" / "wto_coauthorship" / "wto_manual_validation_sample_40.csv"
OUTPUT = ROOT / "data" / "processed" / "wto_coauthorship" / "wto_manual_validation_results_40.csv"


def decision(
    classification: str,
    authors: str,
    evidence: str,
    notes: str = "",
    joint: bool = True,
    strict: bool = False,
) -> dict[str, str]:
    return {
        "manual_classification": classification,
        "manual_authors": authors,
        "manual_evidence": evidence,
        "manual_notes": notes,
        "manual_is_joint_document": "1" if joint else "0",
        "manual_in_strict_universe": "1" if strict else "0",
    }


# Chave: catalogue_id oficial do Documents Online.
DECISIONS = {
    "59922": decision(
        "NEGOTIATION_SUBMISSION", "BRA;HKG;MEX",
        "p.1: 'Communication from' e circulação a pedido das delegações listadas.",
        "Hong Kong, China não é CHN.", strict=True,
    ),
    "56812": decision(
        "NEGOTIATION_SUBMISSION", "BRA;HKG",
        "p.1: 'Communication from' e circulação a pedido das delegações listadas.",
        "Hong Kong, China não é CHN.", strict=True,
    ),
    "61763": decision(
        "NEGOTIATION_SUBMISSION", "BRA;HKG",
        "p.1: 'Communication from' e circulação a pedido das delegações listadas.",
        "Hong Kong, China não é CHN.", strict=True,
    ),
    "96936": decision(
        "FORMAL_JOINT_STATEMENT", "BRA;HKG;MEX;TUR",
        "p.1: 'Joint statement by' e lista explícita de delegações.",
        "Declaração conjunta, não proposta; Hong Kong, China não é CHN.",
    ),
    "1814": decision(
        "NEGOTIATION_SUBMISSION", "ARG;BRA;IND;IDN;MEX",
        "p.1: comunicação recebida das delegações explicitamente listadas.", strict=True,
    ),
    "44267": decision(
        "NEGOTIATION_SUBMISSION_REVISION", "BRA;IND",
        "p.1: 'Submission from' e circulação a pedido das delegações listadas.",
        "Revisão da família IP/C/W/429; não contar como nova família.", strict=True,
    ),
    "90807": decision(
        "FAMILY_ADDENDUM", "BRA;CHN;IND;MEX;ZAF;TUR",
        "p.1: addendum adiciona coautores à lista do documento WT/MIN(09)/W/1.",
        "A autoria vem da família indicada no título oficial; não é nova proposta.", strict=True,
    ),
    "69295": decision(
        "FAMILY_ADDENDUM", "BRA;CHN;IND;IDN;TUR",
        "p.1: lista explícita de coautores; addendum adiciona a Geórgia.",
        "African Group não foi expandido para ZAF; não é nova proposta.", strict=True,
    ),
    "2597": decision(
        "NEGOTIATION_SUBMISSION", "ARG;BRA;IND",
        "p.1: 'Proposal by MERCOSUR (Argentina, Brazil...)' e India.", strict=True,
    ),
    "54861": decision(
        "NEGOTIATION_SUBMISSION_REVISION", "BRA;CHN;IND",
        "p.1: lista explícita; nota diz que a revisão altera coautores, não a proposta.",
        "Não contar como nova família.", strict=True,
    ),
    "54183": decision(
        "NEGOTIATION_SUBMISSION", "ARG;BRA;IND;MEX",
        "p.1: comunicação das delegações explicitamente listadas.", strict=True,
    ),
    "87544": decision(
        "NEGOTIATION_SUBMISSION", "BRA;CHN;IND;IDN;ZAF",
        "p.1: 'Communication from' e lista explícita de proponentes.", strict=True,
    ),
    "57597": decision(
        "NEGOTIATION_SUBMISSION_REVISION", "BRA;CHN;IND",
        "p.1: lista explícita; nota diz que a revisão altera coautores.",
        "Não contar como nova família.", strict=True,
    ),
    "57669": decision(
        "NEGOTIATION_SUBMISSION", "BRA;HKG",
        "p.1: comunicação a pedido das delegações listadas.",
        "Hong Kong, China não é CHN.", strict=True,
    ),
    "113585": decision(
        "FORMAL_JOINT_STATEMENT", "BRA;HKG;MEX;TUR",
        "p.1: comunicação conjunta com lista explícita de delegações.",
        "Hong Kong, China não é CHN; declaração, não proposta.",
    ),
    "103248": decision(
        "NEGOTIATION_SUBMISSION", "BRA;IND;IDN",
        "p.1: comunicação recebida das delegações explicitamente listadas.", strict=True,
    ),
    "56932": decision(
        "NEGOTIATION_SUBMISSION", "BRA;HKG",
        "p.1: comunicação a pedido das delegações listadas.",
        "Hong Kong, China não é CHN.", strict=True,
    ),
    "89623": decision(
        "NEGOTIATION_SUBMISSION", "BRA;CHN;IND;ZAF",
        "p.1: 'Joint Proposal ... By Brazil, China, Cuba, India, Pakistan, South Africa'.",
        strict=True,
    ),
    "20804": decision(
        "NEGOTIATION_SUBMISSION", "BRA;IND;IDN",
        "p.1: 'Submission by' e lista explícita.",
        "African Group não foi expandido para ZAF.", strict=True,
    ),
    "107275": decision(
        "NEGOTIATION_SUBMISSION", "BRA;IND",
        "p.1: 'Communication from Brazil and India'.", strict=True,
    ),
    "5187": decision(
        "FORMAL_JOINT_LETTER", "BRA;IND",
        "p.1: carta assinada pelos ministros responsáveis pelo comércio dos países listados.",
        "Coordenação formal, mas fora de proposta/comunicação negocial estrita.",
    ),
    "11719": decision(
        "NEGOTIATION_SUBMISSION", "BRA;HKG",
        "p.1: 'Paper from' e lista explícita; responde questões sobre contribuição anterior.",
        "É paper conjunto; Hong Kong, China não é CHN.", strict=True,
    ),
    "503": decision(
        "DISPUTE_ACTION", "BRA;IND;IDN;MEX",
        "p.1: pedido conjunto de arbitragem no contencioso WT/DS217/234.",
        "Ação conjunta, mas fora do universo de propostas negociais.",
    ),
    "51259": decision(
        "NEGOTIATION_SUBMISSION", "BRA;HKG",
        "p.1: 'Paper from' e circulação a pedido das delegações listadas.",
        "Hong Kong, China não é CHN.", strict=True,
    ),
    "59833": decision(
        "NEGOTIATION_SUBMISSION", "BRA;IND",
        "p.1: 'Submission from' e circulação a pedido das delegações listadas.", strict=True,
    ),
    "70468": decision(
        "NEGOTIATION_SUBMISSION", "BRA;HKG",
        "p.1: 'Paper from'; texto registra circulação como documento formal.",
        "Hong Kong, China não é CHN.", strict=True,
    ),
    "82383": decision(
        "FORMAL_JOINT_STATEMENT", "BRA;CHN;IND;IDN;MEX;ZAF",
        "p.1: 'Statement of' e lista explícita de delegações.",
        "Declaração conjunta, não nova proposta; revisão da família TN/RL/W/214.",
    ),
    "103230": decision(
        "NEGOTIATION_SUBMISSION", "BRA;HKG;MEX;TUR",
        "p.1: 'Paper from'; o texto o chama de proposta.",
        "Hong Kong, China não é CHN.", strict=True,
    ),
    "47772": decision(
        "NEGOTIATION_SUBMISSION", "BRA;HKG",
        "p.1: 'Paper from'; texto registra circulação como documento formal.",
        "Hong Kong, China não é CHN.", strict=True,
    ),
    "14032": decision(
        "NEGOTIATION_SUBMISSION", "BRA;HKG",
        "p.1: 'Paper from'; o texto o chama de proposta.",
        "Hong Kong, China não é CHN.", strict=True,
    ),
    "88943": decision(
        "RELATIONAL_NOT_COAUTHOR", "IND",
        "p.1: pedido de consultas apresentado pela Índia contra medidas do Brasil.",
        "Brasil é parte demandada, não coautor.", joint=False,
    ),
    "14756": decision(
        "NEGOTIATION_SUBMISSION", "BRA;HKG;TUR",
        "p.1: 'Paper by' e lista explícita de delegações.",
        "Hong Kong, China não é CHN.", strict=True,
    ),
    "71824": decision(
        "NEGOTIATION_SUBMISSION", "ARG;BRA;IND",
        "p.1: comunicação ao grupo negociador 'from Argentina, Brazil and India'.",
        strict=True,
    ),
    "95091": decision(
        "RELATIONAL_NOT_COAUTHOR", "",
        "p.1: perguntas da Austrália dirigidas a propostas distintas de Brasil e Índia.",
        "Nem Brasil nem Índia é autor deste documento.", joint=False,
    ),
    "43525": decision(
        "RELATIONAL_NOT_COAUTHOR", "HKG",
        "p.1: objeção de Hong Kong, China à certificação da lista do Brasil.",
        "Brasil é objeto, não coautor; HKG não é CHN.", joint=False,
    ),
    "71995": decision(
        "NEGOTIATION_SUBMISSION", "BRA;IND",
        "p.1: 'Submission from Brazil and India' e circulação a pedido de ambas as delegações.",
        strict=True,
    ),
    "42718": decision(
        "NEGOTIATION_SUBMISSION", "BRA;HKG;TUR",
        "p.1: 'Paper from' e lista explícita de missões autoras.",
        "Hong Kong, China não é CHN.", strict=True,
    ),
    "95090": decision(
        "RELATIONAL_NOT_COAUTHOR", "",
        "p.1: perguntas do Canadá dirigidas separadamente ao Brasil e à Índia.",
        "Brasil e Índia são alvos, não autores.", joint=False,
    ),
    "96450": decision(
        "RELATIONAL_NOT_COAUTHOR", "",
        "p.1: perguntas dos Estados Unidos dirigidas ao Brasil e à Índia.",
        "Brasil e Índia são alvos, não autores.", joint=False,
    ),
    "1355": decision(
        "NEGOTIATION_SUBMISSION_REVISION", "ARG;BRA;IND",
        "p.1: comunicação circulada a pedido das delegações explicitamente listadas.",
        "Non-paper oficial/restrito; revisão da família JOB(04)/52.", strict=True,
    ),
}


def main() -> None:
    with INPUT.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))

    sample_ids = {row["catalogue_id"] for row in rows}
    if sample_ids != set(DECISIONS):
        missing = sorted(sample_ids - set(DECISIONS))
        extra = sorted(set(DECISIONS) - sample_ids)
        raise RuntimeError(f"Decisões não coincidem com a amostra: missing={missing}; extra={extra}")

    reviewed_at = date.today().isoformat()
    output_rows = []
    for row in rows:
        row.update(DECISIONS[row["catalogue_id"]])
        row["reviewed_at"] = reviewed_at
        output_rows.append(row)

    fields = list(rows[0].keys())
    for field in ("manual_is_joint_document", "manual_in_strict_universe"):
        if field not in fields:
            fields.append(field)

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    with OUTPUT.open("w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=fields, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(output_rows)

    n_joint = sum(row["manual_is_joint_document"] == "1" for row in output_rows)
    n_strict = sum(row["manual_in_strict_universe"] == "1" for row in output_rows)
    n_relational = sum(row["manual_classification"] == "RELATIONAL_NOT_COAUTHOR" for row in output_rows)
    print({"rows": len(output_rows), "joint": n_joint, "strict": n_strict, "relational_not_coauthor": n_relational})


if __name__ == "__main__":
    main()
