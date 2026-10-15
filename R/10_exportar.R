# =============================================================================
# Exportação para o front-end (decisões de economia de dados em PLANO.md):
#
#   output/meta.json            partidos, federações, UFs, fonte -- pequeno,
#                               carregado sempre
#   output/votos/{UF}.json      votos INTEIROS por município da UF: totais
#                               (aptos, comparecimento, válidos, brancos,
#                               nulos), partidos (nominal + legenda) e
#                               candidatos exibidos. %, agregação micro/meso,
#                               líder e LISA são calculados no navegador.
#   output/votos/BR.json        visão "Brasil": só totais e partidos, todos
#                               os municípios (sem candidatos)
#   output/candidatos/{UF}.json dados de card dos exibidos da UF, usados pelo
#                               mapa e pelo hemiciclo (carregado no clique)
#
# Formato compacto: municípios indexados pela posição em `municipios`;
# vetores densos (um valor por município) para totais e partidos; pares
# esparsos [índice, votos, índice, votos, ...] para candidatos.
# =============================================================================

CARGOS_EXPORT <- c("federal", "estadual", "senador")

# Votos por partido x município (nominal + legenda), UF a UF.
ler_votos_partido <- function(ano = ANO) {
  zip <- obter_zip_tse(url_partido_munzona(ano))
  col <- c("NR_TURNO", "SG_UF", "CD_MUNICIPIO", "CD_CARGO", "SG_PARTIDO",
           "QT_VOTOS_NOMINAIS_VALIDOS", "QT_TOTAL_VOTOS_LEG_VALIDOS")
  data.table::rbindlist(lapply(UFS_BRASIL, function(uf) {
    x <- ler_csv_do_zip(zip, sprintf("votacao_partido_munzona_%d_%s.csv", ano, uf), col)
    x <- x[NR_TURNO == TURNO & CD_CARGO %in% CARGOS$cd_cargo]
    x[, .(nominal = sum(QT_VOTOS_NOMINAIS_VALIDOS), legenda = sum(QT_TOTAL_VOTOS_LEG_VALIDOS)),
      by = .(uf = SG_UF, cd_municipio_tse = as.integer(CD_MUNICIPIO), cd_cargo = CD_CARGO, sigla = SG_PARTIDO)]
  }))
}

# Totais por município x cargo (aptos, comparecimento, válidos, brancos, nulos).
ler_detalhe <- function(ano = ANO) {
  zip <- obter_zip_tse(url_detalhe_munzona(ano))
  col <- c("NR_TURNO", "SG_UF", "CD_MUNICIPIO", "CD_CARGO", "QT_APTOS", "QT_COMPARECIMENTO",
           "QT_TOTAL_VOTOS_VALIDOS", "QT_VOTOS_BRANCOS", "QT_TOTAL_VOTOS_NULOS")
  data.table::rbindlist(lapply(UFS_BRASIL, function(uf) {
    x <- ler_csv_do_zip(zip, sprintf("detalhe_votacao_munzona_%d_%s.csv", ano, uf), col)
    x <- x[NR_TURNO == TURNO & CD_CARGO %in% CARGOS$cd_cargo]
    x[, .(aptos = sum(QT_APTOS), comparecimento = sum(QT_COMPARECIMENTO),
          validos = sum(QT_TOTAL_VOTOS_VALIDOS), brancos = sum(QT_VOTOS_BRANCOS),
          nulos = sum(QT_TOTAL_VOTOS_NULOS)),
      by = .(uf = SG_UF, cd_municipio_tse = as.integer(CD_MUNICIPIO), cd_cargo = CD_CARGO)]
  }))
}

# Junta code_muni (IBGE) e o id do cargo do painel; para se algum município do
# TSE não casar com o linkador.
com_ibge <- function(x, crosswalk) {
  x <- merge(x, data.table::as.data.table(crosswalk)[, .(uf, cd_municipio_tse, code_muni)],
             by = c("uf", "cd_municipio_tse"), all.x = TRUE)
  if (anyNA(x$code_muni)) {
    falta <- unique(x[is.na(code_muni), .(uf, cd_municipio_tse)])
    stop("Município do TSE sem código IBGE no linkador: ",
         paste(falta$uf, falta$cd_municipio_tse, collapse = ", "))
  }
  x$cargo <- CARGOS$id[match(x$cd_cargo, CARGOS$cd_cargo)]
  x
}

# Vetor denso na ordem de `municipios` (0 onde não houve voto). I(): o
# auto_unbox do jsonlite transformaria o vetor de 1 elemento do DF (um só
# município) em número solto, e o front-end espera lista.
denso <- function(codigos, valores, municipios) {
  v <- integer(length(municipios))
  v[match(codigos, municipios)] <- as.integer(valores)
  I(v)
}

# Pares esparsos [i0, votos, i1, votos, ...] (índice base 0).
esparso <- function(codigos, valores, municipios) {
  i <- match(codigos, municipios) - 1L
  o <- order(i)
  I(as.vector(rbind(i[o], as.integer(valores[o]))))
}

# Estrutura de um escopo (uma UF, ou "BR" sem candidatos).
montar_votos_escopo <- function(municipios, detalhe, partidos, candidatos_votos = NULL) {
  apt <- detalhe[cargo == "federal"]
  out <- list(
    municipios = I(municipios),
    aptos = denso(apt$code_muni, apt$aptos, municipios),
    comparecimento = denso(apt$code_muni, apt$comparecimento, municipios),
    cargos = list()
  )
  for (cg in CARGOS_EXPORT) {
    d <- detalhe[cargo == cg]
    p <- partidos[cargo == cg]
    p_tot <- p[, .(votos = sum(nominal + legenda)), by = .(sigla, code_muni)]
    siglas <- p_tot[, .(t = sum(votos)), by = sigla][t > 0][order(-t)]$sigla
    item <- list(
      validos = denso(d$code_muni, d$validos, municipios),
      brancos = denso(d$code_muni, d$brancos, municipios),
      nulos = denso(d$code_muni, d$nulos, municipios),
      partidos = stats::setNames(lapply(siglas, function(s) {
        q <- p_tot[sigla == s]
        denso(q$code_muni, q$votos, municipios)
      }), siglas)
    )
    if (!is.null(candidatos_votos)) {
      cv <- candidatos_votos[cargo == cg]
      # Sem candidato zerado (candidatura indeferida: votos anulados aparecem
      # com 0 em todos os municípios) e sem pares com 0 voto.
      cv <- cv[votos > 0]
      sqs <- cv[, .(t = sum(votos)), by = sq_candidato][order(-t)]$sq_candidato
      item$candidatos <- stats::setNames(lapply(sqs, function(s) {
        q <- cv[sq_candidato == s]
        esparso(q$code_muni, q$votos, municipios)
      }), sqs)
    }
    out$cargos[[cg]] <- item
  }
  out
}

# Confere as somas contra o detalhe oficial do TSE, por município e cargo:
#   proporcionais: soma dos partidos (nominal + legenda) = válidos
#   senador:       soma de todos os candidatos = válidos (sem legenda)
validar_votos_escopo <- function(v, rotulo) {
  for (cg in names(v$cargos)) {
    c <- v$cargos[[cg]]
    soma <- if (length(c$partidos) > 0) Reduce(`+`, c$partidos) else integer(length(v$municipios))
    if (!identical(as.numeric(soma), as.numeric(c$validos))) {
      i <- which(soma != c$validos)
      stop(sprintf("%s/%s: soma dos partidos != válidos em %d município(s), ex. %s (%s vs %s)",
                   rotulo, cg, length(i), v$municipios[i[1]], soma[i[1]], c$validos[i[1]]))
    }
  }
  invisible(TRUE)
}

# Dados de card dos exibidos de uma UF (mapa e hemiciclo).
montar_candidatos_uf <- function(cand) {
  sit <- ifelse(grepl("QP", cand$ds_situacao_tse), "QP",
                ifelse(grepl("M.DIA", cand$ds_situacao_tse), "média", NA_character_))
  lista <- lapply(seq_len(nrow(cand)), function(i) {
    c(list(nome = cand$nome[i], nome_completo = cand$nome_completo[i], sigla = cand$sigla[i],
           cargo = cand$cargo[i], ano = cand$ano[i], situacao = cand$situacao[i], sit = sit[i],
           ordem_suplente = cand$ordem_suplente[i], votos = cand$votos_total[i],
           numero = cand$nr_candidato[i], coligacao = cand$coligacao[i], idade = cand$idade[i],
           genero = cand$genero[i], ocupacao = cand$ocupacao[i], instrucao = cand$instrucao[i],
           foto = isTRUE(cand$tem_foto[i])),
      if (length(cand$redes[[i]]) > 0) list(redes = I(cand$redes[[i]])))
  })
  stats::setNames(lista, cand$sq_candidato)
}

# Ranking da visão "Brasil" (que não carrega candidatos por UF): por cargo,
# os N_RANKING deputados mais votados do país e os senadores eleitos em
# ANO, com o % sobre os válidos da UF de cada um.
montar_ranking_br <- function(candidatos, detalhe) {
  val_uf <- detalhe[, .(validos = sum(validos)), by = .(uf, cargo)]
  c26 <- data.table::as.data.table(candidatos)[ano == ANO & votos_total > 0]
  linhas <- function(x) {
    x <- x[order(-votos_total)]
    v <- val_uf$validos[match(paste(x$uf, x$cargo), paste(val_uf$uf, val_uf$cargo))]
    lapply(seq_len(nrow(x)), function(i) {
      list(sq = x$sq_candidato[i], nome = x$nome[i], sigla = x$sigla[i], uf = x$uf[i],
           votos = x$votos_total[i], pct_uf = round(x$votos_total[i] / v[i], 5),
           situacao = x$situacao[i], ordem_suplente = x$ordem_suplente[i], foto = isTRUE(x$tem_foto[i]))
    })
  }
  list(
    federal = linhas(c26[cargo == "federal"][order(-votos_total)][seq_len(N_RANKING)]),
    estadual = linhas(c26[cargo == "estadual"][order(-votos_total)][seq_len(N_RANKING)]),
    senador = linhas(c26[cargo == "senador" & situacao %in% "eleito"])
  )
}

# Vizinhança queen dos municípios de uma UF (para o LISA no navegador),
# calculada na geometria completa (não na simplificada do TopoJSON), na ordem
# de `municipios`; índices base 0. Município sem vizinho (ilha, ex. Fernando
# de Noronha; ou UF de 1 município, DF) fica com lista vazia -> "Não
# significante", como no painel de PE (validado contra o spdep).
vizinhos_queen <- function(mun_sf, municipios) {
  s <- mun_sf[match(municipios, mun_sf$code_muni), ]
  if (nrow(s) < 2) return(list(I(integer(0))))
  sf::sf_use_s2(FALSE)
  on.exit(sf::sf_use_s2(TRUE), add = TRUE)
  nb <- suppressWarnings(spdep::poly2nb(s, queen = TRUE))
  lapply(nb, function(v) I(as.integer(v[v > 0] - 1L)))
}

montar_meta <- function(partidos, federacoes, municipios) {
  regioes <- function(cod, nome) {
    u <- unique(data.frame(cod = as.character(cod), nome = nome))
    stats::setNames(as.list(u$nome), u$cod)
  }
  list(
    ano = ANO,
    ano_senado_anterior = ANO_SENADO_ANTERIOR,
    gerado_em = format(Sys.Date()),
    n_suplentes = N_SUPLENTES,
    fonte_ideologia = paste("Bolognesi, Ribeiro, Codato & Silva (2025), Opinião Pública 31,",
                            "e31120 — média dos experts em 2022 (0 = esquerda, 10 = direita)"),
    ufs = I(UFS_BRASIL),
    microrregioes = regioes(municipios$code_micro, municipios$name_micro),
    mesorregioes = regioes(municipios$code_meso, municipios$name_meso),
    partidos = stats::setNames(lapply(seq_len(nrow(partidos)), function(i) {
      list(rotulo = partidos$rotulo[i], cor = partidos$cor[i], ideologia = partidos$ideologia[i],
           federacao = if (is.na(partidos$nr_federacao[i])) NULL else as.character(partidos$nr_federacao[i]))
    }), partidos$sigla),
    federacoes = stats::setNames(lapply(seq_len(nrow(federacoes)), function(i) {
      list(sigla = federacoes$sigla[i], nome = federacoes$nome[i], cor = federacoes$cor[i],
           ideologia = round(federacoes$ideologia[i], 3), partidos = I(federacoes$partidos[[i]]))
    }), as.character(federacoes$nr))
  )
}
