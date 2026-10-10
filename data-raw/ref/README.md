# data-raw/ref

Tabelas de referência pequenas, editadas à mão e versionadas no git.

## `partidos.csv`

Uma linha por partido com candidato em 2026 (mais o PSC, que só aparece no
Senado, por um senador eleito em 2022). O pipeline para se aparecer partido
fora desta tabela.

| Coluna | Conteúdo |
|---|---|
| `sigla` | Chave: `SG_PARTIDO` exatamente como no TSE em 2026 (ex.: `PCDOB`, `UNIÃO`). É a sigla, não o número, porque números mudam entre eleições (o 20 era do PSC em 2022 e é do PODE em 2026). |
| `rotulo` | Sigla de exibição no painel. |
| `nr_2026` | Número do partido em 2026 (vazio se não concorreu). |
| `cor` | Cor hex. Base: cor nacional do partido (pt.wikipedia `Predefinição:Cor de partido político/BRA`, en.wikipedia `Module:Political party`), com tons ajustados para separar partidos parecidos no mapa (herdada do painel de Pernambuco). |
| `ideologia` | Posição esquerda (0) → direita (10). Ordena o hemiciclo. |
| `metodo_ideologia` | `tabela`: média de 2022 na Tabela 1 da fonte. `renomeado`: partido que só mudou de nome, herda o valor da sigla antiga. `fusao`: média aritmética das siglas fundidas. `estimado`: fora da pesquisa, posição definida pelo usuário (MISSÃO = junto ao NOVO). `pendente`: fora da pesquisa, sem valor ainda. As regras de renomeação e fusão são as dos próprios autores (seção "Resultados" da fonte). Incorporação (ex.: PSC → PODE, PROS → SOLIDARIEDADE) mantém o valor do partido que incorporou, também pela regra dos autores. |
| `obs` | De onde veio o valor quando não é leitura direta da tabela. |

**Fonte da posição ideológica**: BOLOGNESI, Bruno; RIBEIRO, Ednaldo; CODATO,
Adriano; SILVA, Bruno Fernando da. O desaparecimento do centro ideológico no
sistema partidário brasileiro: a classificação mais atualizada dos experts.
*Opinião Pública*, Campinas, v. 31, e31120, 2025. Tabela 1, coluna "2022
(média)" (survey com cientistas políticos, escala de 0 a 10).
<https://periodicos.sbu.unicamp.br/ojs/index.php/op/article/view/8682072>.
A versão anterior (só a rodada de 2018) é Bolognesi, Ribeiro & Codato,
*Dados* 66(2), 2023.

## `federacoes.csv`

`nr` (`NR_FEDERACAO` do TSE) → sigla curta, nome e cor. A composição (quais
partidos) vem do TSE, não desta tabela. A posição ideológica da federação é
calculada no pipeline como a média simples dos partidos membros (o survey não
classifica federações).

## `linkador_bases.xlsx`

Crosswalk nacional de municípios (5.570), fornecido pelo usuário (veio do
`painel-eleicoes-2026`): `id_TSE` casa com o código de município do TSE e
`id_munic_7` é o código IBGE. Usado a partir da Fase 3.
