# Contrato de migração — UNGA-DM

## Escopo e autoridade

Este bloco substitui a computação hoje duplicada em
`validate_ungadm_ideal_points.R`, `audit_ungadm_outcome_robustness.R` e
`audit_ungadm_postreview_diagnostics.R` por funções puras e targets candidatos.
Os scripts e outputs antigos permanecem intactos como baseline até a promoção.

As decisões substantivas já aprovadas pelo autor são:

- BSV Jun/2024 continua sendo o outcome principal;
- UNGA-DM é robustez de mensuração reportada independentemente do resultado;
- o universo UNGA-DM inclui decisões relacionadas a resoluções além do universo
  BSV, portanto as fontes não são tratadas como a mesma medida com mera correção
  de erro;
- tratamento, períodos qualificados, risk set e grade país × ano são definidos
  antes e independentemente da disponibilidade do outcome;
- a grade mestre cobre 1990–2023;
- UNGA-DM entra por `left_join`; 2021–2023 e outras lacunas permanecem `NA`, sem
  imputação;
- a comparação BSV–UNGA-DM usa um target analítico a jusante com exatamente as
  mesmas linhas nas duas colunas.

## Insumos brutos congelados

Todos são file targets e o build não acessa a rede.

| Insumo | Bytes | SHA-256 |
|---|---:|---|
| `raw data/unga_dm/unga_dm_ideal_points_all_resolution_votes_s75.csv` | 2.060.041 | `3713cadff82a220dcc332cc09e433037144b1c41e3be07343d38a309506761f7` |
| `raw data/unga_dm/unga_dm_codebook.pdf` | 278.907 | `74117c225215dc8c749ba8b84dbbca0a23aba795046f1ffdd00d1ee9631cad69` |
| `raw data/dataverse_files-2/IdealpointestimatesAll_Jun2024.csv` | 1.932.704 | `94ce7440bdba9252b2f4294333291585748dfe84dbaf56fe9f26e1af38f66198` |

O CSV UNGA-DM contém 10.687 linhas de dados; o BSV contém 11.238. O CSV e o
codebook UNGA-DM, o BSV e `raw data/unga_dm/SOURCES.md` entram no pacote de
replicação. Esta etapa não decide se os três binários ignorados por Git serão
versionados diretamente no repositório ou incluídos apenas na montagem do
pacote; ela exige que estejam presentes e tenham os hashes acima.

## Harmonização única

1. Limpar nomes de colunas e exigir chaves únicas `ccode × session` nas duas
   fontes.
2. Usar a mediana posterior: `Q50%All` no BSV e `X50.` no UNGA-DM.
3. Corrigir explicitamente a convenção alemã na sessão 45: UNGA-DM `ccode=255`
   corresponde ao BSV `ccode=260`, `iso3c=DEU`.
4. Mapear `iso3c` por `ccode × session` contra o BSV, preservando todas as
   linhas sem mapeamento em um target diagnóstico.
5. Exigir exatamente um ponto da China (`ccode=710`) por sessão usada e
   calcular `abs_distance_china_dm = abs(q50_dm - china_ideal_dm)`.
6. Definir `year = session + 1945`; a tabela analítica harmonizada começa em
   1990 e tem chave única `iso3c × year`.
7. Fazer `left_join` dessa tabela no
   `china_top_m2_goods_full_union_master_panel`, sem alterar o universo de
   países, a grade, os ranks comerciais ou a codificação do tratamento.

## Construção analítica

### Validação da fonte

- comparar BSV e UNGA-DM por país-sessão;
- produzir cobertura, lacunas dentro da cobertura, correlações por janela,
  série do Brasil, resumo de gaps e overlay;
- manter como gate duro correlação de `abs_distance_china` no painel
  1997–2015 maior ou igual a 0,95;
- registrar as linhas UNGA-DM sem `iso3c`, sem descartá-las silenciosamente.

### SDiD Brasil

- janela 1997–2015, entrada em 2009, 96 atribuições;
- especificação preferida sem covariáveis;
- SE placebo com 20.000 replicações e seed `20260520`;
- mesma implementação canônica, checkpoints, fingerprints e gates já aprovados
  no bloco SDiD/commodities;
- ranks direcionais e bilaterais, pesos, time weights, balanço e critérios de
  exclusão de doadores produzidos como targets;
- critério substantivo de exclusão: status China-top observado em 1997–2015;
  a regra de cinco anos permanece apenas como auditoria rotulada.

### Painel IFE e pós-revisão

- partir do row audit estrutural de cinco anos do painel full-union corrigido;
- aplicar o risk set antes da seleção por outcome;
- construir a interseção de linhas com BSV e UNGA-DM observados;
- exigir igualdade exata de `iso3c × year`, tratamento, papéis e contagens nas
  variantes BSV e UNGA-DM;
- estimar as duas variantes com cross-validation em `r = 0:3` e 10.000
  bootstraps;
- estimar a grade 2 × 2 BSV/UNGA-DM × `r = 1/2`, 10.000 bootstraps por célula;
- bootstrap pareado por país, estratificado em tratados/controles, `B = 1.000`,
  seed `20260823`, mesmos sorteios nas duas medidas;
- preservar draws, resumo da diferença, dinâmica, divergência por país e médias
  de grupo.

## Baseline de 2026-08-26

Os CSVs existentes, não a prosa histórica em `PENDING.md` ou nos relatórios de
23/08, são o gabarito do pipeline externo vigente. Os arquivos atuais registram
20.000 placebos, seed `20260520`, 10.000 bootstraps IFE e ausência de smoke
test.

### SDiD, igualdade esperada a `1e-12`

| Fonte | ATT | SE | p normal | rank dir. | rank bilat. |
|---|---:|---:|---:|---:|---:|
| BSV | -0.27277140758306007 | 0.13060794328219072 | 0.03675501981479939 | 3/96 | 7/96 |
| UNGA-DM | -0.33055290591675995 | 0.12514528939052640 | 0.008257559300511077 | 3/96 | 5/96 |

O baseline de UNGA-DM tem 28 linhas sem mapeamento ISO3 e zero missing no
painel SDiD 1997–2015. Divergência aqui é erro novo, erro antigo ou diferença
de ambiente a ser adjudicada antes de qualquer promoção.

### IFE antigo, somente comparador

O pipeline externo antigo usou o painel pré-correção: 5.037 observações e 161
países na janela cheia; 4.727 e 161 na janela comum, com 35 tratados e 126
controles. Seus principais pontos foram BSV comum `-0.09532156006332301`,
UNGA-DM comum `-0.026818587461689563`, e na grade de fatores BSV/UNGA-DM em
`r=2`, respectivamente, `-0.09532156006332301` e
`-0.06483882160990317`.

Esses números **não** são contrato de igualdade, porque a migração aprovada
substitui esse painel pelo full-union corrigido (5.002 observações, 160 países,
35 tratados, 125 controles e 440 períodos tratados na janela cheia). A nova
estimação deve ser comparada ao baseline, e toda diferença deve ser explicada
pela mudança de amostra ou classificada como erro. O tratamento nunca será
redefinido para reproduzir o baseline antigo.

### Hashes das folhas lidas pelo manuscrito

| Arquivo | SHA-256 |
|---|---|
| `estimation/sdid_comparison_table.csv` | `5e7e6cddd7dfeb845a0b90316699770fb51b96539d25712136eb46d43ba7dadc` |
| `estimation/sdid_dm_placebo_distribution.csv` | `d71cd822a5d62a51d7a22343e6753d5bca162b4dc49270850e6edd0cb92603dd` |
| `postreview/sdid_dm_rank_inference_harmonized.csv` | `ee03666e2ab09b2cfc5d39ac93e2bab645b94d925cf041906f9a081798fd1814` |
| `estimation/sdid_unit_weights_bsv_vs_dm.csv` | `eba127b5e1182cbbc24ec3a2b213e1d7279f522d460138cfb6ee1395dfd45ec1` |
| `estimation/ife_comparison_table.csv` | `3815f6a671827f7c2e65e66cb7bd7678aa759991aa7e8b9dae56855373121c55` |
| `postreview/ife_2x2_fixed_r.csv` | `ce4eb407408ade1f06b52dffa58c648459dfd77d7d852a55a850d48c96577021` |
| `postreview/ife_paired_bootstrap_summary.csv` | `a21155abc05e374856bef67408be5eefcc174b31dd421fde7c6548ef16287cfe` |
| `estimation/dm_rows_without_iso3c_mapping.csv` | `b33a8bf0944f301782a63d0aa698ad410c90996f6717b5e92951bd7508c2c748` |
| `estimation/sdid_dm_missing_outcome_rows.csv` | `99173669079ee5838ffe35e9b735a7904b74ba08a8782af8229eabbb5177ccb4` |

## Outputs candidatos

Objetos e file targets devem cobrir todas as tabelas/figuras consumidas pelo
manuscrito e os diagnósticos necessários à auditoria: harmonização e validação;
SDiD summary/distribuição/ranks/pesos/time weights/balanço; comparação BSV–DM;
painéis de janela comum; comparação IFE; dinâmica; grade 2 × 2; draws e resumo
do bootstrap pareado; divergência por país; médias por grupo; overlay de
validação; pretrend e equivalence plot já derivados do modelo principal.

Logs ad hoc, `session_info.txt` e manifestos manuais dos scripts externos são
substituídos por metadados do `targets`, pelo `renv.lock`, pelos hashes dos file
targets e pelo relatório de comparação. Não são dependências do manuscrito.

Todos os artefatos ficam sob `data/processed/targets_migration/ungadm/` e
`images/targets_migration/ungadm/` até a adjudicação. O manuscrito continua
lendo os arquivos antigos nesta fase.

## Gates antes de computação cara

- parse e manifesto estático;
- hashes, schemas, tipos, chaves e unicidade;
- sessão, ano e valores finitos/compatíveis;
- uma âncora chinesa por sessão;
- exceção alemã explícita e auditável;
- grade mestre inalterada após o `left_join`;
- 2021–2023 presentes com UNGA-DM `NA`;
- tratamento/risk set idênticos antes e depois do join;
- igualdade de linhas nas variantes de janela comum;
- painel SDiD completo e donor pool invariável;
- smoke tests jamais aceitos como outputs finais;
- `review-r` independente até PASS sem ressalvas.

Não executar `tar_make()`, modelos, placebos, bootstrap ou render sem nova
autorização específica.
