# Revisão delimitada dos comentários Refine.ink

Escopo: itens 2, 4, 6, 7, 8, 11, 15, 18, 20, 21, 22, 25, 27, 29, 30, 31, 32, 33, 34, 35, 36, 37 e 38. Nenhum comentário geral.

## Referência e papéis

`baseline/` preserva o Rmd e o PDF de referência e uma extração nova. `baseline_manifest.json` registra Git, data e SHA-256. O estado Git antes de criar este diretório era limpo. `protected_reference_hashes.json` permite verificar que as definições e metadados do pipeline foram preservados.

`master.json` e `master.md` são o registro mestre. `delegation_plan.md` documenta responsáveis, modelos e esforços. Especialistas adjudicam e propõem em arquivos próprios; o integrador concentra a edição do manuscrito. Revisores distintos verificam os bytes finais contra fontes e resultados.

A adjudicação é delimitada aos comentários selecionados. Não se usa contrato argumental histórico como certificação da versão atual. Veredictos CONFIRMED, PARTIAL, REFUTED e UNRESOLVED correspondem a procedente, parcialmente procedente, não sustentada e inconclusiva; já resolvida exige evidência atual de resolução.

## Limites

Não há autorização para alterar/executar targets, reestimar modelos, executar classificação por API, alterar dados brutos, encerrar processos ou remover locks, commitar, publicar ou comunicar a terceiros. Cálculos novos destinados ao manuscrito são especificados como targets antes de qualquer implementação. O item 25 é exclusivamente explicativo.

## Reprodução da apresentação

Do diretório raiz do repositório, após a integração autorizada:

```sh
LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 OMP_NUM_THREADS=1 Rscript --vanilla reports/refine_ink_review_paper_v4_2026-09-14/execution/render_revision.R
python3 reports/refine_ink_review_paper_v4_2026-09-14/execution/check_revision.py
```

O renderizador usa os resultados já existentes, gera um PDF em `build/` e registra sessão e avisos. A verificação Python confere somente integridade de arquivos protegidos, diff, referências e gatilho do abstract. Inspeção estática, verificação numérica, revisão metodológica independente e inspeção visual são registradas separadamente; nenhuma substitui reestimação ou validação empírica nova.
