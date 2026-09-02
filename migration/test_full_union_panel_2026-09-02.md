# Testes baratos do painel `full_union`

- Data: 2026-09-02
- Worktree: `red_trade-targets-migration`
- Branch: `codex/targets-migration`
- `targets::tar_make()`: não executado
- Modelos: não executados
- Dados brutos completos: não processados

## Teste determinístico

Comando:

```sh
Rscript --vanilla migration/test_full_union_panel.R
```

Resultado: **PASS** em todos os casos.

Casos cobertos:

1. agregação ITPD-E preserva todos os exportadores;
2. soma dos três setores de bens;
3. parsing comercial inválido aborta;
4. ranking distingue China no topo, outro parceiro no topo e empate exato;
5. master inclui países observados apenas no comércio e apenas no outcome;
6. master respeita a grade anual exata solicitada;
7. status comercial tratado sobrevive ao missing do outcome e só é excluído na
   etapa de estimação;
8. lacuna comercial interrompe duração consecutiva e elegibilidade pelo ano
   anterior;
9. `clean_single_spell` exige exatamente uma entrada elegível e uma entrada
   qualificante;
10. `switching_allowed` seleciona o conjunto exato de anos comum;
11. falha de validação aborta o pipeline candidato.

Mensagem final observada:

```text
ALL FULL-UNION PANEL TESTS PASSED
```

## Manifesto estático de `targets`

Foi carregado apenas o manifesto; nenhum alvo foi construído.

Resultado:

```text
MANIFEST_OK targets=241 candidate_targets=3
```

Os três nomes explicitamente verificados foram:

- `china_top_m2_goods_full_union_status_validation_gate`;
- `china_top_m2_goods_full_union_status_model_bundle`;
- `plot_china_top_m2_goods_full_union_dynamic`.

## Observação de ambiente

O shell iniciou R em locale `C`. O teste selecionou `pt_BR.UTF-8` apenas dentro
do processo R antes de carregar o arquivo histórico `scripts/functions.R`.
Essa seleção não altera o sistema nem o repositório.
