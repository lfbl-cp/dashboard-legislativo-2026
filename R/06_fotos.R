# =============================================================================
# Fotos oficiais do TSE (F<UF><SQ_CANDIDATO>_div.jpg, um ZIP por UF) ->
# output/fotos/<sq>.jpg, só dos candidatos exibidos no painel. Os ZIPs ficam
# em cache em data/raw/.
#
# Senadores eleitos em 2022: os ZIPs de fotos de 2022 do TSE somam ~770 MB
# para 27 fotos, então as fotos vêm da API de dados abertos do Senado (foto
# oficial do titular), recortadas para o mesmo formato das do TSE.
# =============================================================================

DIR_FOTOS <- file.path(DIR_OUTPUT, "fotos")
TAMANHO_FOTO <- "161x225" # largura x altura das fotos do TSE

extrair_fotos <- function(candidatos, ano = ANO) {
  dir.create(DIR_FOTOS, showWarnings = FALSE, recursive = TRUE)
  exib <- candidatos[candidatos$exibir & candidatos$ano == ano, c("uf", "sq_candidato")]
  for (uf in sort(unique(exib$uf))) {
    sq <- exib$sq_candidato[exib$uf == uf]
    destinos <- file.path(DIR_FOTOS, paste0(sq, ".jpg"))
    if (all(file.exists(destinos))) next
    zip <- obter_zip_tse(url_fotos(ano, uf))
    lista <- utils::unzip(zip, list = TRUE)$Name
    sq_zip <- sub("^F[A-Z]{2}(\\d+)_div\\.(jpe?g|png)$", "\\1", basename(lista), ignore.case = TRUE)
    alvo <- lista[sq_zip %in% sq[!file.exists(destinos)]]
    if (length(alvo) == 0) next
    tmp <- tempfile("fotos_")
    utils::unzip(zip, files = alvo, exdir = tmp, junkpaths = TRUE)
    file.copy(file.path(tmp, basename(alvo)),
              file.path(DIR_FOTOS, paste0(sq_zip[match(alvo, lista)], ".jpg")), overwrite = TRUE)
    unlink(tmp, recursive = TRUE)
  }
  file.exists(file.path(DIR_FOTOS, paste0(candidatos$sq_candidato, ".jpg")))
}

# Titulares do Senado cujo mandato começou na legislatura `n` (= eleitos na
# eleição anterior a ela): uma linha por UF, com código e URL da foto.
ler_titulares_senado <- function(n = LEGISLATURA_SENADO_ANTERIOR) {
  destino <- file.path(DIR_RAW, sprintf("senado_legislatura_%d.json", n))
  if (!file.exists(destino)) baixar_arquivo_tse(url_senado_legislatura(n), destino)
  j <- jsonlite::fromJSON(destino, simplifyVector = FALSE)
  linhas <- list()
  for (p in j$ListaParlamentarLegislatura$Parlamentares$Parlamentar) {
    mandatos <- p$Mandatos$Mandato
    if (!is.null(mandatos$CodigoMandato)) mandatos <- list(mandatos)
    for (m in mandatos) {
      if (identical(m$DescricaoParticipacao, "Titular") &&
          identical(m$PrimeiraLegislaturaDoMandato$NumeroLegislatura, as.character(n))) {
        linhas[[length(linhas) + 1]] <- data.frame(
          uf = m$UfParlamentar,
          nome = p$IdentificacaoParlamentar$NomeParlamentar,
          url_foto = sprintf("https://www.senado.leg.br/senadores/img/fotos-oficiais/senador%s.jpg",
                             p$IdentificacaoParlamentar$CodigoParlamentar),
          stringsAsFactors = FALSE
        )
      }
    }
  }
  out <- do.call(rbind, linhas)
  if (nrow(out) != length(UFS_BRASIL) || anyDuplicated(out$uf)) {
    stop(sprintf("API do Senado: esperado 1 titular por UF na legislatura %d, veio %d", n, nrow(out)))
  }
  out
}

# Fotos dos senadores eleitos em ANO_SENADO_ANTERIOR, casados por UF (há
# exatamente 1 por UF). Recorta para TAMANHO_FOTO mantendo o topo (rosto).
extrair_fotos_senado_anterior <- function(candidatos) {
  sen <- candidatos[candidatos$ano == ANO_SENADO_ANTERIOR & candidatos$cargo == "senador", ]
  titulares <- ler_titulares_senado()
  sen$url_foto <- titulares$url_foto[match(sen$uf, titulares$uf)]
  for (i in seq_len(nrow(sen))) {
    destino <- file.path(DIR_FOTOS, paste0(sen$sq_candidato[i], ".jpg"))
    if (file.exists(destino)) next
    tmp <- tempfile(fileext = ".jpg")
    baixar_arquivo_tse(sen$url_foto[i], tmp)
    img <- magick::image_read(tmp)
    img <- magick::image_resize(img, paste0(TAMANHO_FOTO, "^"))
    img <- magick::image_crop(img, TAMANHO_FOTO, gravity = "North")
    magick::image_write(img, destino, format = "jpeg", quality = 85)
    unlink(tmp)
  }
  # nomes lado a lado para conferência visual no log
  data.frame(uf = sen$uf, tse = sen$nome, senado = titulares$nome[match(sen$uf, titulares$uf)])
}
