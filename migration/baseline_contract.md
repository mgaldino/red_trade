# Contrato do baseline pré-migração

## Identidade

- Checkout de referência: `/Users/manoelgaldino/Documents/DCP/Papers/RDD Trade/red_trade`.
- Commit analítico anterior ao plano: `6da13b58a120f3be7ffa9304af1a3285ccfe956a`.
- Commit documental e tag: `2b5d00efc21ace075f4b646e5142b173d898de13` /
  `pre-targets-migration-2026-09-01`.
- Branch de implementação: `codex/targets-migration`.
- Data da captura: 2026-09-02.

O checkout principal e seu store `_targets/` são somente referência. Nenhuma estimação
foi executada para produzir este contrato.

## Folhas diretas do manuscrito

`migration/baseline_direct_paper_leaves.csv` registra 27 arquivos lidos diretamente por
`paper_v4.Rmd` e que precisam deixar de ser folhas externas:

- 12 CSVs do SDiD principal;
- uma tabela CSV de commodity/Table 5;
- três PNGs SDiD em diretório ignorado;
- uma figura PDF de dose-resposta;
- uma figura PNG cross-country;
- nove CSVs UNGA-DM.

O arquivo registra tamanho, SHA-256 e dimensões dos CSVs. Os três PNGs localizados em
`quality_reports/` existem no checkout principal, mas não são materializados por um novo
worktree porque o diretório é ignorado pelo Git.

## Insumos externos congelados

### Evidência de status

- Arquivos: 139.
- Bytes: 22.808.647 (21,75 MiB).
- SHA-256 do manifesto textual ordenado de `caminho + hash`:
  `981ae02acb8c419829913bb72fa3b4984e24b7cdef74906d0e2f073b91fe40b2`.
- Decisão do autor: manter no Git e no pacote de replicação.

### UNGA-DM e BSV

| Arquivo | Bytes | SHA-256 |
|---|---:|---|
| `raw data/unga_dm/unga_dm_ideal_points_all_resolution_votes_s75.csv` | 2.060.041 | `3713cadff82a220dcc332cc09e433037144b1c41e3be07343d38a309506761f7` |
| `raw data/unga_dm/unga_dm_codebook.pdf` | 278.907 | `74117c225215dc8c749ba8b84dbbca0a23aba795046f1ffdd00d1ee9631cad69` |
| `raw data/dataverse_files-2/IdealpointestimatesAll_Jun2024.csv` | 1.932.704 | `94ce7440bdba9252b2f4294333291585748dfe84dbaf56fe9f26e1af38f66198` |

O diretório `raw data/` é ignorado pelo Git e não aparece automaticamente no worktree.
Os insumos devem ser disponibilizados no ambiente de migração por cópia isolada e
validados novamente antes de qualquer build.

## Valores de referência

### SDiD Brasil, especificação preferida sem covariáveis

- ATT: `-0.27277140758306007`.
- SE placebo: `0.13060794328219072`.
- IC 95%: `[-0.5287582725110039, -0.016784542655116197]`.
- p normal bilateral: `0.03675501981479939`.
- rank direcional: `3/96`, p `0.03125`.
- rank absoluto bilateral: `7/96`, p `0.07291666666666667`.
- replicações/seed: `20000` / `20260520`.

Esses valores devem ser idênticos na migração, salvo finding adjudicado de erro na
implementação legada.

### UNGA-DM, SDiD Brasil

- ATT: `-0.33055290591675995`.
- SE placebo: `0.1251452893905264`.
- IC 95%: `[-0.5758331659570342, -0.08527264587648573]`.
- p normal bilateral: `0.008257559300511077`.
- rank direcional: `3/96`, p `0.03125`.
- rank absoluto bilateral: `5/96`, p `0.052083333333333336`.
- replicações/seed: `20000` / `20260520`.

### Cross-country IFE: baseline antigo e correção aprovada

O target de produção antigo não é o gabarito substantivo para a construção do painel.
A migração deve incorporar a correção `full_join` com grade explícita, já documentada
em `scripts/diagnostics/prepare_manuscript_correction_full_join_report.R`.

| Estatística | Target antigo | Correção `full_join` |
|---|---:|---:|
| ATT | -0.1006420140210192 | -0.10072962830167595 |
| SE bootstrap | 0.03912661176449206 | 0.039284768671216226 |
| IC inferior | -0.17733017307942364 | -0.17772777489725977 |
| IC superior | -0.02395385496261476 | -0.023731481706092142 |
| p | 0.01010504420567779 | 0.010344712795288327 |
| fatores selecionados | 2 | 2 |
| observações | 5.037 | 5.002 |
| países | 161 | 160 |
| tratados | 35 | 35 |
| controles | 126 | 125 |
| país-anos tratados | 440 | 440 |

A diferença esperada decorre de `COD–2021`: elegível pelo tratamento comercial, mas
sem outcome UNGA. A integração correta preserva a linha no painel mestre e a exclui da
estimação por outcome ausente; não condiciona a construção do tratamento ao outcome.

### UNGA-DM, IFE em janela comum

- BSV: ATT `-0.09532156006332301`, p `0.0163487622799316`, `r = 2`.
- UNGA-DM: ATT `-0.026818587461689563`, p `0.5731946664011927`, `r = 1`.
- Ambos usam 4.727 observações, 161 países e janela 1990–2020 no baseline legado.

Ao migrar para o painel mestre corrigido, qualquer alteração nessa amostra deve ser
explicada pela nova regra de grade/missingness e adjudicada, não silenciada.

## Regras de comparação

1. Igualdade numérica a `1e-12` para transformações e estimações cuja especificação,
   amostra, seed e ambiente sejam idênticos.
2. Igualdade de chaves, dimensões, amostra e missingness antes de comparar estimativas.
3. Hash idêntico para arquivos determinísticos quando o formato não embutir metadados
   voláteis.
4. Para figuras, comparar primeiro os dados subjacentes e depois fazer inspeção visual;
   hash binário diferente não é, sozinho, finding substantivo.
5. A correção `full_join` é uma diferença substantiva já esperada; o target antigo não
   deve ser reproduzido apenas para obter igualdade.
