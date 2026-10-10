# Painel Legislativo 2026 — plano

Painel público e interativo das eleições legislativas de 2026 (1º turno,
04/10/2026) nas 27 UFs: **Senador, Deputado Federal e Deputado Estadual**
(Distrital no DF), com hemiciclos de composição por partido/federação.

Base:
- **Dados e regras**: `C:\Users\felip\Documents\Dashboard Pernambuco 2026`
  (pipeline em R, TSE 2026, partidos/federações, eleitos/suplentes, fotos,
  LISA no navegador).
- **Visual e arquitetura de site**: `painel-eleicoes-2026/` (clone, só
  referência): mapa Leaflet em tela cheia, painel flutuante, tema escuro,
  site estático multiarquivo (JSON/TopoJSON por UF, carregados sob demanda),
  GitHub Pages.

## Decisões

| Tema | Decisão |
|---|---|
| Cargos | Só legislativo: Senador, Dep. Federal, Dep. Estadual/Distrital. Sem Presidente/Governador (evita o 2º turno). |
| Candidatos — deputados | **Eleitos + os 3 primeiros suplentes de cada lista** (partido ou federação, por UF e cargo; ordem = votos nominais). Decidido na discussão de economia de dados: todos os suplentes eram 88% dos candidatos e das fotos; os 3 primeiros cobrem quem tem chance real de assumir. |
| Candidatos — senador | **Todos** (~200 no país). |
| Votos por partido/federação | **Todos os candidatos + legenda**, somados no pipeline e exportados só como total por partido × unidade (bate com o oficial do TSE). |
| Geografia | Município + micro/meso/UF (base, dados munzona); **bairros e locais de votação** numa fase posterior (dados por seção, UF a UF). |
| Hemiciclo do Senado | 81 cadeiras: 54 eleitos em 2026 + 27 eleitos em 2022, todos pelo **partido da eleição**; cadeiras renovadas em destaque. |
| Ordem no hemiciclo | Espectro **esquerda → direita**, por tabela versionada em `data-raw/ref/` com fonte citada (revisão do usuário). |
| Recursos do painel PE | Fotos + card do candidato. (Sem perfil do eleitorado, sem tabela completa e ficha de município por ora.) |
| Saída | Site estático multiarquivo (não HTML único — não escala para 27 UFs). |
| LISA | Calculado no navegador (`lisa.js` do painel PE), com vizinhança queen exportada por UF. |
| Repositório | Git novo na raiz de `Dashboard-legislativo-2026/`; `painel-eleicoes-2026/` fica fora do git. |

## Economia de dados (decidido em 10/10/2026)

Medição feita com os dados reais de 2026: a votação pesa pouco; o mais
pesado é a geometria municipal.

| Tema | Decisão |
|---|---|
| Votação (Fase 3) | **Um arquivo por UF** com só votos inteiros por município (partidos com todos os votos + legenda, candidatos exibidos, totais de válidos). Percentuais, agregação micro/meso/UF, líder e LISA calculados no navegador. Brasil inteiro: ~10 MB brutos / ~3,5 MB gzip; carrega só a UF vista (MG, a maior, ~0,6 MB gzip). |
| Visão "Brasil" | **Município**, geometria nacional (~1,65 MB gzip) carregada só quando "Brasil" é escolhido; numa UF, só a geometria dela. |
| Card do candidato | **Arquivo de candidatos por UF compartilhado** por mapa e hemiciclo, carregado no clique. `composicao.json` fica só com o essencial de cada cadeira (sem redes/ocupação/etc.). |
| Bairros e locais (Fase 5) | **Piloto nas 27 capitais**; ampliar depois. |
| Suplentes | Eleitos + 3 primeiros suplentes por lista (ver Decisões). Fotos 71 MB -> 17,5 MB; histórico do git reescrito para não carregar as fotos removidas. |

## Navegação

**Modelo de tela (decisão do usuário, evita retrabalho):** igual ao clone —
**um único mapa em tela cheia que muda conforme os filtros** do painel
flutuante. Nada de várias seções/mapas empilhados com scroll como no painel
de PE. O hemiciclo ocupa o mesmo espaço do mapa (troca de visualização no
painel), não é uma seção a mais da página.

**Aba Mapa** — Cargo → UF (ou Brasil) → Unidade → Modo → Partido/Candidato,
com alternância Partido | Federação. Modos: quem lidera (partido/federação),
partido contínuo, candidato contínuo, LISA. Card com foto ao selecionar
candidato.

**Aba Composição** — Casa: Câmara (513, com destaque opcional da bancada de
uma UF), Senado (81), Assembleia (por UF; CLDF no DF). Hover na cadeira =
nome, foto, votos; clique no partido destaca cadeiras e leva ao mapa dele.
SVG próprio (arcos concêntricos), sem dependência externa.

## Fases

| # | Fase | Entrega |
|---|---|---|
| 0 | Bootstrap | Pastas, `renv`, git, `CLAUDE.md`; reaproveitar `linkador_bases.xlsx` e cores |
| 1 | Candidatos nacional | `consulta_cand_2026` (27 UFs) + Senado 2022; eleitos por Casa; federações; cores; classificação ideológica |
| 2 | Hemiciclos | JSON de composição (Câmara, Senado, 27 assembleias) + aba Composição |
| 3 | Votos por município | munzona 2026: partido (todos + legenda) e candidato (eleitos/suplentes; senador todos), 27 UFs |
| 4 | Mapa nacional | Front do clone estendido: proporcionais, Partido/Federação, LISA no navegador, card/fotos |
| 5 | Bairros e locais | piloto nas 27 capitais: votação por seção UF a UF (processa e descarta o bruto), locais geocodificados, bairros com malha IBGE |
| 6 | Publicação | GitHub Pages; checar tamanho de `output/` e política dos tiles |

## Riscos

- Bairros/locais nacionais: dezenas de GB brutos e geocodificação pesada —
  isolado na Fase 5, carregamento por município no front.
- "Eleito" pode mudar (sub judice, retotalização): pipeline reexecutável,
  data dos dados visível no painel.
- Classificação ideológica é subjetiva: fonte citada e revisada pelo usuário.

## Em aberto

- Título definitivo do painel (provisório: "Painel Legislativo 2026").
