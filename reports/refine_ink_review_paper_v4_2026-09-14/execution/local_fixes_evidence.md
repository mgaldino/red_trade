# Evidência localizada — local_fixes

## Identidade do artefato

| Arquivo | SHA-256 |
|---|---|
| `paper_v4.Rmd` | `9c6b03ed3d3703e4a76eb6f35c43201afb08f0479266a1c08b60008e34ff13b4` |
| `output/paper_v4.pdf` | `da7b84fd44a1071953c5c2941be53aefb75f2b249476cc2d6e065e5f8463e312` |
| `execution/baseline/paper_v4.Rmd` | `9c6b03ed3d3703e4a76eb6f35c43201afb08f0479266a1c08b60008e34ff13b4` |
| `execution/baseline/paper_v4.pdf` | `da7b84fd44a1071953c5c2941be53aefb75f2b249476cc2d6e065e5f8463e312` |
| `feedback-the-foreign-policy-impact-of-trade-based-status-ga-2026-09-14.md` | `eb7dc9488e3b6726cee0ddf232250be18f09291797e2a85470b67637af58b88a` |
| `items_to_address.md` | `d0220df748585215fc3ce14786e555546134d1e25534470ee153b1872437ea25` |

## Inspeção estática

- `paper_v4.Rmd:2128–2142` mostra que a Tabela 23 consome somente primeiro tratamento, contagens tratadas/não tratadas e limites do painel.
- `scripts/functions.R:4119–4264` constrói períodos observados e qualificantes; `scripts/functions.R:4268–4364` aplica o risco restrito e remove colunas auxiliares; `scripts/functions.R:4407–4521` mantém apenas resumos agregados e períodos, sem uma saída país-ano de omissões.
- `paper_v4.Rmd:340–345` usa uma imagem já produzida para a Figura 2 e mantém na caption a expressão ambígua “post-treatment gap”. A inspeção visual do PNG mostra as trajetórias e a seta separada.
- `paper_v4.Rmd:300` contém a frase que coloca o país subindo na hierarquia da China; `paper_v4.Rmd:314`, `320–324` e `328–330` descrevem a implementação pretendida como China chegando ao primeiro lugar entre os destinos de exportação.
- `paper_v4.Rmd:20` diz “median”; `paper_v4.Rmd:83–92` define `mean_br` por média pré-2009; `paper_v4.Rmd:149` e `2239–2240` usam média; a Tabela 24 é alimentada por `sdid_comparison_table.csv`.
- `sdid_comparison_table.csv` associa `0.646777890583333` ao BSV e `0.836545155415565` ao UNGA-DM; `sdid_dm_main_summary.csv` confirma a média UNGA-DM.
- `execution/cross_country.json:item15_target_design` e `execution/sdid.json:item29_caption_prerequisites` foram lidos e incorporados no record. O primeiro exige quatro alvos novos, campos país-ano, estados de linha exclusivos e oito validações; o segundo exige que a caption diferencie trajetórias brutas do ATT líquido da diferença prévia ponderada.

## Verificação computacional R

O comando e a saída final estão em `local_fixes_r_checks.txt`. A leitura foi feita com `targets::tar_read(synth_data)` e `read.csv()` sobre outputs existentes. As operações foram média, mediana, razões e `stopifnot()` de identidades; não houve estimação, placebos, bootstrap, `tar_make()` ou escrita de output analítico.

Resultado relevante:

- Brasil pré-2009: 1997–2008, `n = 12`.
- Média: `0.646777890583333`.
- Mediana: `0.620922368500000`.
- ATT BSV armazenado: `-0.272771407583060`.
- Razão absoluta sobre a média: `42.173891772497932%`.
- Razão absoluta sobre a mediana: `43.930033997971528%`.
- UNGA-DM: média `0.836545155415565`, percentual `39.514054175898416%`.
- Identidades numéricas verificadas: `CHECKS: PASS`.

## Fronteira testado/não testado

Testado: identidade dos bytes, localização das passagens, leitura dos pré-requisitos, inspeção do produtor status-current, inspeção visual do PNG da Figura 2 e reconciliação aritmética em R.

Não testado: frescor do store `targets`, execução de novos alvos, reestimação, novo PDF, equivalência substantiva das medidas, busca de novas fontes públicas ou implementação dos patches.
