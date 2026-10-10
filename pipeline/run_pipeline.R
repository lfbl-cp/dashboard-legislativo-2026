# =============================================================================
# Orquestração do pipeline.
#
#   Rscript pipeline/run_pipeline.R                    # todas as etapas
#   Rscript pipeline/run_pipeline.R --etapa=candidatos # só uma (ou várias,
#                                                      # separadas por vírgula)
#
# Etapas (em ordem):
#   candidatos  consulta_cand 2026 (27 UFs) + senadores 2022 -> candidatos,
#               partidos, federações e cadeiras de cada Casa, validados
#   fotos       fotos oficiais dos candidatos exibidos -> output/fotos/
# =============================================================================

suppressPackageStartupMessages({
  library(data.table)
})

# Raiz do projeto = pasta acima de pipeline/, de onde quer que se rode.
local({
  arq <- sub("^--file=", "", grep("^--file=", commandArgs(FALSE), value = TRUE))
  raiz <- if (length(arq) == 1) normalizePath(file.path(dirname(arq), "..")) else getwd()
  setwd(raiz)
})
for (f in sort(list.files("R", pattern = "\\.R$", full.names = TRUE))) source(f, encoding = "UTF-8")

ETAPAS <- c("candidatos", "fotos")

args <- commandArgs(trailingOnly = TRUE)
etapas <- ETAPAS
arg_etapa <- grep("^--etapa=", args, value = TRUE)
if (length(arg_etapa) == 1) {
  etapas <- strsplit(sub("^--etapa=", "", arg_etapa), ",")[[1]]
  desconhecidas <- setdiff(etapas, ETAPAS)
  if (length(desconhecidas) > 0) stop("Etapa desconhecida: ", paste(desconhecidas, collapse = ", "))
}
dir.create(DIR_PROCESSED, showWarnings = FALSE, recursive = TRUE)

# --- candidatos ------------------------------------------------------------------
etapa_candidatos <- function() {
  candidatos <- montar_candidatos(ler_candidatos(ANO))
  senado_anterior <- montar_candidatos(ler_candidatos(ANO_SENADO_ANTERIOR))
  senado_anterior <- senado_anterior[senado_anterior$cargo == "senador" &
                                       senado_anterior$situacao %in% "eleito", ]
  senado_anterior$exibir <- TRUE

  partidos_ref <- ler_partidos_ref()
  validar_partidos(c(candidatos$sigla, senado_anterior$sigla), partidos_ref)
  federacoes <- montar_federacoes(candidatos, partidos_ref)
  partidos <- montar_partidos(partidos_ref, federacoes)

  cadeiras <- montar_cadeiras(candidatos, senado_anterior)
  validar_cadeiras(cadeiras)

  sem_posicao <- unique(cadeiras$sigla[is.na(partidos$ideologia[match(cadeiras$sigla, partidos$sigla)])])
  if (length(sem_posicao) > 0) {
    message("Aviso: partido(s) com cadeira e sem posição ideológica (partidos.csv): ",
            paste(sem_posicao, collapse = ", "))
  }

  todos <- rbind(candidatos, senado_anterior)
  redes <- montar_redes(ANO, todos$sq_candidato[todos$exibir])
  todos$redes <- unname(redes[todos$sq_candidato])

  saveRDS(todos, file.path(DIR_PROCESSED, "candidatos.rds"))
  saveRDS(partidos, file.path(DIR_PROCESSED, "partidos.rds"))
  saveRDS(federacoes, file.path(DIR_PROCESSED, "federacoes.rds"))
  saveRDS(cadeiras, file.path(DIR_PROCESSED, "cadeiras.rds"))

  cat(sprintf("\nCandidatos 2026: %d | exibidos: %d | senadores 2022: %d\n",
              nrow(candidatos), sum(candidatos$exibir), nrow(senado_anterior)))
  print(table(candidatos$cargo, candidatos$situacao, useNA = "ifany"))
  cat("\nCadeiras por Casa:\n")
  n <- table(cadeiras$casa)
  print(n[c("camara", "senado")])
  cat(sprintf("Assembleias: %d cadeiras em %d Casas\n",
              sum(n[grepl("^assembleia_", names(n))]), sum(grepl("^assembleia_", names(n)))))
  cat("\nCâmara por partido:\n")
  print(sort(table(cadeiras$sigla[cadeiras$casa == "camara"]), decreasing = TRUE))
  cat("\nSenado por partido (renovadas em 2026 / eleitos em 2022):\n")
  print(table(cadeiras$sigla[cadeiras$casa == "senado"], cadeiras$ano[cadeiras$casa == "senado"]))
}

# --- fotos -------------------------------------------------------------------------
etapa_fotos <- function() {
  candidatos <- readRDS(file.path(DIR_PROCESSED, "candidatos.rds"))
  extrair_fotos(candidatos)
  cat("Senadores de", ANO_SENADO_ANTERIOR, "(TSE x API do Senado, casados por UF):\n")
  print(extrair_fotos_senado_anterior(candidatos), row.names = FALSE)
  candidatos$tem_foto <- file.exists(file.path(DIR_FOTOS, paste0(candidatos$sq_candidato, ".jpg")))
  saveRDS(candidatos, file.path(DIR_PROCESSED, "candidatos.rds"))
  ex <- candidatos[candidatos$exibir, ]
  cat(sprintf("Exibidos: %d | com foto: %d | sem foto: %d\n",
              nrow(ex), sum(ex$tem_foto), sum(!ex$tem_foto)))
  if (any(!ex$tem_foto)) print(ex[!ex$tem_foto, c("uf", "cargo", "nome", "ds_situacao_tse")], row.names = FALSE)
  tam <- sum(file.size(list.files(DIR_FOTOS, full.names = TRUE)))
  cat(sprintf("output/fotos/: %.1f MB\n", tam / 1024^2))
}

for (e in etapas) {
  cat(sprintf("\n==================== %s ====================\n", e))
  t0 <- Sys.time()
  get(paste0("etapa_", e))()
  cat(sprintf("-- %s ok em %.0fs\n", e, as.numeric(difftime(Sys.time(), t0, units = "secs"))))
}
