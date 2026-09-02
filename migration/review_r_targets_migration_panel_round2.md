# Revisão R independente — rodada 2

- Data: 2026-09-02
- Commit revisado: `f6d4f3c`
- Sessão independente: `01a06023-d4fb-7b72-bef2-f2e20a373139`
- Modo: somente leitura
- Execução de R, `targets` ou modelos: não
- Veredito: **PASS**
- Nota geral: **A**

## Resumo executivo

Nenhum achado acionável. O estado commitado em `f6d4f3c` resolve os oito
bloqueios da rodada 1 e mantém o ramo `full_union` lado a lado com a produção,
sem promoção antecipada.

## Verificações determinantes

- O parsing comercial agora falha de modo abortivo; schemas, valores positivos
  e chaves únicas são verificados.
- O ranking cobre todos os exportadores; `min_rank()` preserva empates, que
  recebem tratamento desconhecido.
- A união das fontes e a grade explícita 1990–2023 precedem a definição do
  tratamento e a filtragem do outcome.
- Os períodos dependem de adjacência calendária e de ano anterior observado não
  tratado.
- Risk set, suporte mínimo e exclusão posterior por outcome estão separados.
- `clean_single_spell` segue o contrato histórico: um período elegível e um
  período qualificante.
- `switching_allowed` exige o conjunto exato de anos comum, não apenas igual
  número de linhas.
- Os nomes derivados são genéricos ao limiar e funcionam para 3, 5 e 7 anos.
- O gate testa a sequência exata 1990–2023, `COD–2021`, outcome ausente,
  permanência no risk set, exclusão na etapa correta e os valores diagnósticos
  5.002 observações, 160 países e 440 períodos tratados; falhas abortam.
- Modelos, resultados dinâmicos, pré-tendência e figura candidatos dependem do
  gate e permanecem separados dos nomes de produção.
- O worktree permaneceu sem alterações durante a revisão.

## Veredito

**PASS**
