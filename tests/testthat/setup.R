# Testes:  Rscript -e "testthat::test_dir('tests/testthat')"  (da raiz)
# O testthat roda cada arquivo com o diretório em tests/testthat, então os
# caminhos do pipeline (relativos à raiz) viram absolutos aqui.
raiz <- normalizePath(file.path(testthat::test_path(), "..", ".."))
for (f in sort(list.files(file.path(raiz, "R"), pattern = "\\.R$", full.names = TRUE))) {
  source(f, encoding = "UTF-8", local = TRUE)
}
DIR_RAW       <- file.path(raiz, DIR_RAW)
DIR_PROCESSED <- file.path(raiz, DIR_PROCESSED)
DIR_REF       <- file.path(raiz, DIR_REF)
DIR_OUTPUT    <- file.path(raiz, DIR_OUTPUT)
