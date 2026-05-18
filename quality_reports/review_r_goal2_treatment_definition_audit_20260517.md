# Revisão R independente: `audit_goal2_treatment_definitions.R`

Data: 2026-05-17

## Q&A / Escopo

Q: O revisor editou arquivos ou rodou R?

A: Não. A revisão foi estática, sem `Rscript`, sem código inline e sem `targets::tar_make()`.

Q: O script podia ser executado novamente antes das correções?

A: Não como diagnóstico válido completo. Ele podia rodar parcialmente, mas a parte SDiD falhava por dependência implícita.

## Nota geral

C+

## Problemas críticos

1. **SDiD quebrado por dependência não carregada.** O script chamava `simple_fit()`, que depende de `panel.matrices()` em `scripts/functions.R`. Fora do pipeline `targets`, `synthdid` não estava anexado; a execução anterior retornou `could not find function "panel.matrices"`. Correção mínima: carregar `synthdid` no script ou qualificar `synthdid::panel.matrices()` nas funções.

2. **Resultados `fect` com `nboots = 100` não devem ser tratados como inferência final.** Isso é aceitável como triagem, mas perigoso para o paper. O relatório precisa dizer explicitamente que esses p-valores são provisórios e não comparáveis ao alvo existente com 500 boots.

3. **A comparação causal muda estimando e amostra ao mesmo tempo.** As variantes mantêm o universo condicionado ao benchmark EUA. Como diagnóstico de harmonização isso é defensável, mas não identifica sozinho o efeito puro de cada definição de tratamento.

## Melhorias importantes

- Corrigir warnings de `dplyr::if_else()` com `min()` para países sem entrada de tratamento.
- Evitar sobrescrever outputs fixos ou registrar metadata suficiente da execução.
- Evitar data hard-coded.
- O uso de `dplyr::select()` está adequado no script.

## Veredito

Não aprovado para nova execução substantiva antes das correções mínimas. Depois de resolver `synthdid`, reduzir os warnings e rotular `nboots=100` como preliminar, o script pode ser executado como diagnóstico.
