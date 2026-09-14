#!/usr/bin/env python3
"""Consolidate delivery records; no analytical computation."""
from pathlib import Path
import json, hashlib, collections, difflib, re
P=Path(__file__).resolve().parent
R=P.parents[2]
T=Path('/private/tmp/refine-review-20260914')
d=json.loads((P/'master.json').read_text())
integration={x['item']:x for x in json.loads((P/'integration.json').read_text())['items']}
short={2:'Documentados universo de 14 casos, sobreposição com a amostra atual, filtro dos nove casos exibidos e categorias.',4:'Documentado procedimento preservado de recuperação; auditoria numérica completa proposta como targets.',6:'Explicitados baselines, interações, padronização e absorção dos termos inferiores.',7:'Separada configuração observável no código da proveniência histórica não preservada.',8:'88% identificado como concordância amostral não ponderada; precisão, recall e representatividade não confundidos.',11:'Explicitados janelas, horizontes, contrafactuais e caráter sugestivo dos contrastes temporais.',15:'Especificado quadro auditável país–ano e quatro targets; sem produzir nova tabela.',18:'Separados erro-padrão placebo, ranks exaustivos e aproximação normal.',20:'Definidos pesos positivos das unidades tratadas e períodos posteriores.',21:'Definidos votos, distâncias, abstenções e exclusões; preservados efeitos fixos existentes.',22:'Explicitadas interação, escala e natureza condicional da comparação 2 × 2; não rejeição não é equivalência.',25:'Nota de entendimento com álgebra, exemplo conceitual, evidência arquivada e alternativas; nenhuma especificação modificada.',27:'Distintas mudança da média, volatilidade anual e aproximação brasileira.',29:'Caption identifica ATT ajustado e seu contraste pré-tratamento ponderado.',30:'Corrigida a direção da hierarquia dos destinos de exportação.',31:'Esclarecidos valor absoluto, suporte empírico e dependência entre covariáveis; principal sem covariáveis preservada.',32:'Esclarecidos objetivo dos pesos temporais e uso de resultados dos controles no pré e pós.',33:'Denominador corrigido de mediana para média; 42% conferido independentemente.',34:'Médias BSV e UNGA-DM atribuídas corretamente.',35:'Atribuição bibliográfica compartilhada corrigida com base em fontes primárias.',36:'Atribuição bibliográfica compartilhada corrigida com base em fontes primárias.',37:'Diagnóstico não sustentado; citação de Strüver mantida.',38:'Removida somente a atribuição ambígua a MacDonald e Parent; definição teórica preservada.'}
labels={'CONFIRMED':'Procedente','PARTIAL':'Parcialmente procedente','REFUTED':'Não sustentado'}
manifest=json.loads((P/'delivery_manifest.json').read_text())
old_lines=(P/'baseline/paper_v4.Rmd').read_text().splitlines()
new_lines=Path(manifest['manuscript']['path']).read_text().splitlines()
ops=difflib.SequenceMatcher(None,old_lines,new_lines,autojunk=False).get_opcodes()
def current_locations(evidence):
 result=[]
 for item in evidence:
  found=re.search(r"paper_v4.Rmd:(\d+)",item)
  if not found:continue
  old=int(found.group(1))-1
  for tag,a,b,c,e in ops:
   if a <= old < b:
    line=c+old-a+1 if tag=='equal' else c+1
    loc={'path':manifest['manuscript']['path'],'line':line,'excerpt':new_lines[line-1][:220],'baseline_location':item,'mapping':'equal line' if tag=='equal' else 'changed block start'}
    if loc not in result:result.append(loc)
    break
 return result
for x in d['items']:
 x['owner']={'corpus_votes':'corpus_votes_bibliography','bibliography_high':'corpus_votes_bibliography','audit_table':'local_fixes'}.get(x['owner'],x['owner'])
 n=x['item'];x['current_locations']=current_locations(x.get('evidence',[]));x['diagnosis_portuguese']=labels[x['diagnosis']];x['solution']=short[n]
 x['changed_files']=[] if n==37 else ([str(P/'domain_note.md'),str(T/'build/item25.pdf')] if n==25 else ([] if n==15 else [manifest['manuscript']['path'],manifest['paper_pdf']['path']]))
 x['independent_review']=['review_documentation.md']
 if n in [2,4,6,7,8,11,15,18,20,21,22,25,27,29,31,32]:x['independent_review'].append('review_methods_final_candidate.md')
 if n in [6,27]:x['independent_review'].append('review_documentation_delta.md')
 if n in [33,34]:x['independent_review'].append('review_abstract.md')
 x['checks']=list({json.dumps(v,sort_keys=True):v for v in list(x.get('checks') or [])+['Final mechanical check, source diff, and rendered-page inspection; see delivery_manifest.json and visual QA records.']}.values())
 x['status']='Correção concluída na versão revisada'
 x['authorization_needed']=[];x['limitation']='Sem nova estimação; conclusões limitadas às evidências existentes.'
 if n in [4,7,8]:
  x['status']='Documentação corrigida; auditoria/proveniência adicional pendente'
  x['authorization_needed']=['Implementar e executar somente os targets de auditoria especificados em pending_authorizations.md; nova codificação humana exige decisão separada.']
  x['limitation']='Resultados novos não inseridos fora do grafo; logs históricos e probabilidades de inclusão ausentes não podem ser reconstruídos por suposição.'
 if n==15:
  x['schema_owner']={'name':'cross_country','model':'gpt-5.6-sol','effort':'xhigh'}
  x['dependencies']=['Sol xhigh defines schema and rules before Luna xhigh assembles target-table proposal.']
  x['status']='Especificação entregue; tabela ampliada pendente'
  x['authorization_needed']=['Implementar e executar os quatro targets propostos; não reestimar modelos.']
  x['limitation']='Tabela 23 original preservada; quadro ampliado ainda não produzido.'
 if n==25:
  x['status']='Entendimento entregue; decisão do autor'
  x['authorization_needed']=['Escolher se deseja manter a principal ou autorizar uma sensibilidade futura.']
  x['limitation']='Nenhum efeito fixo acrescentado ou modelo reestimado; resultados de sensibilidade citados já estavam arquivados.'
 if n==37:
  x['status']='Comentário não sustentado; texto preservado'
  x['limitation']='Distinguida a versão publicada de 2016 de outro estudo de 2017; direção do argumento não equivale a identificação causal.'
 if n==2:x['limitation']='A auditoria legada não cobre 22 países tratados atuais; janelas legadas preservadas e declaradas.'
 if n==27:x['limitation']='A redação final foi verificada contra IdealPointAll, efetivamente plotado na Figura 8. Resumos antigos de Q50.All nos dossiês não devem ser atribuídos à série plotada; ver review_documentation_delta.md e orchestrator_decisions.md.'
 if n==31:x['reasoning']='O código usa valor absoluto, mas no suporte observado todos os valores de poder dos países são menores ou iguais ao dos EUA. A revisão metodológica independente confirmou a dependência linear sob as transformações efetivamente usadas e a preservação da principal sem covariáveis.'
 if n==31:x['limitation']='Dependência observada demonstrada no suporte efetivo; coeficiente não zero não estabelece identificação independente. Principal não usa covariáveis.'
 x['integration_record']=integration.get(n)
 x['promotion_status']=manifest['canonical_promotion']
d['adjudication_counts']=dict(collections.Counter(x['diagnosis'] for x in d['items']))
d['delivery']=manifest
(P/'master.json').write_text(json.dumps(d,ensure_ascii=False,indent=2)+'\n')
lines=['# Matriz de resposta aos 23 itens selecionados','', 'A classificação se refere ao diagnóstico sobre a referência congelada. O estado descreve o que foi concluído na versão revisada e o que continua pendente. A seleção do comentário não implicou sua aceitação.','',f"**Entrega canônica:** {manifest['canonical_promotion']}",'','| Item | Diagnóstico | Resultado e estado |','|---:|---|---|']
for x in d['items']:lines.append(f"| {x['item']} | {x['diagnosis_portuguese']} | {x['solution']} **{x['status']}** |")
for x in d['items']:
 lines += ['',f"## Item {x['item']}",'',f"**Comentário original (estados nele citados pertencem ao parecer recebido):** {x.get('comment','')}",'',f"**Diagnóstico:** {x['diagnosis_portuguese']}. {x.get('reasoning','')}",'',f"**Responsável:** {x['owner']} — {x['model']} / {x['effort']}.",'',f"**Solução:** {x['solution']}",'',f"**Localização atual:** {x['current_locations']}",'',f"**Evidências na referência congelada e produtores:** {'; '.join(x.get('evidence',[]))}",'',f"**Verificações:** {x['checks']}",'',f"**Revisão independente:** {', '.join(x['independent_review'])}; decisões em orchestrator_decisions.md.",'',f"**Arquivos:** {x['changed_files']}",'',f"**Dependências e autorização:** {x['authorization_needed']}",'',f"**Estado:** {x['status']}. {x['limitation']}"]
(P/'master.md').write_text('\n'.join(lines)+'\n')
print(d['adjudication_counts'])
