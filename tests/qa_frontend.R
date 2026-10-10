# =============================================================================
# QA de fumaça do front-end: sobe um servidor estático na raiz do projeto,
# abre o painel no Chrome headless em vários cenários e confere:
#   - nenhum erro de JavaScript nem requisição com falha (404 etc.)
#   - número de cadeiras desenhadas = tamanho da Casa
#   - legenda, card do eleito e tooltip respondendo
# e grava uma captura de tela por cenário em <pasta_saida>.
#
#   Rscript tests/qa_frontend.R [pasta_saida]
#
# Requer os pacotes servr e chromote (só para QA) e Chrome/Edge instalado.
# =============================================================================

suppressPackageStartupMessages({
  library(chromote)
})

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

abrir <- function(hash) {
  b$Page$navigate("about:blank")
  b$Page$navigate(paste0(URL, "#", hash))
  for (i in 1:50) {
    pronto <- js("document.querySelectorAll('.cadeira').length > 0 || document.querySelector('#status')?.textContent.startsWith('Erro')")
    if (isTRUE(pronto)) break
    Sys.sleep(0.2)
  }
  Sys.sleep(0.4) # fotos/tiles
}

resultados <- list()
cenario <- function(nome, hash, esperado = NULL, w = 1440, h = 900, mobile = FALSE, acao = NULL) {
  problemas <<- character(0)
  viewport(w, h, mobile)
  abrir(hash)
  if (!is.null(acao)) {
    js(acao)
    Sys.sleep(0.5)
  }
  n <- js("document.querySelectorAll('.cadeira').length")
  vazadas <- js("[...document.querySelectorAll('.cadeira')].filter(c => c.getAttribute('fill') === 'none').length")
  legenda <- js("document.querySelectorAll('.legenda-grupo').length")
  card <- js("!document.getElementById('card-eleito').hidden")
  b$screenshot(file.path(saida, paste0(nome, ".png")), show = FALSE)
  ok <- length(problemas) == 0 && (is.null(esperado) || identical(as.integer(n), as.integer(esperado)))
  resultados[[nome]] <<- data.frame(cenario = nome, cadeiras = n, esperado = esperado %||% NA,
                                    vazadas = vazadas, grupos_legenda = legenda, card = card,
                                    problemas = paste(problemas, collapse = " | "), ok = ok)
}

`%||%` <- function(a, b) if (is.null(a)) b else a

CLICAR_1A_CADEIRA <- "document.querySelectorAll('.cadeira')[0].dispatchEvent(new MouseEvent('click', {bubbles: true}))"

cenario("camara", "aba=composicao&casa=camara", total_casa("camara"))
cenario("camara_federacao", "aba=composicao&casa=camara&agrupar=federacao", total_casa("camara"))
cenario("camara_bancada_PE", "aba=composicao&casa=camara&destaque=PE", total_casa("camara"))
cenario("senado", "aba=composicao&casa=senado", total_casa("senado"))
cenario("senado_card", "aba=composicao&casa=senado", total_casa("senado"),
        acao = paste0(CLICAR_1A_CADEIRA, ";",
                      "document.querySelectorAll('.cadeira')[40].dispatchEvent(new MouseEvent('mouseenter', {clientX: 700, clientY: 400}))"))
cenario("assembleia_DF", "aba=composicao&casa=assembleia&uf=DF", total_casa("assembleia_DF"))
cenario("assembleia_SP", "aba=composicao&casa=assembleia&uf=SP", total_casa("assembleia_SP"))
cenario("legenda_grupo_PL", "aba=composicao&casa=camara",  total_casa("camara"),
        acao = "document.querySelector('.legenda-grupo[data-grupo=\"PL\"]').click()")
cenario("tema_claro", "aba=composicao&casa=camara", total_casa("camara"),
        acao = paste0("document.getElementById('btn-tema').click();", CLICAR_1A_CADEIRA))
cenario("celular", "aba=composicao&casa=camara", total_casa("camara"), w = 390, h = 844, mobile = TRUE)
cenario("aba_mapa", "aba=mapa")
# volta o tema ao padrão (fica salvo no localStorage do perfil headless)
js("localStorage.clear()")

res <- do.call(rbind, resultados)
rownames(res) <- NULL
print(res[, c("cenario", "cadeiras", "esperado", "vazadas", "grupos_legenda", "card", "ok")])
falhas <- res[!res$ok, ]
if (nrow(falhas) > 0) {
  cat("\nFALHAS:\n")
  for (i in seq_len(nrow(falhas))) cat(sprintf("- %s: %s\n", falhas$cenario[i], falhas$problemas[i]))
}
cat(sprintf("\nCapturas em %s\n", normalizePath(saida)))
b$close()
srv$kill()
if (nrow(falhas) > 0) quit(status = 1)
