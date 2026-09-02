# Revisão R independente: painel mestre e tratamento no `targets` — rodada 1

**Data:** 2026-09-02  
**Sessão independente:** `01a06019-d25a-77b1-93cd-94b5ed60cce4`  
**Escopo:** `_targets.R` e `scripts/functions_targets_migration.R`  
**Modo:** somente leitura; nenhum target, modelo ou pipeline executado  
**Veredito:** **FAIL**

## Achados que bloquearam o PASS

1. A tabela de validação não abortava a execução quando uma invariante falhava.
2. O ramo corrigido ainda não alimentava estimações paralelas, resultados ou figuras.
3. O gate `COD–2021` não provava que a linha continuava tratada e elegível no
   conjunto de risco antes de ser excluída por outcome ausente.
4. A regra `clean_single_spell` havia sido endurecida sem adjudicação explícita.
5. `switching_allowed` igualava apenas o número de linhas, não o conjunto exato
   de anos.
6. O gate da grade não testava diretamente a sequência 1990–2023.
7. Falhas de parsing comercial eram contadas, mas não faziam o pipeline abortar.
8. Nomes de campos específicos a cinco anos eram reutilizados nos limiares de
   três e sete anos.

## Aspectos aprovados conceitualmente

- Ranking calculado para todos os exportadores do insumo bruto.
- Empates exatos preservados por `min_rank()` e convertidos em status desconhecido.
- Grade explícita país × ano, com adjacência calendária.
- Tratamento e durabilidade definidos apenas pela fonte comercial.
- Outcome aplicado somente na seleção da amostra de estimação.
- Lógica principal do conjunto de risco compatível com o diagnóstico `full_join`.

Uma nova revisão deve avaliar integralmente o código corrigido; este parecer não
cobre mudanças posteriores.
