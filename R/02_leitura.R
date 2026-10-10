# =============================================================================
# Leitura dos CSVs do TSE: separador ";", aspas, Latin-1, "#NULO#"/"#NE#"
# como ausente.
# =============================================================================

VALORES_AUSENTES_TSE <- c("#NULO#", "#NE#", "#NULO", "#NE", "")

ler_csv_tse <- function(caminho, select = NULL, ...) {
  if (!file.exists(caminho)) stop(sprintf("Arquivo bruto não encontrado: %s", caminho))
  # integer64 = "character": SQ_CANDIDATO (ex.: 170002544167) não cabe em
  # inteiro de 32 bits; como texto vira chave de join sem depender do bit64.
  x <- data.table::fread(caminho, sep = ";", quote = "\"", encoding = "Latin-1",
                         showProgress = FALSE, na.strings = VALORES_AUSENTES_TSE,
                         select = select, integer64 = "character", ...)
  # fread só aplica na.strings a campo SEM aspas; o TSE grava "#NULO#" entre
  # aspas nas colunas de texto, então converte à mão.
  for (col in names(x)[vapply(x, is.character, logical(1))]) {
    idx <- which(x[[col]] %in% VALORES_AUSENTES_TSE)
    if (length(idx) > 0) data.table::set(x, i = idx, j = col, value = NA_character_)
  }
  x
}
