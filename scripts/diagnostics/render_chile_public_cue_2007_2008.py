#!/usr/bin/env python3
"""Render the focused Chile source audit as a reader-facing PDF.

Run with Python and reportlab after building the audit CSVs. This script reads
the frozen build manifest and verifies the source-output checksum before
rendering. It does not contact websites or run targets.
"""

from __future__ import annotations

import csv
import hashlib
from html import escape
import json
from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER, TA_LEFT
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import KeepTogether, Paragraph, SimpleDocTemplate, Spacer, Table, TableStyle


ROOT = Path(__file__).resolve().parents[2]
STEM = "chile_public_cue_2007_2008"
MANIFEST = ROOT / f"data/processed/status_cue_salience/{STEM}_build_manifest.json"
SOURCE_CSV = ROOT / f"data/processed/status_cue_salience/{STEM}_source_evidence.csv"
COUNTRY_CSV = ROOT / f"data/processed/status_cue_salience/{STEM}_country_code.csv"
OUTPUT = ROOT / f"output/pdf/{STEM}.pdf"
NAVY = colors.HexColor("#17365D")
BLUE = colors.HexColor("#DDE9F3")
PALE = colors.HexColor("#F4F7FA")
INK = colors.HexColor("#263441")
MUTED = colors.HexColor("#566779")


def font_setup() -> tuple[str, str]:
    font_dir = Path("/System/Library/Fonts/Supplemental")
    regular = font_dir / "Arial.ttf"
    bold = font_dir / "Arial Bold.ttf"
    if regular.is_file() and bold.is_file():
        pdfmetrics.registerFont(TTFont("AuditArial", str(regular)))
        pdfmetrics.registerFont(TTFont("AuditArial-Bold", str(bold)))
        pdfmetrics.registerFontFamily("AuditArial", normal="AuditArial", bold="AuditArial-Bold")
        return "AuditArial", "AuditArial-Bold"
    return "Helvetica", "Helvetica-Bold"


def read_verified() -> tuple[list[dict[str, str]], dict[str, str], dict[str, object]]:
    build = json.loads(MANIFEST.read_text(encoding="utf-8"))
    expected = {item["path"]: item["sha256"] for item in build["outputs"]}
    for p in (SOURCE_CSV, COUNTRY_CSV):
        key = str(p.relative_to(ROOT))
        if hashlib.sha256(p.read_bytes()).hexdigest() != expected[key]:
            raise ValueError(f"Output hash changed since build: {key}")
    with SOURCE_CSV.open(encoding="utf-8", newline="") as handle:
        sources = list(csv.DictReader(handle))
    with COUNTRY_CSV.open(encoding="utf-8", newline="") as handle:
        countries = list(csv.DictReader(handle))
    if len(countries) != 1 or countries[0]["iso3c"] != "CHL" or countries[0]["salience_code"] != "high":
        raise ValueError("Expected Chile high in country table")
    if len(sources) != 7 or sum(not r["notes"].startswith("DO_NOT_COUNT") for r in sources) != 5:
        raise ValueError("Expected seven candidate and five counted sources")
    return sources, countries[0], build


def page_decor(canvas, doc) -> None:
    canvas.saveState()
    width, height = A4
    canvas.setStrokeColor(colors.HexColor("#B7C5D2"))
    canvas.setLineWidth(0.45)
    canvas.line(doc.leftMargin, height - 15.5 * mm, width - doc.rightMargin, height - 15.5 * mm)
    canvas.setFillColor(MUTED)
    canvas.setFont("Helvetica", 8)
    canvas.drawString(doc.leftMargin, height - 12.2 * mm, "RDD Trade | Auditoria de public cue: Chile")
    canvas.drawRightString(width - doc.rightMargin, 11.2 * mm, f"Página {doc.page}")
    canvas.drawString(doc.leftMargin, 11.2 * mm, "Consulta documental: 22 de setembro de 2026")
    canvas.restoreState()


def label_date(value: str) -> str:
    if value == "2007-05":
        return "maio/2007*"
    year, month, day = value.split("-")
    return f"{day}/{month}/{year}"


def main() -> None:
    sources, country, build = read_verified()
    normal_font, bold_font = font_setup()
    styles = getSampleStyleSheet()
    title = ParagraphStyle(
        "AuditTitle", parent=styles["Title"], fontName=bold_font, fontSize=20,
        leading=24, alignment=TA_LEFT, textColor=NAVY, spaceAfter=5 * mm,
    )
    subtitle = ParagraphStyle(
        "AuditSubtitle", parent=styles["Normal"], fontName=normal_font,
        fontSize=9.4, leading=13.2, textColor=MUTED, spaceAfter=5 * mm,
    )
    head = ParagraphStyle(
        "AuditHead", parent=styles["Heading2"], fontName=bold_font,
        fontSize=12, leading=15, textColor=NAVY, spaceBefore=4.2 * mm,
        spaceAfter=2.6 * mm, keepWithNext=True,
    )
    body = ParagraphStyle(
        "AuditBody", parent=styles["BodyText"], fontName=normal_font,
        fontSize=9.1, leading=13.3, textColor=INK, spaceAfter=3.3 * mm,
    )
    small = ParagraphStyle(
        "AuditSmall", parent=body, fontSize=7.5, leading=10, spaceAfter=0,
    )
    table_head = ParagraphStyle(
        "AuditTableHead", parent=small, fontName=bold_font,
        textColor=colors.white, alignment=TA_CENTER,
    )
    callout = ParagraphStyle(
        "AuditCallout", parent=body, fontName=bold_font,
        fontSize=10.5, leading=15.2, textColor=NAVY,
        backColor=BLUE, borderPadding=10, spaceAfter=5 * mm,
    )
    foot = ParagraphStyle(
        "AuditFoot", parent=body, fontSize=7.8, leading=10.8,
        textColor=MUTED, spaceAfter=2 * mm,
    )
    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    doc = SimpleDocTemplate(
        str(OUTPUT), pagesize=A4, leftMargin=18 * mm, rightMargin=18 * mm,
        topMargin=22 * mm, bottomMargin=19 * mm,
        title="Chile: public cue de primeiro destino das exportações, 2007-2008",
        author="RDD Trade research audit",
        subject="Auditoria documental focal de fontes chilenas de 2007 e 2008",
    )
    story = [
        Spacer(1, 5 * mm),
        Paragraph("Chile: public cue comercial, 2007-2008", title),
        Paragraph("Janela: primeira entrada da China como destino nº 1 de exportações de bens no inventário M2 (2007), mais o ano seguinte.", subtitle),
        Paragraph("Código: HIGH - cue explícito em notícia chilena e fontes oficiais independentes de 2007; reafirmado em 2008.", callout),
        Paragraph(
            "O inventário de exportações de bens registra a entrada em 2007 e os Estados Unidos como parceiro antes no topo. "
            "Esta auditoria identifica quando o rótulo público circulou; a série anual de tratamento continua definida pelo inventário.",
            body,
        ),
        Paragraph("Tabela 1. Fontes contemporâneas contadas", head),
    ]
    metric = {
        "chl_mundomaritimo_2007_02_19": "Exportações nacionais de bens, janeiro de 2007. China à frente dos EUA.",
        "chl_direcon_2007_05_q1_report": "Exportações de bens, primeiro trimestre. China primeiro país individual; UE primeiro bloco.",
        "chl_bcn_2007_10_01": "Exportações nacionais, primeiro semestre de 2007; artigo da BCN.",
        "chl_emol_efe_2008_04_15": "Principal destino atual das exportações; comércio total futuro é previsão.",
        "chl_mundomaritimo_2008_05_19": "Exportações de bens, abril de 2008: China 1ª, Japão 2º, EUA 3º.",
    }
    short_name = {
        "chl_mundomaritimo_2007_02_19": "El Mercurio via MundoMarítimo",
        "chl_direcon_2007_05_q1_report": "DIRECON",
        "chl_bcn_2007_10_01": "Biblioteca do Congresso",
        "chl_emol_efe_2008_04_15": "Emol / EFE",
        "chl_mundomaritimo_2008_05_19": "El Mercurio via MundoMarítimo",
    }
    counted = [r for r in sources if not r["notes"].startswith("DO_NOT_COUNT")]
    data = [[Paragraph(x, table_head) for x in ("Publicação", "Fonte", "Métrica e período", "Status")]]
    for row in counted:
        sid = row["raw_file"].split("/")[-2]
        link = f'<link href="{escape(row["url"], quote=True)}" color="#17365D"><u>{escape(short_name[sid])}</u></link>'
        data.append([
            Paragraph(label_date(row["publication_date"]), small),
            Paragraph(link, small),
            Paragraph(escape(metric[sid]), small),
            Paragraph("Conta", small),
        ])
    table = Table(data, colWidths=[24 * mm, 46 * mm, 91 * mm, 13 * mm], repeatRows=1, hAlign="LEFT")
    table.setStyle(TableStyle([
        ("BACKGROUND", (0, 0), (-1, 0), NAVY),
        ("ROWBACKGROUNDS", (0, 1), (-1, -1), [colors.white, PALE]),
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("GRID", (0, 0), (-1, -1), 0.35, colors.HexColor("#CCD6DF")),
        ("LEFTPADDING", (0, 0), (-1, -1), 5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 5),
        ("TOPPADDING", (0, 0), (-1, -1), 6),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 6),
    ]))
    story += [
        table, Spacer(1, 2 * mm),
        Paragraph("* O relatório oficial DIRECON traz somente mês e ano na capa; nenhum dia de publicação foi presumido.", foot),
        Paragraph("Por que a codificação é high", head),
        Paragraph(
            "Em 19/02/2007, notícia chilena publicada pelo MundoMarítimo e atribuída ao El Mercurio põe a China como principal destino e os EUA em segundo nas exportações de janeiro. "
            "O relatório oficial DIRECON de maio de 2007 afirma a primeira posição da China entre países individuais no primeiro trimestre. "
            "A Biblioteca do Congresso Nacional repete o rótulo em 01/10/2007. "
            "Essas publicações não pertencem à mesma família editorial. Em 2008, Emol/EFE e El Mercurio repetem a posição exportadora.",
            body,
        ),
        Paragraph("Definição do rank e fontes excluídas", head),
        Paragraph(
            "A DIRECON põe a União Europeia acima da China quando trata o bloco como um destino agregado; na comparação entre países individuais, a China está acima dos EUA. "
            "O comunicado DIRECON de 15/12/2008 coloca os EUA em primeiro no comércio bilateral total (exportações mais importações), uma medida diferente do destino das exportações.",
            body,
        ),
        Paragraph(
            "Uma página SUBREI exibida como 25/01/2007 menciona etapas da negociação com a China que ocorreram em 2008-2009. "
            "Sua data aparente não é confiável e ela foi marcada DO_NOT_COUNT. A fala no Emol/EFE de que a China poderia assumir depois o primeiro lugar no comércio total também foi tratada como previsão.",
            body,
        ),
        Paragraph("Proveniência e reprodução", head),
        Paragraph(
            "O acesso automatizado à página da Biblioteca do Congresso parou na verificação de robots.txt. "
            "O usuário forneceu um PDF completo impresso pelo Safari, com URL, data do artigo e texto; uma cópia idêntica foi arquivada com SHA-256. "
            "As outras fontes contadas foram capturadas por HTTPS com checagem de robots.txt. "
            "Há 10 consultas executadas registradas. GDELT DOC 2.0 não cobre utilmente esta janela anterior a 2017.",
            body,
        ),
        Paragraph(
            "Dados: cinco fontes contadas em sete candidatos. Tabelas CSV mantêm o esquema legado, com métrica da fonte e janela acrescentadas. "
            "A codificação legada de 14 países e o manuscrito não foram alterados.",
            body,
        ),
    ]
    doc.build(story, onFirstPage=page_decor, onLaterPages=page_decor)
    print(OUTPUT)


if __name__ == "__main__":
    main()
