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
    modo = js("document.getElementById('sel-modo').value")
  )
  b$screenshot(file.path(saida, paste0(nome, ".png")), show = FALSE)
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
cenario("mapa_br_popup", "aba=mapa&cargo=federal&uf=BR", list(popup = TRUE), acao = function() clicar_mapa(886, 430))
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
