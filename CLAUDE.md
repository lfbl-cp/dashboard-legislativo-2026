# Painel Legislativo 2026 — CLAUDE.md

## Propósito

Painel público e interativo das eleições legislativas de 2026 (1º turno,
04/10/2026) nas 27 UFs: Senador, Deputado Federal e Deputado Estadual
(Distrital no DF), com resultado por município e hemiciclos da composição
por partido/federação (Câmara, Senado e as 27 Assembleias). Plano de fases e
decisões em `PLANO.md`.

Combina dois projetos anteriores do usuário:
- **Dados/regras**: `C:\Users\felip\Documents\Dashboard Pernambuco 2026`
  (pipeline R sobre TSE 2026, partidos/federações, eleitos/suplentes, fotos,
  LISA no navegador via `www/lisa.js`). Saída lá é um HTML único -- não
  escala para 27 UFs, não copiar esse formato.
- **Visual/arquitetura de site**: `painel-eleicoes-2026/` (clone, fora do
  git, só referência; tem seu próprio `CLAUDE.md` com muitas lições de
  front-end e geo -- vale ler antes das Fases 3-4).

## Decisões fixas (do usuário)

- **Uma tela só: um único mapa em tela cheia que muda conforme os filtros**
  do painel flutuante (igual ao clone). Nunca várias seções/mapas com scroll
  como no painel de PE. O hemiciclo ocupa o mesmo espaço (troca de
  visualização), não é seção extra.
- Só cargos legislativos (sem Presidente/Governador, sem 2º turno).
- Deputados: dados por candidato **só de eleitos + os 3 primeiros suplentes
  de cada lista** (lista = federação ou partido isolado, por UF e cargo;
  ordem dos suplentes = votos nominais, como na totalização do TSE).
  Decidido na discussão de economia de dados (todos os suplentes eram 88%
  dos exibidos e das fotos). Senador: todos. Totais de partido/federação somam **todos os candidatos + legenda**
  (calculado no pipeline, exportado só como total).
- Senado no hemiciclo: 81 cadeiras = 54 eleitos em 2026 + 27 eleitos em
  2022, **pelo partido da eleição** (não partido atual nem suplente em
  exercício).
- Ordem no hemiciclo: esquerda→direita pela classificação de **Bolognesi
  et al.** (Opinião Pública, 2025, média 2022) -- ver
  `data-raw/ref/README.md` para fonte e regras de renomeação/fusão.
- Modo federação: cada partido vai para a federação **de 2026** a que
  pertence (inclusive senadores de 2022).
- Geografia: município + micro/meso/UF; bairros e locais de votação numa
  fase posterior.
- Recursos trazidos do painel de PE: fotos + card do candidato.

## Estrutura

```
R/                 funções, uma etapa por arquivo numerado; só definem
                   funções, nunca rodam nada ao dar source()
pipeline/          run_pipeline.R -- orquestração (--etapa=...)
data-raw/ref/      tabelas de referência editadas à mão (partidos, federações,
                   linkador de municípios) -- ver README lá
data/raw/          ZIPs/CSVs do TSE (cache, gitignored)
data/processed/    rds intermediários (gitignored)
output/            o que o site serve (versionado): fotos/, depois JSON/TopoJSON
frontend/          HTML/CSS/JS estático (Fase 2+)
tests/testthat/    testes
```

## Comandos

```
Rscript pipeline/run_pipeline.R                        # tudo
Rscript pipeline/run_pipeline.R --etapa=candidatos     # uma etapa
Rscript -e "testthat::test_dir('tests/testthat')"      # testes (da raiz)
Rscript tests/qa_frontend.R [pasta]                    # QA do front no Chrome headless
Rscript -e "servr::httd('.', port = 8000)"             # servidor local -> /frontend/
```

`file://` não funciona (o `fetch` de `../output/` é bloqueado). Não há
Python nem Node na máquina; servidor e QA são em R (`servr`, `chromote`).
No QA, o servidor roda num processo à parte (`processx`): o `servr` em modo
daemon depende do loop de eventos da sessão, que o `chromote` bloqueia
(`Page.navigate` estoura o tempo). Para o `chromote` achar o navegador:
`CHROMOTE_CHROME="C:/Program Files/Google/Chrome/Application/chrome.exe"`.

R 4.6.1 (`C:\Program Files\R\R-4.6.1`), pacotes na biblioteca do usuário.
`renv.lock` só **registra** as versões (snapshot da biblioteca do usuário);
o projeto não ativa biblioteca renv própria (sem `.Rprofile`) -- o clone
documenta várias dores de binário Windows com renv; evitar até precisar.

## Dados do TSE -- o que já se sabe

- CDN `cdn.tse.jus.br/estatistica/sead/...` exige User-Agent de navegador
  (403 sem). Funcionando em out/2026 (sem bloqueio de defeso).
- `consulta_cand_{ano}.zip`: um CSV por UF + `_BR` (Presidente) + `_BRASIL`
  (concatenação, não usar). Traz CPF, e-mail e título de eleitor -- o
  pipeline lê só `COLUNAS_CANDIDATO` (`R/03_candidatos.R`), dado pessoal
  nunca entra. `SQ_CANDIDATO` sempre como texto (não cabe em int32).
- `DS_SIT_TOT_TURNO` 2026: ELEITO (senador), ELEITO POR QP, ELEITO POR
  MÉDIA, SUPLENTE, NÃO ELEITO, ausente (sem totalização). Deputado Distrital
  é CD_CARGO 8, tratado como "estadual".
- Partido é chaveado por **sigla**, não número (o 20 era PSC em 2022, é PODE
  em 2026). PSC só existe nos dados por causa de Cleitinho (MG, Senado 2022).
- Fotos: `foto_cand{ano}_{UF}_div.zip`, arquivos `F{UF}{SQ}_div.jpg` (161x225).
  Os de 2022 somam ~770 MB para só 27 fotos -- não usados: os senadores de
  2022 vêm da API de dados abertos do Senado (`senador/lista/legislatura/57`,
  titular com mandato iniciado na 57ª, 1 por UF, casado por UF e conferido
  por nome no log), recortados para 161x225 com `magick`.
- `votacao_candidato_munzona_2026.zip`: 445 MB, um CSV por UF (3,2 GB
  descompactados; SP 884 MB, MG 718 MB) + `_BR` + `_BRASIL` (não usar). Traz
  `QT_VOTOS_NOMINAIS_VALIDOS` por candidato x município x zona e também
  `DS_SIT_TOT_TURNO`. Só voto nominal -- legenda vem de outro arquivo
  (votação por partido, Fase 3). `R/06_votos.R` processa UF a UF (extrai
  para temporário, lê só as colunas usadas, soma zonas, apaga o CSV), cache
  por UF em `data/processed/votos_uf/`. 5,86 milhões de linhas candidato x
  município no total.

## Estado atual

- **Fase 0 (bootstrap)** completa: git (`main`), estrutura, `.gitignore`,
  `renv.lock`, referências.
- **Fase 1 (candidatos nacional)** completa: etapas `candidatos` e `fotos`.
  Validado: Câmara 513, Senado 81 (2 de 2026 + 1 de 2022 em cada UF), 27
  Assembleias com o tamanho constitucional (CF art. 27, total 1.059);
  exibidos e fotos: ver economia de dados abaixo. MISSÃO (fora da pesquisa) posicionado junto ao NOVO por decisão
  do usuário (`metodo_ideologia = estimado`).
- **Fase 2 (hemiciclos)** completa:
  - Etapa `composicao` -> `output/composicao.json` (29 Casas, 1.653
    cadeiras, ~710 KB; metade disso são links de redes sociais -- ver
    pendência de economia de dados abaixo). Redes normalizadas na origem
    (`limpar_url_rede()`: minúsculas, sem query de rastreamento, até 6,
    redes conhecidas primeiro). Coligação "FEDERAÇÃO" do TSE vira vazio.
  - Front-end (`frontend/`): abas Mapa | Composição; o hemiciclo ocupa o
    lugar do mapa. `hemiciclo.js` = layout próprio (arcos concêntricos,
    busca binária do espaçamento, cadeiras por fileira proporcionais ao
    arco, ordenadas por ângulo e preenchidas na ordem dos grupos).
    `composicao.js` = Casa/UF, destaque de bancada (Câmara/Senado; legenda
    passa a contar só a bancada), Partido|Federação, clique na legenda
    destaca o grupo, clique na cadeira abre card (foto, partido,
    federação, situação, dados, redes), tooltip no hover. Senado: cadeira
    vazada = eleito em 2022. Estado na URL
    (`#aba=composicao&casa=assembleia&uf=PE&agrupar=federacao`).
  - Mapa-base claro trocado de OSM para Esri World Light Gray (a política
    de uso dos tiles do OSM não admite tráfego alto -- ver clone).
  - Mapa ainda só com mapa-base (Fase 4); aba padrão é Composição.
  - Verificado com `tests/qa_frontend.R`: 11 cenários sem erro de JS/HTTP,
    contagem de cadeiras = tamanho da Casa em todos, 27 vazadas no Senado,
    card e tooltip funcionando; capturas conferidas visualmente (desktop
    escuro/claro, celular 390px).
- **Economia de dados (decidida com o usuário; tabela completa em
  PLANO.md)**:
  - Decidido: deputados exibidos = eleitos + 3 primeiros suplentes por
    lista. Nova etapa `votos` (entre `candidatos` e `fotos`) ordena a
    suplência por votos e redefine `exibir`; `fotos` apaga as de quem
    saiu. Exibidos 13.058 -> 3.211 (1.572 deputados eleitos, 1.293
    suplentes, 346 senadores); fotos 71 MB -> 17,5 MB; 3.210 com foto (o
    único sem é candidatura ao Senado sem totalização, sem foto no TSE).
    Teste: nenhum suplente supera o eleito menos votado da lista; 1º
    suplente = mais votado. 21 testes passando.
  - Histórico do git reescrito (filter-branch) para as ~9.800 fotos
    removidas nunca terem entrado: `.git` de 72 MB para 18 MB.
  - Votação (Fase 3): **um JSON por UF** só com votos inteiros por
    município (partidos = nominal + legenda; candidatos exibidos; totais
    de válidos); %, agregação micro/meso/UF, líder e LISA no navegador.
    Medido: candidatos exibidos 863 mil pares candidato x município (7,2 MB
    brutos / 2,5 MB gzip no país), partidos 310 mil pares (2,7 / 1,0 MB).
    Não seguir o modelo do clone (um arquivo pré-calculado por
    cargo x unidade x candidato).
  - Visão "Brasil": por município, geometria nacional (~1,65 MB gzip)
    só quando escolhida.
  - Card do candidato: arquivo de candidatos por UF compartilhado por mapa
    e hemiciclo, carregado no clique; `composicao.json` deve ficar só com
    o essencial da cadeira (hoje ainda tem tudo -- ajustar na Fase 3/4).
  - Bairros/locais (Fase 5): piloto nas 27 capitais.
- **Fase 3 (votos por município)** completa -- etapas `geografia` e
  `exportar`:
  - Malha **2025** do geobr (5.571 municípios): a de 2022 não tem Boa
    Esperança do Norte (MT, instalado em 2025), que vota em 2026. O
    linkador do usuário (5.570) é complementado por
    `data-raw/ref/linkador_complemento.csv` (TSE 73709 -> IBGE 5101837);
    o xlsx do usuário não é alterado. Micro/meso de 2020 por join espacial
    (`st_point_on_surface`, fallback para o polígono mais próximo); nomes
    de município do linkador (o geobr grafa "Abreu E Lima").
  - Só a malha municipal é exportada (`output/geo/municipios_{BR,UF}.topojson`,
    keep 0,05 nacional / 0,15 UF, quantização 1e5): nacional 3,0 MB bruto /
    0,9 MB gzip (metade do clone). Micro/meso/contorno de UF devem ser
    fundidos no navegador com `topojson.merge` (Fase 4).
  - Fontes de voto: `votacao_partido_munzona` (nominal +
    `QT_TOTAL_VOTOS_LEG_VALIDOS` = total oficial do partido) e
    `detalhe_votacao_munzona` (aptos, comparecimento, válidos, brancos,
    nulos). `ler_csv_do_zip()` extrai para temporário e apaga.
  - Saída: `meta.json` (partidos, federações, fonte), `votos/{UF}.json` e
    `votos/BR.json` (só partidos/totais) -- municípios por índice, vetores
    densos para totais/partidos, pares esparsos `[i, votos, ...]` (base 0)
    para candidatos; candidatos com 0 voto válido (indeferidos) ficam fora
    do arquivo de votos. `candidatos/{UF}.json` = card (mapa e hemiciclo,
    via `frontend/js/card.js`). `composicao.json` agora só tem o essencial
    da cadeira (153 KB bruto / 25 KB gzip). Votos 7,2 MB bruto no total.
  - Validado: em todo município e cargo, soma dos partidos = válidos
    oficiais do detalhe; nominal por partido = soma dos candidatos; senador:
    soma dos candidatos = válidos; 5.571 municípios; geometria de cada UF =
    municípios do arquivo de votos. 221 testes. Conferido contra o projeto
    de PE: diferenças pequenas (≤0,1% por partido) explicadas por data de
    geração (PE usou arquivos de 06/10; aqui, 10/10 12:31) e por votos
    anulados sub judice (batem exatamente em PCO, PSDB, NOVO).
- **Fase 4 (mapa)** completa -- aba Mapa é a padrão:
  - Módulos: `analise.js` (escopo = votos + geometria + candidatos da UF ou
    BR; micro/meso/UF fundidos com `topojson.merge`; entidades partido /
    federação = soma dos membros / candidato; agregação, %, líder com
    margem e intensidade como no clone, teto da escala contínua no
    percentil 98), `lisa.js` (do painel de PE), `painel_mapa.js`
    (seletores, legenda, resumo, popup, card), `mapa.js` (Leaflet canvas,
    contorno de UF por cima, linha por zoom do clone, enquadramento que
    desconta o painel), `card.js` (compartilhado com o hemiciclo; "Ver no
    mapa" no card do hemiciclo abre o contínuo do eleito na UF dele).
  - Combinações (`normalizar()` em painel_mapa.js): unidade "uf" só no
    Brasil; agrupar por candidato só numa UF e, para deputados, não em
    "quem lidera" (só eleitos + 3 suplentes exportados -> o mais votado
    do município poderia não estar entre eles); LISA só por município,
    numa UF, fora o DF (1 município). URL inválida é corrigida.
  - Vizinhança queen exportada por UF em `votos/{UF}.json` (`vizinhos`,
    calculada no R na geometria completa); `meta.json` traz nomes de
    micro/meso. Vetores sempre com `I()` no R: o auto_unbox virava número
    solto no DF (1 município) e quebrava o front.
  - **Zoom só inteiro**: com `zoomSnap` fracionário apareciam costuras de
    1 px entre blocos de tiles do mapa-base (testado: some sem tiles;
    sobreposição de meio pixel e `mix-blend-mode: plus-lighter` não
    resolvem). Brasil fica um pouco menor; é o comportamento do clone.
  - Verificado (`tests/qa_frontend.R`, 25 cenários, sem erro de JS/HTTP):
    nº de unidades desenhadas (5.571 / 137 meso / 27 UF / UF), popup,
    card, link hemiciclo -> mapa, URLs inválidas corrigidas, celular e
    tema claro; **LISA do navegador = spdep::localmoran em 100% dos
    municípios** (PE, SP, BA, MG; 2.100 municípios). Capturas conferidas.
- Próximo: Fase 5 (bairros e locais, piloto nas capitais) e Fase 6
  (publicação).
