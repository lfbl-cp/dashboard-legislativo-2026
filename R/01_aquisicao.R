# =============================================================================
# Aquisição: baixa os ZIPs do TSE para data/raw/ (cache -- ZIP já baixado é
# reaproveitado) e extrai só os arquivos pedidos. Para forçar novo download
# (o TSE republica arquivos com correções), apagar o ZIP em data/raw/.
# =============================================================================

baixar_arquivo_tse <- function(url, destino, tentativas = 3) {
  dir.create(dirname(destino), showWarnings = FALSE, recursive = TRUE)
  tmp <- paste0(destino, ".parcial")
  for (i in seq_len(tentativas)) {
    ok <- tryCatch({
      resp <- httr::GET(url, httr::add_headers(`User-Agent` = UA_NAVEGADOR),
                        httr::write_disk(tmp, overwrite = TRUE), httr::timeout(3600))
      httr::stop_for_status(resp)
      TRUE
    }, error = function(e) {
      message(sprintf("  tentativa %d/%d falhou: %s", i, tentativas, conditionMessage(e)))
      FALSE
    })
    if (ok) {
      file.rename(tmp, destino)
      return(invisible(destino))
    }
    unlink(tmp)
    Sys.sleep(10)
  }
  stop(sprintf("Falha ao baixar %s", url))
}

# Garante o ZIP em data/raw/<basename da URL> e devolve o caminho.
obter_zip_tse <- function(url) {
  destino <- file.path(DIR_RAW, basename(url))
  if (!file.exists(destino)) {
    message(sprintf("Baixando %s ...", basename(url)))
    baixar_arquivo_tse(url, destino)
    message(sprintf("  %.1f MB", file.size(destino) / 1024^2))
  }
  destino
}

# Extrai do ZIP os arquivos cujo nome casa com `padrao` para
# data/raw/<nome do zip sem extensão>/ (pula os que já estão lá). Devolve os
# caminhos extraídos.
extrair_do_zip <- function(zip, padrao) {
  pasta <- file.path(DIR_RAW, sub("\\.zip$", "", basename(zip)))
  lista <- utils::unzip(zip, list = TRUE)$Name
  alvo <- grep(padrao, lista, value = TRUE)
  if (length(alvo) == 0) stop(sprintf("Nenhum arquivo casando '%s' em %s", padrao, zip))
  faltam <- alvo[!file.exists(file.path(pasta, alvo))]
  if (length(faltam) > 0) {
    dir.create(pasta, showWarnings = FALSE, recursive = TRUE)
    utils::unzip(zip, files = faltam, exdir = pasta, overwrite = TRUE)
  }
  file.path(pasta, alvo)
}

# CSVs de candidatos de um ano: um por UF (os 27 estaduais). O _BR
# (Presidente) e o _BRASIL (concatenação redundante) ficam de fora.
obter_csvs_candidatos <- function(ano) {
  zip <- obter_zip_tse(url_consulta_cand(ano))
  extrair_do_zip(zip, sprintf("^consulta_cand_%d_(%s)\\.csv$", ano, paste(UFS_BRASIL, collapse = "|")))
}

obter_csvs_redes <- function(ano) {
  zip <- obter_zip_tse(url_rede_social(ano))
  extrair_do_zip(zip, sprintf("^rede_social_candidato_%d_(%s)\\.csv$", ano, paste(UFS_BRASIL, collapse = "|")))
}
