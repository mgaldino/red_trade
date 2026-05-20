# Mini revisão de literatura: potência regional

Data: 2026-05-19  
Escopo: definir um critério simples e reproduzível para marcar se o incumbente deslocado pela China era uma potência regional no painel cross-country do paper.

## Síntese do campo

A literatura de RI trata “potência regional” como uma categoria posicional, não apenas como uma lista de países grandes. O núcleo comum é: o país pertence a uma região, concentra capacidades materiais acima dos demais atores regionais, tem centralidade econômica/diplomática/segurança observável e recebe algum grau de reconhecimento regional ou extrarregional. O conceito é próximo, mas não idêntico, a “middle power”: uma potência média pode ter capacidade diplomática global sem ser o polo de uma região; uma potência regional tem saliência principalmente em um subsistema regional.

## Trabalhos-chave

| Autor(es) | Ano | Contribuição para o critério |
|---|---:|---|
| Buzan & Wæver | 2003 | A política internacional é estruturada por complexos regionais de segurança; regiões são subsistemas relevantes para hierarquias de poder. |
| Flemes | 2007 | Propõe quatro critérios: reivindicação de liderança, recursos de poder, uso de instrumentos de política externa e aceitação/recognition da liderança. |
| Nolte | 2010 | Define potência regional por pretensão de liderança, recursos materiais/organizacionais/ideacionais, influência real em assuntos regionais e reconhecimento. |
| Prys | 2010 | Diferencia formas de “regional powerhood” e alerta contra assumir liderança regional uniforme. |
| Kappel | 2011 | Em IPE, enfatiza peso econômico regional, população, comércio, investimento e oferta de bens públicos/instituições. |
| Nolte & Schenoni | 2021 | Separa status de potência regional de exercício de liderança; dois elementos mínimos são pertencer a uma região e ter parcela superior das capacidades regionais, reconhecida por outros atores. |

## Critério operacional recomendado

Para este diagnóstico, a variável não deve tentar medir liderança regional ano a ano. Ela deve capturar a saliência política de deslocar um incumbente comercial com status regional/global reconhecido. O critério recomendado é:

1. Construir uma lista pré-especificada de incumbentes que combinam capacidades materiais relevantes, centralidade regional e reconhecimento na literatura de RI/IPE.
2. Aplicar a lista ao parceiro deslocado no ano imediatamente anterior ao treatment entry/onset: `displaced_partner_{i,t0-1}`.
3. Manter dummies separadas para `displaced_us` e `displaced_g7`, porque elas capturam vínculos com a ordem liberal/Ocidental e não devem ser absorvidas conceitualmente pela categoria “potência regional”.
4. Salvar uma coluna auxiliar `displaced_regional_power_same_macroregion`, mas não usá-la como definição principal nesta rodada. Ela permite diagnosticar se o resultado depende de tratar a potência regional como status do parceiro ou como vínculo regional direto com o país tratado.

## Lista pré-especificada

Versão: `strict_pre_specified_ri_ipe_2026_05_19`

| Região/sistema | Países incluídos | Justificativa curta |
|---|---|---|
| América do Norte | USA | Superpotência e polo regional; codificada também em `displaced_us`. |
| América Latina | BRA, MEX, ARG | Brasil e México são polos regionais amplamente reconhecidos; Argentina é potência média/regional histórica no Cone Sul. |
| Europa/Eurásia | DEU, FRA, GBR, RUS, TUR | Alemanha, França e Reino Unido combinam capacidade econômica/diplomática europeia; Rússia e Turquia são polos regionais/euroasiáticos. |
| Oriente Médio/Norte da África | EGY, IRN, SAU | A literatura trata Egito, Irã e Arábia Saudita como polos regionais centrais. |
| África Subsaariana | NGA, ZAF | Nigéria e África do Sul são os casos canônicos de potência regional africana. |
| Sul da Ásia | IND, PAK | Índia é o polo regional dominante; Paquistão é potência regional/segurança nuclear no Sul da Ásia. |
| Leste/Sudeste Asiático e Oceania | JPN, KOR, IDN, AUS | Japão e Coreia do Sul são polos econômicos/segurança no Leste Asiático; Indonésia é polo do Sudeste Asiático; Austrália é potência regional no Indo-Pacífico/Oceania. |

Países deliberadamente excluídos da lista estrita incluem CAN, ITA, BEL, CHE, ARE, SGP, THA, GHA, SEN, UKR e MYS. Alguns são ricos, hubs comerciais ou aliados relevantes, mas a inclusão como potência regional ampla seria menos defensável ou já é capturada por `displaced_g7`.

## Risco e mitigação

- **Arbitrariedade da lista**: mitigada por pré-especificação, versão nomeada e critério explícito. Ainda assim, a lista deve ser tratada como diagnóstico, não como prova definitiva.
- **Sobreposição com G7/EUA**: mantida de propósito, mas os resultados devem ser lidos junto com `displaced_us` e `displaced_g7`.
- **Potência regional externa à região do país tratado**: mitigada pela coluna auxiliar de mesma macrorregião.
- **Mudança temporal de status**: a lista é estática. Para um diagnóstico preliminar isso é aceitável; uma versão de paper deveria considerar codificação temporal ou literatura por região.

## Referências consultadas

- Buzan, Barry, and Ole Wæver. 2003. *Regions and Powers: The Structure of International Security*. Cambridge University Press. https://books.google.com/books/about/Regions_and_Powers.html?id=N3LfkrrNM4QC
- Flemes, Daniel. 2007. “Conceptualising Regional Power in International Relations: Lessons from the South African Case.” GIGA Working Paper No. 53. https://ssrn.com/abstract=1000123
- Kappel, Robert. 2011. “On the Economics of Regional Powers.” In *Regional Powers and Regional Orders*. https://doi.org/10.5771/9783845238128-237
- Nolte, Detlef. 2010. “How to Compare Regional Powers: Analytical Concepts and Research Topics.” *Review of International Studies* 36(4): 881-901. https://doi.org/10.1017/S026021051000135X
- Nolte, Detlef, and Luis L. Schenoni. 2021. “To Lead or Not to Lead: Regional Powers and Regional Leadership.” *International Politics*. https://doi.org/10.1057/s41311-021-00355-8
- Prys, Miriam. 2010. “Hegemony, Domination, Detachment: Differences in Regional Powerhood.” *International Studies Review* 12(4): 479-504. https://doi.org/10.1111/j.1468-2486.2010.00957.x
