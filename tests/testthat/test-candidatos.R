test_that("nome de urna sai com só a inicial maiúscula e conectivos minúsculos", {
  expect_equal(normalizar_nome_candidato(c("RAQUEL LYRA", "MARIA DA SILVA", "DA COSTA", NA)),
               c("Raquel Lyra", "Maria da Silva", "Da Costa", NA))
  expect_equal(normalizar_nome_candidato("JOÃO  DOS SANTOS"), "João dos Santos")
})

test_that("situação final do TSE é classificada", {
  expect_equal(
    classificar_situacao(c("ELEITO", "ELEITO POR QP", "ELEITO POR MÉDIA", "SUPLENTE",
                           "NÃO ELEITO", NA)),
    c("eleito", "eleito", "eleito", "suplente", "nao_eleito", NA)
  )
})

test_that("URL de rede social é normalizada", {
  expect_equal(
    limpar_url_rede(c("HTTPS://WWW.INSTAGRAM.COM/PLINIO.VALERIO?IGSH=ZJNT",
                      "www.tiktok.com/@Fulano?_t=8AX&_r=1",
                      "https://twitter.com/fulano/",
                      "http://WWW.Site.com.br/Pagina?id=1")),
    c("https://www.instagram.com/plinio.valerio",
      "https://www.tiktok.com/@fulano",
      "https://twitter.com/fulano",
      "http://www.site.com.br/Pagina?id=1")
  )
  expect_equal(eh_rede_conhecida(c("https://www.instagram.com/x", "https://m.facebook.com/x",
                                   "https://meusite.com.br")), c(TRUE, TRUE, FALSE))
})

test_that("tamanho da Assembleia segue a CF art. 27", {
  expect_equal(tamanho_assembleia(c(8L, 12L, 25L, 70L)), c(24L, 36L, 49L, 94L))
})

test_that("tabela de partidos é consistente", {
  p <- ler_partidos_ref()
  expect_true(all(grepl("^#[0-9A-Fa-f]{6}$", p$cor)))
  expect_true(all(is.na(p$ideologia) | (p$ideologia >= 0 & p$ideologia <= 10)))
  expect_true(all(p$metodo_ideologia %in% c("tabela", "renomeado", "fusao", "estimado", "pendente")))
  expect_true(all(is.na(p$ideologia) == (p$metodo_ideologia == "pendente")))
  expect_false(anyDuplicated(p$nr_2026[!is.na(p$nr_2026)]) > 0)
})

arq_cadeiras <- file.path(DIR_PROCESSED, "cadeiras.rds")

test_that("cadeiras processadas fecham com o tamanho de cada Casa", {
  skip_if_not(file.exists(arq_cadeiras), "rode o pipeline (etapa candidatos) antes")
  cadeiras <- readRDS(arq_cadeiras)
  expect_silent(validar_cadeiras(cadeiras))
  expect_equal(sum(grepl("^assembleia_", cadeiras$casa)), 1059)
  expect_false(anyDuplicated(cadeiras$sq_candidato) > 0)
  # renovada = FALSE só para os 27 senadores de 2022
  expect_equal(sum(!cadeiras$renovada), 27)
})

test_that("candidatos não carregam dados pessoais sensíveis", {
  skip_if_not(file.exists(file.path(DIR_PROCESSED, "candidatos.rds")))
  cand <- readRDS(file.path(DIR_PROCESSED, "candidatos.rds"))
  expect_false(any(grepl("CPF|EMAIL|TITULO", toupper(names(cand)))))
})

test_that("suplência segue os votos: nenhum suplente supera o eleito menos votado da lista", {
  arq <- file.path(DIR_PROCESSED, "candidatos.rds")
  skip_if_not(file.exists(arq))
  cand <- readRDS(arq)
  skip_if(is.null(cand$ordem_suplente), "rode a etapa votos antes")
  d <- cand[cand$ano == ANO & cand$tipo == "proporcional", ]
  chave <- paste(d$uf, d$cargo, d$lista)
  min_eleito <- tapply(d$votos_total[d$situacao %in% "eleito"], chave[d$situacao %in% "eleito"], min)
  sup <- d[d$situacao %in% "suplente", ]
  ch_sup <- paste(sup$uf, sup$cargo, sup$lista)
  com_eleito <- ch_sup %in% names(min_eleito)
  expect_true(all(sup$votos_total[com_eleito] <= min_eleito[ch_sup[com_eleito]]))

  # 1º suplente é o mais votado entre os suplentes da lista
  primeiro <- sup[sup$ordem_suplente %in% 1, ]
  max_sup <- tapply(sup$votos_total, ch_sup, max)
  expect_equal(as.vector(primeiro$votos_total),
               as.vector(max_sup[paste(primeiro$uf, primeiro$cargo, primeiro$lista)]))

  # exibidos: eleitos + até N_SUPLENTES por lista; suplente além disso só se
  # estiver entre os mais votados da UF ou da capital (ranking)
  vm <- readRDS(file.path(DIR_PROCESSED, "votos_candidato_municipio.rds"))
  cw <- ler_crosswalk_tse_ibge()
  top <- top_votados(cand, vm, N_RANKING, cw[cw$code_muni %in% CAPITAIS, c("uf", "cd_municipio_tse")])
  extra <- sup[sup$exibir & sup$ordem_suplente > N_SUPLENTES, ]
  expect_true(all(extra$sq_candidato %in% top))
  expect_true(all(d$exibir[d$situacao %in% "eleito"]))
  expect_true(all(cand$exibir[cand$sq_candidato %in% top]))
})

test_that("os 10 mais votados de cada UF e cargo são exibidos", {
  arq <- file.path(DIR_PROCESSED, "candidatos.rds")
  skip_if_not(file.exists(arq))
  cand <- data.table::as.data.table(readRDS(arq))[ano == ANO & votos_total > 0]
  skip_if(is.null(cand$ordem_suplente), "rode a etapa votos antes")
  top <- cand[order(-votos_total), head(.SD, N_RANKING), by = .(uf, cargo)]
  expect_true(all(top$exibir))
})

test_that("validar_cadeiras acusa Câmara incompleta", {
  skip_if_not(file.exists(arq_cadeiras))
  cadeiras <- readRDS(arq_cadeiras)
  expect_error(validar_cadeiras(cadeiras[-1, ]), "Câmara|Senado|Assembleia")
})
