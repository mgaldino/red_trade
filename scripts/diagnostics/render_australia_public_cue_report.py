#!/usr/bin/env python3
"""Render the Australia 2006-2009 public-cue source report to PDF."""

from __future__ import annotations

import csv
import hashlib
from pathlib import Path
from xml.sax.saxutils import escape

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import (
    KeepTogether,
    PageBreak,
    Paragraph,
    SimpleDocTemplate,
    Spacer,
    Table,
    TableStyle,
)


ROOT = Path(__file__).resolve().parents[2]
CSV_PATH = (
    ROOT
    / "data/processed/status_cue_salience/"
    / "australia_public_cue_media_2006_2009.csv"
)
OUTPUT = ROOT / "output/pdf/australia_public_cue_2006_2009.pdf"

NAVY = colors.HexColor("#17365D")
BLUE = colors.HexColor("#DCE6F1")
PALE = colors.HexColor("#F4F7FA")
INK = colors.HexColor("#202A35")
MUTED = colors.HexColor("#5A6570")
GREEN = colors.HexColor("#E2F0D9")
RED = colors.HexColor("#FCE4D6")


def read_rows() -> list[dict[str, str]]:
    with CSV_PATH.open(encoding="utf-8", newline="") as handle:
        rows = list(csv.DictReader(handle))
    if len(rows) != 8:
        raise ValueError(f"Expected eight source rows, found {len(rows)}")
    return rows


def summarize(rows: list[dict[str, str]]) -> dict[str, str | int]:
    positive = [row for row in rows if row["positive_broad_cue"] == "true"]
    strict = [row for row in rows if row["strict_m2_goods_only"] == "true"]
    earliest = min(row["publication_date"] for row in positive)
    summary = {
        "documents": len(rows),
        "positive": len(positive),
        "strict": len(strict),
        "earliest": earliest,
    }
    expected = {"documents": 8, "positive": 5, "strict": 0, "earliest": "2007-05-04"}
    if summary != expected:
        raise ValueError(f"Unexpected report summary: {summary} != {expected}")
    return summary


def page_decor(canvas, document) -> None:
    canvas.saveState()
    width, height = A4
    canvas.setStrokeColor(colors.HexColor("#B8C4D1"))
    canvas.setLineWidth(0.45)
    canvas.line(document.leftMargin, height - 16 * mm, width - document.rightMargin, height - 16 * mm)
    canvas.setFont("Helvetica", 8)
    canvas.setFillColor(MUTED)
    canvas.drawString(document.leftMargin, height - 12.5 * mm, "Australia: public cue comercial, 2006-2009")
    canvas.drawRightString(width - document.rightMargin, 11 * mm, f"Página {document.page}")
    canvas.setFont("Helvetica", 7.5)
    canvas.drawString(document.leftMargin, 11 * mm, "Busca e verificação: 22 de setembro de 2026")
    canvas.restoreState()


def linked_label(row: dict[str, str]) -> str:
    short = {
        "ABC News": "ABC",
        "Reserve Bank of Australia": "RBA",
        "Australian Department of Foreign Affairs and Trade": "DFAT",
        "Australian Financial Review": "AFR",
    }[row["source_name"]]
    date = row["publication_date"]
    return f'<link href="{escape(row["url"])}" color="#17365D"><u>{short}, {escape(date)}</u></link>'


def metric_label(row: dict[str, str]) -> str:
    labels = {
        "generic_trade_partner": "parceiro comercial; denominador não especificado",
        "export_destination": "destino de exportações de bens e serviços",
        "two_way_trade": "comércio bilateral: importações + exportações",
    }
    return labels[row["metric_scope"]]


def access_label(row: dict[str, str]) -> str:
    if row["access_status"] == "ok":
        return "raw novo, SHA-256"
    if row["access_status"] == "existing_raw_verified":
        return "raw anterior, SHA-256"
    return "navegador; coleta parou em robots"


def build_pdf(rows: list[dict[str, str]]) -> None:
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    summary = summarize(rows)
    day = str(summary["earliest"])[8:10]
    month = str(summary["earliest"])[5:7]
    year = str(summary["earliest"])[0:4]
    earliest_br = f"{day}/{month}/{year}"
    csv_hash = hashlib.sha256(CSV_PATH.read_bytes()).hexdigest()
    styles = getSampleStyleSheet()
    title = ParagraphStyle(
        "TitleCustom",
        parent=styles["Title"],
        fontName="Helvetica-Bold",
        fontSize=22,
        leading=27,
        textColor=NAVY,
        alignment=TA_LEFT,
        spaceAfter=9 * mm,
    )
    subtitle = ParagraphStyle(
        "Subtitle",
        parent=styles["Normal"],
        fontName="Helvetica",
        fontSize=10.5,
        leading=15,
        textColor=MUTED,
        spaceAfter=6 * mm,
    )
    heading = ParagraphStyle(
        "HeadingCustom",
        parent=styles["Heading2"],
        fontName="Helvetica-Bold",
        fontSize=14,
        leading=17,
        textColor=NAVY,
        spaceBefore=5 * mm,
        spaceAfter=3 * mm,
        keepWithNext=True,
    )
    body = ParagraphStyle(
        "BodyCustom",
        parent=styles["BodyText"],
        fontName="Helvetica",
        fontSize=9.5,
        leading=14,
        textColor=INK,
        alignment=TA_LEFT,
        spaceAfter=3.2 * mm,
    )
    small = ParagraphStyle(
        "Small",
        parent=body,
        fontSize=7.4,
        leading=9.2,
        spaceAfter=0,
    )
    small_center = ParagraphStyle(
        "SmallCenter",
        parent=small,
        alignment=TA_CENTER,
    )
    table_head = ParagraphStyle(
        "TableHead",
        parent=small_center,
        fontName="Helvetica-Bold",
        textColor=colors.white,
    )
    caption = ParagraphStyle(
        "Caption",
        parent=body,
        fontName="Helvetica-Oblique",
        fontSize=8.3,
        leading=11,
        textColor=MUTED,
        spaceAfter=2.5 * mm,
    )
    code = ParagraphStyle(
        "Code",
        parent=body,
        fontName="Courier",
        fontSize=7.4,
        leading=10,
        leftIndent=4 * mm,
        rightIndent=4 * mm,
        borderColor=colors.HexColor("#C6D2DE"),
        borderWidth=0.5,
        borderPadding=6,
        backColor=PALE,
    )

    document = SimpleDocTemplate(
        str(OUTPUT),
        pagesize=A4,
        rightMargin=18 * mm,
        leftMargin=18 * mm,
        topMargin=22 * mm,
        bottomMargin=19 * mm,
        title="Australia: public cue comercial, 2006-2009",
        author="RDD Trade research audit",
        subject="Cronologia e escopo da pista pública comercial da Austrália",
    )

    story = [
        Spacer(1, 8 * mm),
        Paragraph("Public cue comercial da Austrália, 2006-2009", title),
        Paragraph(
            "Relatório de busca documental e proveniência. Unidade: documento jornalístico nacional ou publicação oficial.",
            subtitle,
        ),
    ]

    summary_data = [
        [
            Paragraph("Primeira pista positiva", table_head),
            Paragraph("Documentos", table_head),
            Paragraph("Pistas amplas positivas", table_head),
            Paragraph("Fontes goods-only estritas", table_head),
        ],
        [
            Paragraph(earliest_br, small_center),
            Paragraph(str(summary["documents"]), small_center),
            Paragraph(str(summary["positive"]), small_center),
            Paragraph(str(summary["strict"]), small_center),
        ],
    ]
    summary_table = Table(summary_data, colWidths=[42 * mm, 35 * mm, 47 * mm, 47 * mm])
    summary_table.setStyle(
        TableStyle(
            [
                ("BACKGROUND", (0, 0), (-1, 0), NAVY),
                ("BACKGROUND", (0, 1), (0, 1), GREEN),
                ("BACKGROUND", (1, 1), (-1, 1), PALE),
                ("GRID", (0, 0), (-1, -1), 0.45, colors.HexColor("#AAB7C4")),
                ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
                ("TOPPADDING", (0, 0), (-1, -1), 6),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
            ]
        )
    )
    story.extend([summary_table, Spacer(1, 6 * mm)])

    story.extend(
        [
            Paragraph("Resultado principal", heading),
            Paragraph(
                f"A primeira pista pública nacional positiva diretamente recuperada é de <b>{earliest_br}</b>. A ABC informou que a China havia superado o Japão como maior parceiro comercial da Austrália, com base na soma de importações e exportações nos doze meses até março. Outra matéria da ABC repetiu a classificação em setembro. As fontes recuperadas para 2006 ainda colocavam a China em <b>segundo lugar</b>.",
                body,
            ),
            Paragraph(
                f"A pista de 2007 mede <b>comércio bilateral agregado</b>. Nenhum dos {summary['documents']} documentos estabelece que a China já fosse o primeiro destino das <b>exportações de bens</b>, a métrica da especificação cross-country principal. O DFAT confirma a diferença: em 2007, China foi a maior parceira bilateral em bens e serviços, enquanto Japão permaneceu como maior mercado de exportações.",
                body,
            ),
            Paragraph(
                "Implicação: 2009 não deve ser tratado como a primeira pista pública ampla da Austrália, mas a evidência de 2007 também não autoriza recodificar automaticamente o tratamento goods-only de 2009.",
                ParagraphStyle(
                    "Callout",
                    parent=body,
                    fontName="Helvetica-Bold",
                    backColor=BLUE,
                    borderColor=NAVY,
                    borderWidth=0.6,
                    borderPadding=8,
                    spaceBefore=2 * mm,
                    spaceAfter=5 * mm,
                ),
            ),
            PageBreak(),
            Paragraph("Evidência documental", heading),
            Paragraph(
                "Tabela 1. Documentos recuperados. Cue amplo positivo significa primeiro lugar sob a métrica usada pelo próprio documento; não significa alinhamento com exportações goods-only.",
                caption,
            ),
        ]
    )

    table_data = [
        [
            Paragraph("Fonte e data", table_head),
            Paragraph("Rank", table_head),
            Paragraph("Métrica", table_head),
            Paragraph("Período", table_head),
            Paragraph("Cue / acesso", table_head),
        ]
    ]
    for row in rows:
        cue = "Sim" if row["positive_broad_cue"] == "true" else "Não"
        table_data.append(
            [
                Paragraph(linked_label(row), small),
                Paragraph(f"China #{escape(row['rank_position_china'])}", small_center),
                Paragraph(escape(metric_label(row)), small),
                Paragraph(escape(row["reference_period"]), small),
                Paragraph(f"<b>{cue}</b><br/>{escape(access_label(row))}", small),
            ]
        )
    evidence_table = Table(
        table_data,
        colWidths=[31 * mm, 14 * mm, 48 * mm, 40 * mm, 38 * mm],
        repeatRows=1,
    )
    table_style = [
        ("BACKGROUND", (0, 0), (-1, 0), NAVY),
        ("GRID", (0, 0), (-1, -1), 0.4, colors.HexColor("#AAB7C4")),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("TOPPADDING", (0, 0), (-1, -1), 5),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 5),
        ("LEFTPADDING", (0, 0), (-1, -1), 4),
        ("RIGHTPADDING", (0, 0), (-1, -1), 4),
    ]
    for index, row in enumerate(rows, start=1):
        background = PALE if index % 2 == 0 else colors.white
        table_style.append(("BACKGROUND", (0, index), (-1, index), background))
        cue_color = GREEN if row["positive_broad_cue"] == "true" else RED
        table_style.append(("BACKGROUND", (4, index), (4, index), cue_color))
    evidence_table.setStyle(TableStyle(table_style))
    story.extend([evidence_table, Spacer(1, 5 * mm)])

    story.extend(
        [
            Paragraph("A leitura correta do terceiro ano do AFR", heading),
            Paragraph(
                "O Australian Financial Review situa o primeiro lugar inicial em <b>2006-07</b> e o dado corrente em <b>2008-09</b>. A sequência é fiscal: 2006-07, 2007-08 e 2008-09. Ela não corresponde aos anos-calendário 2006, 2007 e 2008.",
                body,
            ),
            Paragraph(
                "A distinção é confirmada pelos comunicados do DFAT: Japão voltou ao primeiro lugar no comércio bilateral do ano-calendário de 2008; China aparece em primeiro no ano fiscal 2008-09. Em ambos os casos, Japão continuava como maior mercado de exportações.",
                body,
            ),
            Paragraph("Busca e limites", heading),
            Paragraph(
                "As consultas combinaram publicadores, China, Austrália, Japão, largest/biggest trading partner, second-largest export destination, 2006, 2007 e 2006-07. Foram pesquisados ABC, AFR, Sydney Morning Herald, The Age, RBA e DFAT. Nenhuma matéria verificável de 2006-2007 foi recuperada em AFR, Sydney Morning Herald ou The Age. Isto é uma lacuna de recuperação, não evidência de ausência de publicação.",
                body,
            ),
            Paragraph(
                "O RBA e o DFAT 2007 foram verificados no navegador de pesquisa, mas o coletor não arquivou os artigos porque os endpoints de robots ficaram indisponíveis. Três matérias da ABC foram arquivadas após verificação de robots. Três raws anteriores, incluindo o AFR, foram reutilizados somente após conferência de SHA-256.",
                body,
            ),
            PageBreak(),
            Paragraph("Proveniência e reprodução", heading),
            Paragraph(
                f"O CSV documento a documento, o cadastro de fontes, o manifesto, o log de busca e o coletor ficam no repositório. A validação offline retornou PASS: {summary['documents']} documentos, {summary['positive']} pistas positivas amplas, {summary['strict']} fonte goods-only estrita e primeira pista positiva em {summary['earliest']}. SHA-256 do CSV usado neste PDF: <font name=\"Courier\" size=\"7.2\">{csv_hash}</font>.",
                body,
            ),
            Paragraph(
                "Uma revisão independente somente leitura repetiu testes adversariais e aprovou o fechamento. O validador rejeita alteração da base fiscal do AFR, ID duplicado e mudança de rank, além de recalcular os marcadores nos raws preservados.",
                body,
            ),
            Paragraph(
                "python3 scripts/diagnostics/collect_australia_public_cue_2006_2009.py --build --validate --run-dir data/raw/status_cue_salience/AUS/australia_media_search/20260922T160400Z",
                code,
            ),
            Spacer(1, 4 * mm),
            KeepTogether(
                [
                    Paragraph("Arquivos canônicos", heading),
                    Paragraph(
                        "- Relatório-fonte: reports/status_cue_salience/australia_public_cue_2006_2009.md<br/>"
                        "- Dados: data/processed/status_cue_salience/australia_public_cue_media_2006_2009.csv<br/>"
                        "- Fontes: data/processed/status_cue_salience/SOURCES.yaml<br/>"
                        "- Manifesto: scripts/diagnostics/australia_public_cue_2006_2009_manifest.json<br/>"
                        "- Log de busca: scripts/diagnostics/australia_public_cue_2006_2009_search_log.json<br/>"
                        "- Checksums: data/raw/status_cue_salience/checksums.sha256",
                        body,
                    ),
                ]
            ),
            Paragraph("Limite de escopo", heading),
            Paragraph(
                "Este trabalho registrou evidência e proveniência. Não alterou o manuscrito, o PDF do paper, o pipeline targets, modelos, resultados ou a codificação vigente do tratamento.",
                body,
            ),
        ]
    )

    document.build(story, onFirstPage=page_decor, onLaterPages=page_decor)


def main() -> int:
    rows = read_rows()
    build_pdf(rows)
    print(OUTPUT)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
