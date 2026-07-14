# Pendências do Projeto

Atualizado em: 2026-05-25, após checagem direta de `paper_v4.Rmd` e
`paper_v4.pdf` renderizado em 2026-05-25 17:31 (-03).

## Fonte de verdade operacional

Para o manuscrito ativo, use nesta ordem:

1. `paper_v4.Rmd`
2. `paper_v4.pdf`
3. `_targets.R` e `scripts/functions.R` para verificar se resultados vêm do
   pipeline

Não use `PENDING.md`, `README.md`, relatórios antigos de revisão ou
`paper_v4.extraction_cache.json` como fonte de verdade sem conferir o Rmd/PDF
atuais. O cache de extração pode conter texto de versões anteriores.

## Estado atual do `paper_v4`

### Resolvido: cross-country China #1 status-current

**Status**: Resolvido no manuscrito ativo e migrado para `targets`
**Prioridade**: FECHADO, salvo nova decisão substantiva

A antiga pendência de migrar a recodificação cross-country para `targets` está
superada. O `paper_v4.Rmd` agora usa a especificação goods-only
**status-current** com **restricted risk set**:

- tratamento = 1 apenas em país-anos em que China é o maior destino de
  exportações de bens;
- o período China-top precisa durar pelo menos cinco anos observados;
- anos pós-saída e episódios curtos são removidos do risk set principal;
- há robustez `clean_single_spell` e `switching_allowed`;
- serviços são excluídos antes do cálculo dos ranks.

Alvos relevantes já existem em `_targets.R`:

- `china_top_m2_goods_status_current_panel_bundle`
- `china_top_m2_goods_status_current_model_results`
- `fect_ife_china_top_m2_goods_status_current_min5_risk_set`
- `plot_china_top_m2_goods_status_current_dynamic`

Funções relevantes já existem em `scripts/functions.R`:

- `build_status_current_period_data()`
- `make_status_current_panel()`
- `make_status_current_panel_bundle()`
- `fit_status_current_fect_models()`
- `plot_status_current_dynamic()`

Critério de resolução já atendido: o paper não depende mais de tabelas
cross-country off-target como especificação principal e não usa tratamento
absorvente como estimando principal.

### Resolvido: diagnósticos SDiD do Brasil

**Status**: Resolvido no manuscrito ativo
**Prioridade**: FECHADO

O paper já incorporou:

- resumo compacto de diagnósticos SDiD no corpo do texto;
- pesos completos de doadores;
- pesos de tempo;
- RMSPE e balance;
- placebo ranks;
- sensibilidade a doadores;
- sensibilidade de janela;
- exposição dos doadores de alto peso à expansão chinesa.

Esses itens aparecem no corpo e no apêndice de `paper_v4.Rmd`.

### Resolvido: alinhamento entre tratamento e cue público

**Status**: Resolvido no manuscrito ativo
**Prioridade**: FECHADO

O paper agora distingue explicitamente:

- tratamento empírico: China como maior destino de exportações;
- linguagem pública: `largest trading partner`, `principal trading partner`,
  `main commercial partner`, `top export market`;
- evidência pública: usada como mecanismo, não como redefinição do tratamento.

O caso Austrália/AFR também já foi incorporado como caveat de métrica: o item
AFR documenta cue público amplo de parceiro comercial agregado, mas não conta
como evidência de uptake do tratamento estrito de destino de exportações.

### Resolvido: linguagem causal cross-country

**Status**: Resolvido no manuscrito ativo
**Prioridade**: FECHADO

A seção cross-country foi rebaixada para evidência de escopo/padrão compatível.
O paper usa linguagem como `compatible directional pattern`, `associated with`
e `scope evidence`, e não trata o painel como substituto do teste de mecanismo
brasileiro.

### Resolvido: AGNU/issue-area overclaim

**Status**: Resolvido no manuscrito ativo para a rodada atual
**Prioridade**: FECHADO, salvo nova exigência de parecerista

O paper já calibra a interpretação AGNU:

- a convergência é seletiva, não uniforme;
- a evidência mais informativa está em direitos humanos, especialmente quando
  China e EUA divergem;
- os diagnósticos voto-a-voto são interpretados como conteúdo substantivo e
  benchmark inferencial, não como prova isolada de causalidade;
- o texto evita vender uma aproximação geral ampla com a China.

## Pendências reais remanescentes

### Significância estatística da especificação principal do Brasil

**Status**: Pendência crítica de identificação/inferência
**Prioridade**: MÁXIMA antes de nova circulação

O `paper_v4.pdf` atual mostra um efeito principal negativo, mas impreciso no
nível bilateral de 5%. Na especificação principal do Brazil SDiD, o ATT é
`-0.264`, o erro-padrão baseado em placebo é `0.145`, o intervalo de 95% é
`[-0.548, 0.020]` e o p-valor normal bilateral é `0.069`. A Tabela 3,
portanto, recebe apenas a marca de 10%.

O diagnóstico por ranks produz uma leitura diferente: `p = 0.042` para o
teste unilateral de efeito negativo, mas `p = 0.083` para o teste bilateral de
efeito absoluto. O paper precisa definir explicitamente qual hipótese e qual
regra inferencial são substantivamente justificadas. Não se deve escolher o
teste unilateral apenas para atravessar o limiar de 5%.

Há uma especificação de robustez na Tabela 5 que adiciona exposição
predeterminada a commodities/choques de 2008--2009 e produz ATT `-0.306`, SE
`0.148`, IC `[-0.595, -0.016]` e p `0.038`. Esse resultado pode justificar uma
reavaliação da especificação principal se o controle for parte necessária da
identificação, mas não deve ser promovido automaticamente apenas porque atinge
5%. O teste de estresse completo é instável e não pode ser usado como solução.

Antes de editar o paper, é necessário:

1. Fixar o contrato inferencial da especificação principal: SDiD com uma
   unidade tratada, placebo-in-space/rank inference e hipótese unilateral ou
   bilateral substantivamente justificada.
2. Reestimar, em scripts separados, um conjunto pequeno e pré-especificado de
   alternativas: baseline; exposição predeterminada a commodities; janela
   temporal alternativa; donor pool/risk set justificado; e, se defensável,
   extensão do período pós-2009.
3. Para cada alternativa, reportar ATT, SE, IC, p-valor/rank p-valor, fit,
   balance, pesos dos doadores e estabilidade do sinal. Não escolher a coluna
   pelo p-valor.
4. Verificar se “adicionar observações” muda o estimando. No Brazil SDiD, mais
   doadores não equivalem a mais unidades tratadas independentes; anos
   adicionais podem alterar o período pós-tratamento e incorporar choques
   políticos posteriores.
5. Fazer revisão causal independente antes de decidir qualquer mudança na
   especificação principal.

Critério de resolução: uma especificação principal escolhida por argumento de
identificação e pré-especificação, com inferência coerente e transparente. Se o
efeito continuar não significativo bilateralmente a 5%, o paper deverá tratar
isso como evidência imprecisa, não como resultado que precisa ser ajustado
para obter significância.

### Table 2: legibilidade

**Status**: Pendente
**Prioridade**: ALTA antes de nova circulação

A Table 2 do `paper_v4.pdf` ficou pequena demais e praticamente impossível de
ler. A tabela resume os diagnósticos compactos do SDiD do Brasil; o conteúdo é
útil, mas a apresentação atual precisa ser revista.

Ações possíveis:

1. quebrar a tabela em duas tabelas menores;
2. mover parte do conteúdo para o apêndice e deixar no corpo uma versão mais
   enxuta;
3. substituir por bullets numerados no texto e manter a tabela completa no
   apêndice;
4. ajustar layout/fonte/colunas apenas se isso resolver a legibilidade sem
   comprimir demais.

Critério de resolução: Table 2 legível no PDF renderizado em tamanho normal,
sem depender de zoom excessivo.

### C17: imagem de headlines promete 20 itens

**Status**: Pendente deliberado
**Prioridade**: BAIXA

O caption do `paper_v4.Rmd` já foi suavizado, mas a imagem
`images/table1_headlines.png` ainda contém o subtítulo "Random sample of 20
headlines with ChatGPT-assigned topic". O PDF atual ainda extrai essa frase da
imagem. O item continua visual/transparência, não causal.

Ação futura, apenas se o autor pedir ou antes de circulação final:

1. regenerar a imagem para mostrar efetivamente os 20 headlines completos; ou
2. alterar o subtítulo dentro da imagem para não prometer 20 itens.

### Rank-label frequency explícita

**Status**: Opcional
**Prioridade**: MÉDIA se o objetivo for blindar mecanismo

O paper já tem evidência de saliência por categoria de headline e evidência
oficial de uptake do cue. Ainda não há uma contagem normalizada de expressões
explícitas como `largest`, `number one`, `principal partner` sobre o total da
cobertura. Isso responderia ao M04 literal do coarse review, mas não bloqueia a
versão atual.

### Tabela completa de portabilidade da codificação cross-country

**Status**: Opcional
**Prioridade**: MÉDIA

O apêndice já tem audit de setor e audit agregado de amostra. Ainda poderia ser
adicionada uma tabela país-a-país com entrada, incumbente deslocado, duração,
saída, ties/missing e inclusão sob regras de 1/3/5 anos. Isso é útil para
parecerista metodológico, mas não é uma falha estrutural da versão atual.

### Baseline formal de continuous interdependence

**Status**: Opcional
**Prioridade**: MÉDIA/BAIXA

O paper responde à alternativa de interdependência contínua por covariáveis,
timing tests, lower-threshold placebo e diagnósticos de demanda chinesa. Ainda
não há uma tabela dedicada estilo Flores-Macias/Kreps ou Urdinez no mesmo
sample adicionando depois a entrada rank-one. Isso é uma blindagem adicional,
não uma pendência operacional.

### Materiais derivados

**Status**: Condicional
**Prioridade**: BAIXA até uso externo

Antes de usar `paper_v4_anonymous.Rmd`, slides, pacote de submissão ou materiais
externos, sincronizar com o `paper_v4.Rmd` atual. A versão ativa do manuscrito
é `paper_v4.Rmd`, não os derivados.

## Itens removidos da lista de pendências ativas

- Decidir estimando cross-country principal: resolvido como goods-only
  status-current restricted risk set.
- Migrar status-current para `targets`: resolvido.
- Refazer cross-country com resultados vindos de `targets`: resolvido no paper
  atual.
- Corrigir M05 export-destination vs public cue: resolvido no texto e no
  apêndice.
- Inserir diagnósticos SDiD completos: resolvido.
- Suavizar linguagem causal do painel cross-country: resolvido.
- Tratar BaTIS BPM5/BPM6 como pendência do paper atual: removido; a
  especificação principal é goods-only e exclui serviços antes do ranking.
