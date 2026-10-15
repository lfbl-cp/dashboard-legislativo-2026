# =============================================================================
# QA de fumaça do front-end: sobe um servidor estático na raiz do projeto,
# abre o painel no Chrome headless em vários cenários e confere:
#   - nenhum erro de JavaScript nem requisição com falha (404 etc.)
#   - hemiciclo: cadeiras desenhadas = tamanho da Casa; card e tooltip
#   - mapa: unidades desenhadas = esperado (municípios/micro/meso/UF), card,
#     popup, combinações inválidas na URL corrigidas, link hemiciclo -> mapa
#   - LISA do navegador (frontend/js/lisa.js) = spdep::localmoran no R, com a
#     mesma vizinhança e os mesmos valores
# e grava uma captura de tela por cenário em <pasta_saida>.
#
#   Rscript tests/qa_frontend.R [pasta_saida]
#
# Requer servr, chromote, processx e spdep (QA) e Chrome/Edge instalado
# (CHROMOTE_CHROME aponta o executável).
# =============================================================================

suppressPackageStartupMessages({
  library(chromote)
})
`%||%` <- function(a, b) if (is.null(a)) b else a

local({
  arq <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  if (length(arq) == 1) setwd(normalizePath(file.path(dirname(arq), "..")))
})
args <- commandArgs(trailingOnly = TRUE)
saida <- if (length(args) >= 1) args[1] else file.path(tempdir(), "qa_frontend")
dir.create(saida, showWarnings = FALSE, recursive = TRUE)

# Servidor num processo R à parte: o servr "daemon" atende pelo loop de
# eventos desta sessão, que fica bloqueado enquanto o chromote espera
# resposta do navegador (Page.navigate estoura o tempo).
PORTA <- 8765
srv <- processx::process$new(
  file.path(R.home("bin"), "Rscript"),
  c("-e", sprintf("servr::httd('.', port = %d, browser = FALSE, daemon = FALSE)", PORTA)),
  stdout = NULL, stderr = NULL
)
for (i in 1:50) {
  ok <- tryCatch({
    con <- url(sprintf("http://127.0.0.1:%d/index.html", PORTA)); readLines(con, warn = FALSE); close(con); TRUE
  }, error = function(e) FALSE)
  if (ok) break
  Sys.sleep(0.2)
}
URL <- sprintf("http://127.0.0.1:%d/frontend/index.html", PORTA)

comp <- jsonlite::fromJSON("output/composicao.json", simplifyVector = FALSE)
total_casa <- function(id) comp$casas[[id]]$total
n_mun <- function(uf) length(jsonlite::fromJSON(sprintf("output/votos/%s.json", uf))$municipios)

b <- ChromoteSession$new()
problemas <- character(0)
b$Runtime$enable()
b$Network$enable()
b$Runtime$exceptionThrown(callback_ = function(m) {
  problemas <<- c(problemas, paste("JS:", m$exceptionDetails$exception$description %||% m$exceptionDetails$text))
}, wait_ = FALSE)
b$Network$responseReceived(callback_ = function(m) {
  if (m$response$status >= 400) problemas <<- c(problemas, sprintf("HTTP %d: %s", m$response$status, m$response$url))
}, wait_ = FALSE)

js <- function(expr) b$Runtime$evaluate(expr, returnByValue = TRUE, awaitPromise = TRUE)$result$value

viewport <- function(w, h, mobile = FALSE) {
  b$Emulation$setDeviceMetricsOverride(width = w, height = h, deviceScaleFactor = 1, mobile = mobile)
}

esperar <- function(cond, max_s = 20) {
  for (i in seq_len(max_s * 5)) {
    if (isTRUE(js(cond))) return(TRUE)
    Sys.sleep(0.2)
  }
  FALSE
}

PRONTO <- "document.querySelectorAll('.cadeira').length > 0 && Mapa.nFeicoes() > 0 &&
  document.getElementById('status').textContent === ''"

abrir <- function(hash) {
  b$Page$navigate("about:blank")
  b$Page$navigate(paste0(URL, "#", hash))
  if (!esperar(PRONTO)) problemas <<- c(problemas, "página não ficou pronta em 20 s")
  Sys.sleep(0.6) # tiles e fotos
}

# O renderizador canvas do Leaflet descobre a feição sob o cursor pelo
# mousemove; sem movê-lo antes, o clique não acha alvo.
clicar_mapa <- function(x, y) {
  b$Input$dispatchMouseEvent(type = "mouseMoved", x = x, y = y)
  Sys.sleep(0.2)
  for (tipo in c("mousePressed", "mouseReleased")) {
    b$Input$dispatchMouseEvent(type = tipo, x = x, y = y, button = "left", clickCount = 1)
  }
  Sys.sleep(0.4)
}

resultados <- list()
cenario <- function(nome, hash, esperado = list(), w = 1440, h = 900, mobile = FALSE, acao = NULL) {
  problemas <<- character(0)
  viewport(w, h, mobile)
  abrir(hash)
  if (is.function(acao)) acao() else if (!is.null(acao)) {
    js(acao)
    Sys.sleep(0.8)
  }
  obtido <- list(
    aba = js("document.querySelector('.abas button[aria-selected=\"true\"]').dataset.aba"),
    cadeiras = js("document.querySelectorAll('.cadeira').length"),
    vazadas = js("[...document.querySelectorAll('.cadeira')].filter(c => c.getAttribute('fill') === 'none').length"),
    unidades = js("Mapa.nFeicoes()"),
    card = js("[...document.querySelectorAll('.card')].some(c => !c.hidden && c.querySelector('.card-nome'))"),
    popup = js("!!document.querySelector('.leaflet-popup')"),
    agrupar = js("document.querySelector('#seg-agrupar-mapa button[aria-pressed=\"true\"]').dataset.valor"),
    modo = js("document.getElementById('sel-modo').value"),
    ranking = js("document.querySelectorAll('#painel-direito:not([hidden]) #ranking-mapa li').length"),
    eleitos = js("document.querySelectorAll('#ranking-mapa li.rk-eleito').length"),
    # votos do ranking e do seletor de alvo (candidatos) do maior para o menor
    ordenado = js("(() => { const v = [...document.querySelectorAll('#ranking-mapa ol')].map((ol) => [...ol.querySelectorAll('.rk-num span')].map((s) => +s.textContent.replace(/[^0-9]/g, ''))); return v.every((a) => a.every((x, i) => i === 0 || a[i - 1] >= x)); })()"),
    alvo_ordenado = js("(() => { const o = [...document.querySelectorAll('#sel-alvo option')].map((x) => x.textContent); const n = o.map((t) => +((t.match(/· ([0-9.]+)$/) || [0, '-1'])[1].replace(/[^0-9-]/g, ''))); return n.every((x, i) => i === 0 || x < 0 || n[i - 1] >= x); })()")
  )
  b$screenshot(file.path(saida, paste0(nome, ".png")), show = FALSE)
  if (identical(obtido$aba, "mapa") && !isTRUE(obtido$ordenado)) problemas <<- c(problemas, "ranking fora de ordem")
  if (identical(obtido$aba, "mapa") && !isTRUE(obtido$alvo_ordenado)) problemas <<- c(problemas, "seletor de alvo fora de ordem")
  difere <- names(esperado)[!vapply(names(esperado), function(k) identical(obtido[[k]], esperado[[k]]), logical(1))]
  if (length(difere) > 0) {
    problemas <<- c(problemas, sprintf("%s: obtido %s, esperado %s", difere,
                                       vapply(difere, function(k) format(obtido[[k]] %||% "NULL"), ""),
                                       vapply(difere, function(k) format(esperado[[k]]), "")))
  }
  resultados[[nome]] <<- data.frame(cenario = nome, aba = obtido$aba, cadeiras = obtido$cadeiras,
                                    unidades = obtido$unidades, card = obtido$card, popup = obtido$popup,
                                    problemas = paste(problemas, collapse = " | "), ok = length(problemas) == 0)
}

CLICAR_CADEIRA <- function(i) sprintf("document.querySelectorAll('.cadeira')[%d].dispatchEvent(new MouseEvent('click', {bubbles: true}))", i)

# --- hemiciclo ----------------------------------------------------------------------
cenario("camara", "aba=composicao&casa=camara", list(aba = "composicao", cadeiras = total_casa("camara")))
cenario("camara_federacao", "aba=composicao&casa=camara&agrupar=federacao", list(cadeiras = total_casa("camara")))
cenario("camara_bancada_PE", "aba=composicao&casa=camara&destaque=PE", list(cadeiras = total_casa("camara")))
cenario("senado_card", "aba=composicao&casa=senado", list(cadeiras = total_casa("senado"), vazadas = 27L, card = TRUE),
        acao = paste0(CLICAR_CADEIRA(0), ";",
                      "document.querySelectorAll('.cadeira')[40].dispatchEvent(new MouseEvent('mouseenter', {clientX: 700, clientY: 400}))"))
cenario("assembleia_DF", "aba=composicao&casa=assembleia&uf=DF", list(cadeiras = total_casa("assembleia_DF")))
cenario("assembleia_SP", "aba=composicao&casa=assembleia&uf=SP", list(cadeiras = total_casa("assembleia_SP")))
cenario("tema_claro", "aba=composicao&casa=camara", list(card = TRUE),
        acao = paste0("document.getElementById('btn-tema').click();", CLICAR_CADEIRA(0)))
js("localStorage.clear()")
cenario("celular", "aba=composicao&casa=camara", list(cadeiras = total_casa("camara")), w = 390, h = 844, mobile = TRUE)

# hemiciclo -> "Ver no mapa": abre o mapa contínuo do eleito, na UF dele
cenario("hemiciclo_ver_no_mapa", "aba=composicao&casa=assembleia&uf=PE",
        list(aba = "mapa", agrupar = "candidato", modo = "continuo", unidades = n_mun("PE"), card = TRUE),
        acao = function() {
          js(CLICAR_CADEIRA(10))
          esperar("!!document.querySelector('#card-eleito [data-acao=\"mapa\"]')")
          js("document.querySelector('#card-eleito [data-acao=\"mapa\"]').click()")
          esperar("Mapa.nFeicoes() === document.querySelector('#sel-uf').options.length && false", 1)
          Sys.sleep(1.5)
        })

# --- mapa -----------------------------------------------------------------------------
cenario("mapa_padrao_br", "", list(aba = "mapa", unidades = 5571L, agrupar = "partido", modo = "lider"))
cenario("mapa_br_popup", "aba=mapa&cargo=federal&uf=BR", list(popup = TRUE), acao = function() clicar_mapa(700, 330))
cenario("mapa_br_federacao_meso", "aba=mapa&cargo=federal&uf=BR&unidade=mesorregiao&agrupar=federacao",
        list(unidades = 137L, agrupar = "federacao"))
cenario("mapa_br_uf", "aba=mapa&cargo=estadual&uf=BR&unidade=uf", list(unidades = 27L))
cenario("mapa_br_candidato_invalido", "aba=mapa&cargo=federal&uf=BR&agrupar=candidato&modo=continuo",
        list(agrupar = "partido", unidades = 5571L))
cenario("mapa_pe_candidato", "aba=mapa&cargo=federal&uf=PE&agrupar=candidato&modo=continuo",
        list(unidades = n_mun("PE"), card = TRUE))
cenario("mapa_sp_lisa_PL", "aba=mapa&cargo=federal&uf=SP&agrupar=partido&modo=lisa&alvo=PL",
        list(unidades = n_mun("SP"), modo = "lisa"))
cenario("mapa_df_lisa_invalido", "aba=mapa&cargo=federal&uf=DF&modo=lisa", list(modo = "continuo", unidades = 1L))
cenario("mapa_mg_senador_lider_cand", "aba=mapa&cargo=senador&uf=MG&agrupar=candidato",
        list(unidades = n_mun("MG"), agrupar = "candidato", modo = "lider"))
cenario("mapa_mt_micro", "aba=mapa&cargo=federal&uf=MT&unidade=microrregiao", list(unidades = 22L))
cenario("mapa_tema_claro", "aba=mapa&cargo=federal&uf=BA&agrupar=federacao&modo=continuo&alvo=F101", list(),
        acao = "document.getElementById('btn-tema').click()")
js("localStorage.clear()")
cenario("mapa_celular", "aba=mapa&cargo=federal&uf=RJ", list(unidades = n_mun("RJ")), w = 390, h = 844, mobile = TRUE)

# --- capitais: bairros e locais de votação (Fase 5) ------------------------------------
capitais <- jsonlite::fromJSON("output/capitais/index.json", simplifyVector = FALSE)
n_sub <- function(uf) as.integer(capitais[[uf]]$n_subdivisoes)
n_loc_mapa <- function(uf) {
  l <- jsonlite::fromJSON(sprintf("output/capitais/%s.json", uf))$locais
  sum(!is.na(l$lat))
}
# Clica no maior local de votação desenhado (o 1º: maiores vêm primeiro).
clicar_local <- function() {
  p <- unlist(js("Mapa.pontoTela(0)"))
  clicar_mapa(p[1], p[2])
}
cenario("cap_pe_bairros", "aba=mapa&cargo=federal&uf=PE&unidade=subdivisao", list(unidades = n_sub("PE")))
cenario("cap_pe_locais_popup", "aba=mapa&cargo=estadual&uf=PE&unidade=local",
        list(unidades = n_loc_mapa("PE"), popup = TRUE), acao = clicar_local)
cenario("cap_sp_distritos_lisa", "aba=mapa&cargo=federal&uf=SP&unidade=subdivisao&modo=lisa&alvo=PL",
        list(unidades = n_sub("SP"), modo = "lisa"))
cenario("cap_sp_locais_senador_cand", "aba=mapa&cargo=senador&uf=SP&unidade=local&agrupar=candidato",
        list(unidades = n_loc_mapa("SP"), agrupar = "candidato", modo = "lider"))
cenario("cap_df_ras_candidato", "aba=mapa&cargo=estadual&uf=DF&unidade=subdivisao&agrupar=candidato&modo=continuo",
        list(unidades = n_sub("DF"), card = TRUE))
cenario("cap_ac_sem_bairro", "aba=mapa&cargo=federal&uf=AC&unidade=subdivisao", list(unidades = n_mun("AC")))
cenario("cap_ac_locais", "aba=mapa&cargo=federal&uf=AC&unidade=local&modo=lisa", list(unidades = n_loc_mapa("AC"), modo = "continuo"))
cenario("cap_br_local_invalido", "aba=mapa&cargo=federal&uf=BR&unidade=local", list(unidades = 5571L))
cenario("cap_rj_bairros_celular", "aba=mapa&cargo=federal&uf=RJ&unidade=subdivisao&agrupar=federacao",
        list(unidades = n_sub("RJ")), w = 390, h = 844, mobile = TRUE)

# --- painel da direita: ranking dos mais votados / card ---------------------------------
# MA federal: o 6º mais votado (Duarte Jr) não foi eleito nem é suplente --
# entra pelo ranking (10 mais votados da UF exportados).
cenario("rank_ma_federal", "aba=mapa&cargo=federal&uf=MA", list(ranking = 10L, eleitos = 9L))
cenario("rank_pe_senado", "aba=mapa&cargo=senador&uf=PE", list(eleitos = 2L))
cenario("rank_br_senado", "aba=mapa&cargo=senador&uf=BR", list(ranking = 54L, eleitos = 54L))
cenario("rank_br_federal", "aba=mapa&cargo=federal&uf=BR", list(ranking = 10L))
cenario("rank_sp_partido_PL", "aba=mapa&cargo=federal&uf=SP&modo=continuo&alvo=PL", list(ranking = 10L, card = FALSE))
cenario("rank_capital_pe_locais", "aba=mapa&cargo=estadual&uf=PE&unidade=local", list(ranking = 10L))
cenario("rank_clique_abre_candidato", "aba=mapa&cargo=federal&uf=AL",
        list(agrupar = "candidato", modo = "continuo", card = TRUE, ranking = 0L),
        acao = function() {
          js("document.querySelector('#ranking-mapa li').click()")
          Sys.sleep(1.5)
        })
cenario("lider_cand_recife_bairros", "aba=mapa&cargo=federal&uf=PE&unidade=subdivisao&agrupar=candidato",
        list(agrupar = "candidato", modo = "lider", unidades = n_sub("PE"), ranking = 10L))
cenario("lider_cand_pe_municipios", "aba=mapa&cargo=estadual&uf=PE&agrupar=candidato",
        list(agrupar = "candidato", modo = "lider", unidades = n_mun("PE")))
cenario("lider_cand_sp_locais", "aba=mapa&cargo=federal&uf=SP&unidade=local&agrupar=candidato",
        list(agrupar = "candidato", modo = "lider", unidades = n_loc_mapa("SP")))
cenario("rank_celular", "aba=mapa&cargo=senador&uf=BA", list(eleitos = 2L), w = 390, h = 844, mobile = TRUE)

# --- LISA: navegador x spdep -----------------------------------------------------------
lisa_spdep <- function(x, viz) {
  n <- length(x)
  nb <- lapply(viz, function(v) if (length(v) == 0) 0L else as.integer(unlist(v)) + 1L)
  class(nb) <- "nb"
  attr(nb, "region.id") <- as.character(seq_len(n))
  lw <- spdep::nb2listw(nb, style = "W", zero.policy = TRUE)
  lm <- spdep::localmoran(x, lw, zero.policy = TRUE, alternative = "two.sided")
  p <- lm[, 5]
  z <- x - mean(x)
  lag <- spdep::lag.listw(lw, z, zero.policy = TRUE)
  sem_viz <- lengths(lapply(viz, unlist)) == 0
  ifelse(is.na(p) | p >= 0.05 | sem_viz, "Não significante",
         ifelse(z >= 0, ifelse(lag >= 0, "Alto-Alto", "Alto-Baixo"), ifelse(lag < 0, "Baixo-Baixo", "Baixo-Alto")))
}
casos_lisa <- list(c("PE", "federal", "PSB"), c("SP", "federal", "PL"), c("BA", "estadual", "PT"), c("MG", "senador", NA))
problemas <- character(0)
abrir("aba=mapa")
for (caso in casos_lisa) {
  v <- jsonlite::fromJSON(sprintf("output/votos/%s.json", caso[1]), simplifyVector = FALSE)
  cg <- v$cargos[[caso[2]]]
  validos <- unlist(cg$validos)
  votos <- if (!is.na(caso[3])) unlist(cg$partidos[[caso[3]]]) else {
    pares <- unlist(cg$candidatos[[1]]); d <- numeric(length(validos)); d[pares[c(TRUE, FALSE)] + 1] <- pares[c(FALSE, TRUE)]; d
  }
  x <- ifelse(validos > 0, votos / validos, 0)
  r <- lisa_spdep(x, v$vizinhos)
  navegador <- unlist(js(sprintf("LISA.classificar(%s, %s)", jsonlite::toJSON(x, digits = NA),
                                 jsonlite::toJSON(lapply(v$vizinhos, function(k) as.integer(unlist(k)))))))
  dif <- sum(r != navegador)
  resultados[[paste("lisa", caso[1], caso[2])]] <- data.frame(
    cenario = sprintf("lisa_%s_%s_%s", caso[1], caso[2], caso[3] %||% "cand"), aba = "-", cadeiras = NA,
    unidades = length(x), card = NA, popup = NA,
    problemas = if (dif > 0) sprintf("%d de %d municípios divergem do spdep", dif, length(x)) else "",
    ok = dif == 0
  )
}

# LISA das subdivisões da capital: navegador (Analise.lisaSubdivisoes, que
# tira do grafo as subdivisões sem local de votação) x spdep no mesmo subgrafo.
casos_cap <- list(c("PE", "federal", "PSB"), c("SP", "federal", "PL"), c("RJ", "estadual", "PL"), c("DF", "federal", "PT"))
for (caso in casos_cap) {
  cap <- jsonlite::fromJSON(sprintf("output/capitais/%s.json", caso[1]), simplifyVector = FALSE)
  cg <- cap$cargos[[caso[2]]]
  sub <- unlist(cap$locais$subdiv)
  ns <- length(cap$vizinhos)
  soma <- function(v) vapply(seq_len(ns) - 1L, function(s) sum(v[sub == s]), numeric(1))
  val_s <- soma(unlist(cg$validos))
  vot_s <- soma(unlist(cg$partidos[[caso[3]]]))
  com <- which(val_s > 0) - 1L
  x <- vot_s[com + 1] / val_s[com + 1]
  viz <- lapply(com, function(i) {
    v <- as.integer(unlist(cap$vizinhos[[i + 1]]))
    match(v[v %in% com], com) - 1L
  })
  r <- lisa_spdep(x, viz)
  navegador <- unlist(js(sprintf(
    "(async () => {
      const meta = await Dados.carregarJson('output/meta.json');
      const idx = await Dados.carregarJson('output/capitais/index.json');
      const e = await Analise.carregarCapital('%1$s', idx['%1$s']);
      const uns = Analise.unidades(e, 'subdivisao', meta);
      const tot = Analise.totais(e, '%2$s', uns);
      const ent = Analise.entidades(e, '%2$s', 'partido', meta).find((x) => x.chave === '%3$s');
      const cl = Analise.lisaSubdivisoes(e, uns, Analise.fracoes(ent, uns, tot.validos), tot.validos);
      const porI = [];
      uns.features.forEach((f, u) => { porI[f.properties.i] = cl[u]; });
      return porI.filter((c) => c);
    })()", caso[1], caso[2], caso[3])))
  dif <- if (length(navegador) != length(r)) NA else sum(r != navegador)
  resultados[[paste("lisa_cap", caso[1])]] <- data.frame(
    cenario = sprintf("lisa_capital_%s_%s_%s", caso[1], caso[2], caso[3]), aba = "-", cadeiras = NA,
    unidades = length(x), card = NA, popup = NA,
    problemas = if (is.na(dif)) sprintf("navegador classificou %d, spdep %d", length(navegador), length(r))
                else if (dif > 0) sprintf("%d de %d subdivisões divergem do spdep", dif, length(x)) else "",
    ok = isTRUE(dif == 0)
  )
}

# "Quem lidera" por candidato (deputados): líder de cada município no
# navegador (só candidatos exportados) = mais votado entre TODOS os
# candidatos no munzona.
vm <- readRDS("data/processed/votos_candidato_municipio.rds")
cw <- readxl::read_excel("data-raw/ref/linkador_bases.xlsx", sheet = "Sheet1")
for (caso in list(c("PE", "federal", 6L), c("SP", "estadual", 7L), c("MG", "federal", 6L))) {
  v <- vm[vm$uf == caso[1] & vm$cd_cargo == as.integer(caso[3]) & vm$votos > 0, ]
  v <- v[order(-v$votos), ]
  v <- v[!duplicated(v$cd_municipio_tse), ]
  v$code_muni <- as.integer(cw$id_munic_7[match(paste(caso[1], v$cd_municipio_tse), paste(cw$estado_abrev, cw$id_TSE))])
  navegador <- js(sprintf(
    "(async () => {
      const meta = await Dados.carregarJson('output/meta.json');
      const e = await Analise.carregarEscopo('%s');
      const uns = Analise.unidades(e, 'municipio', meta);
      const ents = Analise.entidades(e, '%s', 'candidato', meta);
      const { lideres } = Analise.lideres(ents, uns, Analise.totais(e, '%s', uns).validos);
      return uns.features.map((f, u) => [f.properties.code_muni, lideres[u] ? ents[lideres[u].k].chave : null]);
    })()", caso[1], caso[2], caso[2]))
  nav <- stats::setNames(vapply(navegador, function(x) x[[2]] %||% NA_character_, ""),
                         vapply(navegador, function(x) as.character(x[[1]]), ""))
  # empate no 1º lugar: qualquer um dos empatados vale
  dif <- sum(nav[as.character(v$code_muni)] != v$sq_candidato &
               !mapply(function(m, sq) {
                 x <- vm[vm$uf == caso[1] & vm$cd_cargo == as.integer(caso[3]) & vm$cd_municipio_tse == m, ]
                 sq %in% x$sq_candidato[x$votos == max(x$votos)]
               }, v$cd_municipio_tse, nav[as.character(v$code_muni)]), na.rm = TRUE)
  resultados[[paste("lider_cand", caso[1])]] <- data.frame(
    cenario = sprintf("lider_candidato_%s_%s", caso[1], caso[2]), aba = "-", cadeiras = NA,
    unidades = nrow(v), card = NA, popup = NA,
    problemas = if (dif > 0) sprintf("%d municípios com líder diferente do munzona", dif) else "",
    ok = dif == 0
  )
}

res <- do.call(rbind, resultados)
rownames(res) <- NULL
print(res[, c("cenario", "aba", "cadeiras", "unidades", "card", "popup", "ok")])
falhas <- res[!res$ok, ]
if (nrow(falhas) > 0) {
  cat("\nFALHAS:\n")
  for (i in seq_len(nrow(falhas))) cat(sprintf("- %s: %s\n", falhas$cenario[i], falhas$problemas[i]))
}
cat(sprintf("\nCapturas em %s\n", normalizePath(saida)))
b$close()
srv$kill()
if (nrow(falhas) > 0) quit(status = 1)
