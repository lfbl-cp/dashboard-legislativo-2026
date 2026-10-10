# =============================================================================
# Cadeiras de cada Casa (base dos hemiciclos):
#   camara          deputados federais eleitos em 2026 (513)
#   senado          senadores eleitos em 2026 (2 por UF, renovação de 2/3)
#                   + eleitos em 2022 (1 por UF, mandato até 2031), todos pelo
#                   partido da eleição -- não pelo partido atual nem por quem
#                   ocupa a cadeira hoje (suplente em exercício)
#   assembleia_XX   deputados estaduais (distritais no DF) eleitos em 2026
# =============================================================================

COLUNAS_CADEIRA <- c("casa", "uf", "ano", "sq_candidato", "nome", "sigla")

montar_cadeiras <- function(candidatos, candidatos_senado_anterior) {
  eleitos <- candidatos[candidatos$situacao %in% "eleito", ]
  eleitos$ano <- ANO

  camara <- eleitos[eleitos$cargo == "federal", ]
  camara$casa <- "camara"

  assembleias <- eleitos[eleitos$cargo == "estadual", ]
  assembleias$casa <- paste0("assembleia_", assembleias$uf)

  sen_ant <- candidatos_senado_anterior[candidatos_senado_anterior$cargo == "senador" &
                                          candidatos_senado_anterior$situacao %in% "eleito", ]
  sen_ant$ano <- ANO_SENADO_ANTERIOR
  senado <- rbind(eleitos[eleitos$cargo == "senador", names(sen_ant)], sen_ant)
  senado$casa <- "senado"

  out <- rbind(camara[, COLUNAS_CADEIRA], senado[, COLUNAS_CADEIRA], assembleias[, COLUNAS_CADEIRA])
  out$renovada <- out$casa != "senado" | out$ano == ANO
  rownames(out) <- NULL
  out
}

# Tamanho constitucional da Assembleia (CF art. 27): o triplo da bancada
# federal até 36; acima disso, +1 por deputado federal que passar de 12.
tamanho_assembleia <- function(bancada_federal) {
  ifelse(bancada_federal <= 12, 3L * bancada_federal, 36L + bancada_federal - 12L)
}

# Confere as cadeiras contra os tamanhos esperados de cada Casa. Para no 1º
# problema, com mensagem dizendo onde.
validar_cadeiras <- function(cadeiras) {
  n <- table(cadeiras$casa)
  if (n[["camara"]] != 513) stop(sprintf("Câmara com %d eleitos (esperado 513)", n[["camara"]]))
  if (n[["senado"]] != 81) stop(sprintf("Senado com %d cadeiras (esperado 81)", n[["senado"]]))

  sen_uf <- table(cadeiras$uf[cadeiras$casa == "senado"], cadeiras$ano[cadeiras$casa == "senado"])
  ruins <- rownames(sen_uf)[sen_uf[, as.character(ANO)] != 2 | sen_uf[, as.character(ANO_SENADO_ANTERIOR)] != 1]
  if (length(ruins) > 0) stop("Senado sem 2 (2026) + 1 (2022) cadeiras em: ", paste(ruins, collapse = ", "))

  bancada <- table(factor(cadeiras$uf[cadeiras$casa == "camara"], levels = UFS_BRASIL))
  esperado <- tamanho_assembleia(as.integer(bancada))
  obtido <- as.integer(n[paste0("assembleia_", UFS_BRASIL)])
  ruins <- UFS_BRASIL[is.na(obtido) | obtido != esperado]
  if (length(ruins) > 0) {
    stop("Assembleia com tamanho diferente do constitucional em: ",
         paste(sprintf("%s (%s eleitos, esperado %d)", ruins, obtido[match(ruins, UFS_BRASIL)],
                       esperado[match(ruins, UFS_BRASIL)]), collapse = "; "))
  }
  invisible(TRUE)
}
