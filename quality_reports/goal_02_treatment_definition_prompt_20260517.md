# Prompt operacional: Goal 2 — tratamento top trade partner vs. top export destination

Data: 2026-05-17

## Objetivo

Resolver o problema de definição do tratamento no paper v4: separar e harmonizar o uso de "top trade partner", "top export destination" e possíveis variantes de total bilateral trade/import source. A primeira entrega deve ser diagnóstica e reprodutível, sem alterar `_targets.R` nem rodar `targets::tar_make()`.

## Perguntas inferidas

- Tratamento atual no paper: China entra/ocupa a posição de número 1 na hierarquia comercial.
- Implementação atual mais provável: maior destino de exportação, a partir de `trade_data` com `exporter_iso3`, `importer_iso3` e `exports`.
- Outcome principal: distância absoluta de ideal point da AGNU em relação à China.
- Desenhos: SDiD para Brasil; `fect`/IFE com tratamento reversível para painel cross-country.
- Problema substantivo: o texto alterna entre "top trade partner" e "top export destination"; o Goal 2 exige decidir se isso é empiricamente defensável ou se a linguagem deve ser estreitada.

## Restrições do repositório

- Não alterar `_targets.R`, `_targets/` ou `_targets.yaml`.
- Não rodar `targets::tar_make()`.
- Usar R para análise estatística.
- Manter computação em script separado, preferencialmente `scripts/diagnostics/`.
- Usar `dplyr::select()` ao selecionar colunas.
- Preservar dados brutos e não sobrescrever arquivos de origem.
- Outputs em UTF-8.

## Skills/metodologia

- Usar `data-analysis-r` para implementação reprodutível.
- Usar `causal-did-identification`, `causal-did-estimation` e `causal-did-inference` como orientação metodológica: explicitar estimando, tratamento reversível, riscos de controles pós-tratamento e inferência com poucos tratados.
- Usar `review-r` apenas para revisão crítica separada.

## Separação de papéis

- Implementador: cria scripts, roda diagnósticos e gera tabelas/relatório.
- Revisor: revisa o script R e a estratégia causal depois da implementação; não edita arquivos.
- Quem implementa não revisa; quem revisa não implementa.

## Entregas esperadas

1. Script novo em `scripts/diagnostics/` que leia alvos existentes via `targets::tar_read()` e gere variantes de tratamento sem modificar o pipeline.
2. Tabela para o Brasil com o primeiro ano em que China é número 1 sob cada definição viável:
   - maior destino de exportação;
   - maior origem de importação, se os dados permitirem reconstruir via fluxos reportados por parceiros;
   - maior parceiro por total bilateral trade, se os dados permitirem;
   - rank ordinal da China;
   - share comercial da China;
   - margem da China sobre o segundo colocado.
3. Tabela cross-country com número de países tratados, anos tratados, entradas, saídas/switches e cobertura por definição.
4. Reestimação do painel `fect` para as variantes viáveis, preferencialmente com `nboots` reduzido na versão diagnóstica e com aviso claro de que resultados são triagem.
5. Reestimação ou auditoria do SDiD Brasil sob variantes viáveis; quando a variante não for implementável, explicar por quê.
6. Relatório Markdown em `quality_reports/` com:
   - contrato do desenho causal;
   - disponibilidade dos dados por definição;
   - resultados das tabelas;
   - recomendação textual: manter tratamento principal como export-destination, trocar para total-trade, ou tornar total-trade co-primary;
   - parágrafo sugerido para o paper.
7. Relatório separado de revisão R, sem edição pelo revisor.

## Critérios de aceitação

- O script roda do zero a partir dos alvos existentes sem modificar `_targets.R`.
- Não há seleção de colunas com `select()` não qualificado.
- O relatório distingue "verificável nos dados" de "não implementável com os dados atuais".
- A recomendação final deixa claro qual linguagem deve aparecer no abstract, hipóteses, notas de figura e captions.
- O relatório não transforma diagnósticos exploratórios em inferência confirmatória.
