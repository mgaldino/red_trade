# Tradução da versão reduzida do modelo

Data: 21 de setembro de 2026.

A tradução segue o texto colado pelo autor nesta conversa. A nota longa preexistente `toy_model_status_cue.Rmd` não foi usada para substituir escolhas da versão reduzida. O manuscrito `paper_v4.Rmd` não foi editado por esta tarefa.

## Arquivos

- Fonte do autor, preservada byte a byte: `short_version_author_2026-09-21.txt`.
- Tradução editável: `toy_model_status_cue_short_en.Rmd`.
- PDF: `../../output/pdf/toy_model_status_cue_short_en.pdf`.
- Renderização, a partir da raiz do repositório: `bash scripts/render_toy_model_status_cue_short_en.sh`.

SHA-256 da fonte do autor: `f8439dc7c2fce8a74fd1b5299125a335eb3edf6c61274b5940cb6209eb06f8b1`.

## Intervenções na tradução

- Tradução para inglês e ajustes de gramática, pontuação e expressões não idiomáticas nos trechos já escritos em inglês.
- Exclusão da segunda cópia integral e idêntica de “Consequências imediatas”. Nenhuma implicação distinta foi excluída.
- Correção de `/gt` para `>` e da composição LaTeX do bloco que interpreta os sinais de `iota`.
- Definição da macro de apresentação `\pospart{x}` como `[x]_+`, conforme a notação usada no original e na nota longa preexistente.
- Título e metadados acrescentados somente para o documento independente.
- Preservação das afirmações, hipóteses, fórmulas e provas, sem revisão substantiva. A referência `[citar gabaix]` foi traduzida para `[cite Gabaix]` e continua pendente.

A conferência independente de fidelidade cobriu integralmente a fonte e a tradução. Não encontrou omissões nem alterações materiais de sentido. O refinamento idiomático “A persistent ranking”, sugerido nessa conferência, foi incorporado. Essa verificação foi textual; não constitui auditoria matemática.

O PDF final foi compilado com R Markdown/Pandoc e XeLaTeX e teve suas quatro páginas inspecionadas visualmente, incluindo equações, desigualdades e numeração dos resultados. A checagem mecânica confirmou que o bloco removido era uma repetição integral e que permanecem um lema, uma proposição e três corolários. Não foram executadas estimações ou etapas do pipeline `targets`.

## Avaliação inicial de inserção e cortes

O lugar natural é depois da motivação inicial de “Theory and Hypotheses”, antes da discussão das implicações. Na fonte observada durante esta tarefa, essa localização já ganhou os marcadores “Beggining Formal Model” e “End Formal model”. As referências abaixo usam o início dos parágrafos porque o manuscrito estava sendo editado simultaneamente.

1. **Manter a abertura conceitual.** Ela explica por que categorias públicas podem importar e situa o mecanismo na literatura. O modelo passa então a tornar explícitas atenção, valência e implementação.
2. **Substituir os parágrafos “The mechanism has two steps” e “Secondly, the cue should affect policy through justification” por uma interpretação breve depois do resultado.** As definições de `s(q)` e `K(q)` assumem parte da função desses parágrafos. A justificativa pública continua como interpretação substantiva; o jogo não modela uma audiência que avalia justificativas.
3. **Fundir as repetições na subseção “From Attention to Selective Diplomatic Alignment”.** “When a foreign power's rise...” e “The domestic pathway works through justification” repetem a justificativa já apresentada. Preservar a explicação de por que votos na AGNU permitem ajustes visíveis e relativamente pouco custosos e conectá-la aos custos por tema.
4. **Condensar a durabilidade.** O parágrafo “The justification mechanism also implies a durability condition” e a extensão de persistência cumprem funções próximas. Basta uma discussão conjunta. O jogo estático não deriva uma trajetória temporal gradual; a frase sobre mudança gradual exige permanecer como motivação empírica ou interpretação adicional.
5. **Ajustar a hipótese direcional.** O parágrafo “The main theoretical expectation is therefore...” prevê aproximação. No modelo, aproximação requer avaliação favorável, além de uma resposta ativa; uma avaliação desfavorável permite distanciamento. Essa condição precisa ficar explícita, com a aplicação ao Brasil justificada substantivamente. O modelo também não garante, sozinho, aproximação média em uma amostra de países com avaliações heterogêneas.
6. **Economizar espaço na apresentação do modelo.** Manter no corpo as primitivas essenciais, os dois payoffs, o resultado principal e sua interpretação. As provas podem ir ao apêndice; as três implicações podem ser apresentadas em prosa. Os exemplos Canadá/Reino Unido/França-Alemanha são uma possibilidade de corte adicional se o objetivo for reduzir extensão, mas sua exclusão é uma escolha editorial do autor.

## Pontos do original a resolver antes de integrar

Estes pontos foram preservados na tradução para não transformar a tarefa em alteração do modelo:

- **Domínio da saliência:** a versão reduzida escreve `s(1)>s(0)`, mas não explicita `s(q)>=0`. Sem essa restrição, a relação entre o sinal de `theta` e o sinal da política não vale em geral. A nota longa preexistente explicitava `s(q)>0`; reinseri-la exige uma decisão sobre o texto, não uma correção de tradução.
- **Ativação versus intensidade por tema:** “Issues on which policy has already adjusted do not change” não decorre da equação (3). Com implementação ativa e resposta já positiva em módulo, aumentar `s` também aumenta a intensidade. A desigualdade da extensão identifica temas recém-ativados pelo canal da atenção, condicional à implementação; não enumera todos os temas cuja política pode mudar.
- **Notação e referência:** definir `[x]_+=max{x,0}` para o leitor e completar a referência a Gabaix. O peso `s(q)` é exógeno neste modelo, que não deriva uma escolha ótima de atenção.

Esta avaliação localiza decisões de integração. As propostas de corte e os ajustes substantivos descritos nesta avaliação não foram aplicados ao paper ou à tradução.
