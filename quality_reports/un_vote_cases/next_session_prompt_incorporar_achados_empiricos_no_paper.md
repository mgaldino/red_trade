# /goal para próxima sessão: incorporar achados AGNU no paper

Use este prompt na próxima sessão.

## /goal

Gerar texto pronto para revisão do autor, indicando exatamente onde cada trecho deve entrar no paper, para incorporar os achados empíricos da análise Brasil-China na AGNU, 2005-2012, sem superestimar a narrativa de aproximação com a China.

O agente deve entregar uma proposta textual completa, mas não deve editar o paper diretamente. O autor revisará primeiro. Depois, em outra etapa, o texto aprovado será inserido no manuscrito.

## Skills a chamar

Use as skills nesta ordem:

1. `theory-framing` para definir o claim correto e a arquitetura conceitual.
2. `ipe-expert` para avaliar a interpretação substantiva em economia política internacional e política externa brasileira.
3. `devils-advocate` para testar overclaiming, inferência fraca, mecanismos alternativos e falsos positivos.
4. `rewrite-introduction` apenas se a proposta exigir mudanças na introdução ou no framing inicial do paper.
5. `proofread` ao final, para polir o texto pronto sem alterar o conteúdo substantivo.

## Contexto empírico

O paper argumenta que o Brasil se aproxima da China após 2009. A análise diagnóstica de votos na AGNU separou três possibilidades:

- mudança direta do voto brasileiro em direção a uma posição chinesa relativamente estável;
- realinhamento relacional do espaço de votação, no qual Brasil e/ou China mantêm votos estáveis, mas outros países mudam;
- falsos positivos de aproximação, quando a China muda para a posição brasileira.

Os outputs principais estão em:

- `quality_reports/un_vote_cases/nota_alinhamento_relacional_brasil_china_2005_2012.md`
- `quality_reports/un_vote_cases/figura_6_similaridade_brasil_china_por_tema_facets_local_linear_2005_2012.png`
- `quality_reports/un_vote_cases/figura_8_similarity_score_jitter_facet_tema_2005_2012.png`
- `quality_reports/un_vote_cases/figura_9_similarity_score_jitter_sem_tema_2005_2012.png`
- `data/processed/unvotes/brazil_china_vote_alignment_by_issue_year_2005_2012.csv`
- `data/processed/unvotes/brazil_china_vote_alignment_mechanisms_2005_2012.csv`
- `data/processed/unvotes/brazil_china_vote_similarity_score_by_resolution_2005_2012.csv`

Achado central: a aproximação pós-2009 é real, mas estreita e temática. Ela aparece sobretudo em direitos humanos. O mecanismo mais convincente é mudança direta do Brasil em direção à posição chinesa, não um realinhamento relacional amplo pró-China. Fora de direitos humanos, a evidência é limitada ou mista; alguns casos em armas/desarmamento/nuclear parecem falsos positivos porque a China se moveu para a posição brasileira.

Série agregada de voto igual Brasil-China por ano:

- 2005: 82,5%
- 2006: 81,5%
- 2007: 83,9%
- 2008: 76,0%
- 2009: 86,7%
- 2010: 87,1%
- 2011: 86,5%
- 2012: 78,9%

Por tema, a virada de 2008 para 2009 é mais visível em direitos humanos e em "outros"; Palestina/Oriente Médio já estava em convergência alta, e desenvolvimento/descolonização têm teto alto.

## Protocolo revisão-implementação

Siga um protocolo iterativo com gate de qualidade. Não encerre com texto "rascunho" se ele ainda não estiver pronto para revisão do autor.

### Etapa 1 — Diagnóstico de inserção

1. Ler o paper atual antes de propor texto.
2. Identificar seções, subtítulos, parágrafos e linhas aproximadas onde os achados AGNU podem entrar.
3. Separar o que deve entrar no texto principal do que deve ir para apêndice/nota de rodapé.
4. Explicitar quais claims atuais do paper precisam ser preservados, moderados ou removidos.

### Etapa 2 — Framing substantivo

Usando `theory-framing` e `ipe-expert`, decidir o claim final. A decisão deve escolher uma destas versões ou propor uma alternativa melhor:

1. Claim forte: aproximação geral com a China após 2009.
2. Claim moderado: aproximação concentrada em direitos humanos.
3. Claim refinado: mudança brasileira em arenas onde a posição chinesa era saliente, sem realinhamento relacional amplo.

O default deve ser o claim refinado, salvo se a leitura do paper mostrar que outro claim é mais defensável.

### Etapa 3 — Redação pronta para revisão

Produzir texto final em blocos separados, cada um com:

- seção de destino no paper;
- local de inserção;
- função retórica do trecho;
- texto pronto em inglês acadêmico;
- observação sobre figuras/tabelas associadas;
- risco interpretativo que o trecho evita.

Os blocos mínimos esperados são:

1. Um parágrafo curto para a seção empírica principal.
2. Um parágrafo para discussão de mecanismo.
3. Um parágrafo ou nota sobre escopo e falsos positivos.
4. Uma frase de transição conectando ideal points e análise resolução por resolução.
5. Caption revisada para a figura recomendada.
6. Texto de apêndice, se a evidência detalhada não couber no corpo do paper.

### Etapa 4 — Revisão crítica

Submeter a proposta textual a `devils-advocate`. A revisão deve dar nota A/B/C e apontar:

- overclaiming;
- ambiguidade causal;
- inconsistência com os achados;
- lugares em que o texto parece vender mais do que a evidência permite;
- figuras ou casos que enfraquecem a narrativa;
- o que precisa mudar para nota A.

### Etapa 5 — Iteração até A

Revisar o texto incorporando apenas críticas relevantes. Repetir revisão crítica até obter nota A ou equivalente.

Critérios para nota A:

- claim substantivo calibrado à evidência;
- distinção clara entre mudança direta do Brasil, realinhamento relacional e falsos positivos;
- texto pronto para o autor revisar sem retrabalho pesado;
- indicação precisa de onde inserir cada trecho;
- nenhuma afirmação maior que os dados;
- integração clara com a lógica causal do paper.

Se a revisão não chegar a A em duas rodadas, parar e reportar o bloqueio substantivo.

### Etapa 6 — Polimento final

Usar `proofread` para revisar gramática, clareza e estilo. Não mudar o conteúdo substantivo depois da nota A sem nova revisão crítica.

## Tarefas concretas

1. Decidir qual claim o paper deve fazer:
   - claim forte: aproximação geral com a China após 2009;
   - claim moderado: aproximação concentrada em direitos humanos;
   - claim refinado: mudança de política externa brasileira em arenas onde a posição chinesa era saliente, mas sem realinhamento relacional amplo.
2. Dizer onde isso entra no paper:
   - teoria/mecanismo;
   - seção empírica de votos na ONU;
   - robustez/diagnóstico;
   - discussão de mecanismos e escopo.
3. Escolher quais figuras usar no manuscrito e quais deixar para apêndice.
4. Propor texto curto para o paper, mas apenas depois de fixar o claim.
5. Listar casos/resoluções que merecem process tracing qualitativo.
6. Listar casos que devem ser tratados como falsos positivos porque a China se moveu para o Brasil.

## Output esperado

Produza:

- diagnóstico de risco de overclaiming;
- recomendação de framing;
- mapa de inserção por seção/parágrafo do paper;
- texto pronto, em inglês acadêmico, por bloco de inserção;
- captions prontas para as figuras recomendadas;
- indicação do que deve ir para apêndice;
- lista de casos/resoluções para process tracing;
- lista de falsos positivos em que a China mudou para o Brasil;
- log curto das rodadas de revisão e mudanças feitas até obter nota A;
- instrução final clara: "Aguardando revisão do autor antes de inserir no paper."
