// Aba Mapa: seletores (Cargo -> UF -> Unidade -> Agrupar -> Modo -> Alvo),
// legenda, resumo, popups e card. Um único mapa que muda conforme os filtros.
//
// Combinações válidas (normalizar()):
//   - Unidade "uf" só na visão Brasil.
//   - Agrupar por candidato só numa UF (candidatos são de cada UF). No
//     "quem lidera" de deputados o líder é exato: o pipeline exporta o 1º e
//     o 2º de toda unidade do mapa (ver exibidos em CLAUDE.md).
//   - LISA por município numa UF (vizinhança da própria UF -- misturar 27
//     eleições não tem sentido, ver clone; fora o DF, 1 município) ou pelas
//     subdivisões da capital; nunca por local de votação (pontos).
//   - Bairros/locais (piloto nas capitais) só numa UF; bairros só onde a
//     capital tem subdivisão na malha do IBGE.
const PainelMapa = (() => {
  const CARGOS = { federal: "Deputado Federal", estadual: "Deputado Estadual/Distrital", senador: "Senador" };
  const UNIDADES = {
    municipio: "Município", microrregiao: "Microrregião", mesorregiao: "Mesorregião", uf: "UF",
    subdivisao: "Bairro", local: "Local de votação",
  };
  const PLURAIS = {
    municipio: "municípios", microrregiao: "microrregiões", mesorregiao: "mesorregiões", uf: "UFs",
    subdivisao: "bairros", local: "locais de votação",
  };
  const DA_CAPITAL = new Set(["subdivisao", "local"]);
  const MODOS = { lider: "Quem lidera", continuo: "Desempenho (contínuo)", lisa: "Clusters (LISA)" };

  let meta = null;
  let capitais = {};
  let aoMudarEstado = () => {};
  let sequencia = 0;
  let vistaDesenhada = null;
  const estado = { cargo: "federal", uf: "BR", unidade: "municipio", agrupar: "partido", modo: "lider", alvo: "" };
  const el = (id) => document.getElementById(id);

  function capitalDe(uf) {
    return capitais[uf] || null;
  }

  // Rótulo da unidade (singular ou plural, minúsculo para o plural); a
  // subdivisão da capital tem nome próprio (bairros, distritos, RAs...).
  function rotuloUnidade(unidade, plural = false) {
    const cap = capitalDe(estado.uf);
    if (unidade === "subdivisao" && cap && cap.subdivisao) {
      return plural ? cap.subdivisao.rotulo.toLowerCase() : cap.subdivisao.singular;
    }
    return plural ? PLURAIS[unidade] : UNIDADES[unidade];
  }

  // --- regras de combinação ---------------------------------------------------
  function candidatoPermitido(e) {
    return e.uf !== "BR";
  }

  function lisaPermitida(e) {
    if (e.unidade === "subdivisao") return (capitalDe(e.uf) || {}).n_subdivisoes >= 5;
    return e.uf !== "BR" && e.uf !== "DF" && e.unidade === "municipio";
  }

  function unidadePermitida(e) {
    if (!UNIDADES[e.unidade]) return false;
    if (e.unidade === "uf") return e.uf === "BR";
    if (DA_CAPITAL.has(e.unidade)) {
      const cap = capitalDe(e.uf);
      return e.uf !== "BR" && !!cap && (e.unidade === "local" || !!cap.subdivisao);
    }
    return true;
  }

  function normalizar() {
    if (!CARGOS[estado.cargo]) estado.cargo = "federal";
    if (estado.uf !== "BR" && !NOMES_UF[estado.uf]) estado.uf = "BR";
    if (!unidadePermitida(estado)) estado.unidade = "municipio";
    if (!MODOS[estado.modo]) estado.modo = "lider";
    if (estado.modo === "lisa" && !lisaPermitida(estado)) estado.modo = "continuo";
    if (!["partido", "federacao", "candidato"].includes(estado.agrupar)) estado.agrupar = "partido";
    if (estado.agrupar === "candidato" && !candidatoPermitido(estado)) {
      estado.agrupar = "partido";
      estado.alvo = "";
    }
  }

  // --- controles ------------------------------------------------------------------
  function opcoes(select, pares, valor) {
    select.innerHTML = pares
      .map(([v, rot, desab]) => `<option value="${Util.esc(v)}"${desab ? " disabled" : ""}>${Util.esc(rot)}</option>`)
      .join("");
    select.value = valor;
  }

  function sincronizarControles() {
    opcoes(el("sel-cargo"), Object.entries(CARGOS), estado.cargo);
    opcoes(el("sel-uf"), [["BR", "Brasil"], ...UFS.map((u) => [u, NOMES_UF[u]])], estado.uf);
    const cap = capitalDe(estado.uf);
    opcoes(
      el("sel-unidade"),
      Object.keys(UNIDADES)
        .filter((u) => unidadePermitida({ ...estado, unidade: u }))
        .map((u) => [u, DA_CAPITAL.has(u) ? `${Util.titulo(rotuloUnidade(u, true))} — ${cap.nome}` : UNIDADES[u]]),
      estado.unidade
    );
    opcoes(el("sel-modo"), Object.entries(MODOS).map(([m, r]) => [m, r, m === "lisa" && !lisaPermitida(estado)]), estado.modo);
    el("seg-agrupar-mapa").querySelectorAll("button").forEach((b) => {
      const v = b.dataset.valor;
      b.disabled = v === "candidato" && !candidatoPermitido(estado);
      b.title = b.disabled ? "Escolha uma UF para ver candidatos" : "";
      b.setAttribute("aria-pressed", String(v === estado.agrupar));
    });
    el("label-alvo").hidden = estado.modo === "lider";
  }

  function ligarControles() {
    // Trocar cargo ou UF muda o conjunto de candidatos/partidos: o alvo volta
    // ao mais votado. Os demais filtros preservam a seleção.
    const aoTrocar = (campo) => (ev) => {
      estado[campo] = ev.target.value;
      if (campo === "cargo" || campo === "uf") estado.alvo = "";
      atualizar();
    };
    el("sel-cargo").addEventListener("change", aoTrocar("cargo"));
    el("sel-uf").addEventListener("change", aoTrocar("uf"));
    el("sel-unidade").addEventListener("change", aoTrocar("unidade"));
    el("sel-modo").addEventListener("change", aoTrocar("modo"));
    el("sel-alvo").addEventListener("change", aoTrocar("alvo"));
    el("seg-agrupar-mapa").querySelectorAll("button").forEach((b) => {
      b.addEventListener("click", () => {
        if (b.disabled || estado.agrupar === b.dataset.valor) return;
        estado.agrupar = b.dataset.valor;
        estado.alvo = "";
        atualizar();
      });
    });
  }

  function rotuloSituacao(i) {
    return i.situacao === "eleito" ? "eleito" : i.situacao === "suplente" ? `${i.ordem_suplente}º sup.` : "não eleito";
  }

  // Rótulo no seletor de alvo (a lista vem do mais ao menos votado no
  // escopo): candidato com partido, situação e votos; partido com o %.
  function rotuloAlvo(e) {
    if (!e.info) return `${e.rotulo} — ${Util.pctBr(e.fracEscopo)}`;
    return `${e.rotulo} · ${rotuloSituacao(e.info)} · ${Math.round(e.total).toLocaleString("pt-BR")}`;
  }

  // --- desenho ----------------------------------------------------------------------
  async function atualizar({ manterVista = false } = {}) {
    normalizar();
    sincronizarControles();
    aoMudarEstado();
    const pedido = ++sequencia;
    const status = el("status");
    status.textContent = "Carregando...";
    const naCapital = DA_CAPITAL.has(estado.unidade);
    let escopo;
    try {
      escopo = naCapital
        ? await Analise.carregarCapital(estado.uf, capitalDe(estado.uf))
        : await Analise.carregarEscopo(estado.uf);
    } catch (e) {
      status.textContent = `Erro ao carregar dados: ${e.message}`;
      throw e;
    }
    if (pedido !== sequencia) return;

    const uns = Analise.unidades(escopo, estado.unidade, meta);
    const ents = Analise.entidades(escopo, estado.cargo, estado.agrupar, meta);
    const tot = Analise.totais(escopo, estado.cargo, uns);
    ents.forEach((e) => {
      e.fracEscopo = tot.escopo.validos > 0 ? e.total / tot.escopo.validos : 0;
    });

    // alvo (contínuo/LISA)
    let alvo = null;
    if (estado.modo !== "lider") {
      alvo = ents.find((e) => e.chave === estado.alvo) || ents[0] || null;
      estado.alvo = alvo ? alvo.chave : "";
      opcoes(el("sel-alvo"), ents.map((e) => [e.chave, rotuloAlvo(e)]), estado.alvo);
      el("label-alvo-titulo").textContent =
        estado.agrupar === "candidato" ? "Candidato" : estado.agrupar === "federacao" ? "Federação / partido" : "Partido";
    }
    aoMudarEstado();

    const tema = Mapa.tema();
    const SEM_DADO = { fillColor: "#999999", fillOpacity: 0.35 };
    let estiloUnidade;
    let infoUnidade = () => "";
    let legenda;

    if (estado.modo === "lider") {
      const { lideres } = Analise.lideres(ents, uns, tot.validos);
      // Partido: cor do líder, escura/clara pela folga (como no clone).
      // Candidato: cada líder com um tom próprio da cor do partido (vários
      // candidatos do mesmo partido lideram em lugares diferentes); a folga
      // fica no popup.
      const tons = estado.agrupar === "candidato" ? tonsCandidatos(ents, lideres) : null;
      const corLider = (l) =>
        tons ? tons.get(l.k) : l.intensidade === "alta" ? Cores.escurecer(ents[l.k].cor, 0.25) : Cores.interpolarComBranco(ents[l.k].cor, 0.55);
      estiloUnidade = (u) => (lideres[u] ? { fillColor: corLider(lideres[u]), fillOpacity: 0.9 } : SEM_DADO);
      infoUnidade = (u) => {
        const l = lideres[u];
        return l ? `<div class="popup-nota">Lidera ${Util.esc(ents[l.k].rotulo)} com folga de ${Util.pp(l.margem)}</div>` : "";
      };
      legenda = legendaLider(ents, lideres, tons);
    } else if (estado.modo === "continuo") {
      const fr = alvo ? Analise.fracoes(alvo, uns, tot.validos) : new Float64Array(uns.n);
      const max = Analise.teto(fr);
      estiloUnidade = (u) =>
        tot.validos[u] > 0 ? { fillColor: Cores.interpolarComBranco(alvo.cor, fr[u] / max), fillOpacity: 0.9 } : SEM_DADO;
      legenda = legendaContinuo(alvo, max);
    } else if (escopo.capital) {
      // LISA sobre o % por subdivisão (bairros sem local de votação ficam
      // fora da vizinhança e em cinza).
      const fr = Analise.fracoes(alvo, uns, tot.validos);
      const classeUn = Analise.lisaSubdivisoes(escopo, uns, fr, tot.validos);
      estiloUnidade = (u) =>
        classeUn[u] ? { fillColor: Cores.corLisa(classeUn[u], tema), fillOpacity: Cores.opacidadeLisa(classeUn[u], tema) } : SEM_DADO;
      infoUnidade = (u) =>
        `<div class="popup-nota">Cluster: <b>${Util.esc(classeUn[u] ? LISA.nome(classeUn[u]) : "sem local de votação")}</b></div>`;
      legenda = legendaLisa(classeUn.filter(Boolean), tema);
    } else {
      // LISA: % de válidos por município, na ordem do arquivo de votos (a
      // mesma da vizinhança); depois levado à ordem das feições.
      const c = escopo.votos.cargos[estado.cargo];
      const fracMun = Array.from(alvo.votos, (v, i) => (c.validos[i] > 0 ? v / c.validos[i] : 0));
      const classes = Analise.lisa(escopo, fracMun);
      const classeUn = new Array(uns.n);
      classes.forEach((cl, i) => {
        if (uns.unidadeDe[i] >= 0) classeUn[uns.unidadeDe[i]] = cl;
      });
      estiloUnidade = (u) => ({ fillColor: Cores.corLisa(classeUn[u], tema), fillOpacity: Cores.opacidadeLisa(classeUn[u], tema) });
      infoUnidade = (u) => `<div class="popup-nota">Cluster: <b>${Util.esc(classeUn[u] ? LISA.nome(classeUn[u]) : "—")}</b></div>`;
      legenda = legendaLisa(classes, tema);
    }

    const indice = new Map(uns.features.map((f, u) => [f, u]));
    // Votos de cada entidade por unidade: só no 1º popup, uma vez por desenho.
    let agregados = null;
    const popup = (f) => {
      const u = indice.get(f);
      if (!agregados) agregados = ents.map((e) => Analise.agregar(e.votos, uns));
      const votosUn = ents.map((e, k) => ({ k, v: agregados[k][u] }));
      return htmlPopup(f, u, ents, votosUn, tot.validos[u], alvo, escopo) + infoUnidade(u);
    };

    // Painel da direita antes do mapa: o enquadramento desconta a largura dele.
    renderDireito(escopo, ents, alvo, tot.escopo.validos);

    const contorno = estado.unidade === "uf" ? null : Analise.contornoUfs(escopo, meta, estado.unidade);
    Mapa.renderizar({
      features: uns.features,
      estilo: (f) => estiloUnidade(indice.get(f)),
      popup,
      contorno,
      ajustarVista: !manterVista && vistaDesenhada !== escopo.chave,
    });
    vistaDesenhada = escopo.chave;

    renderResumo(tot.escopo);
    el("legenda-mapa").innerHTML = legenda + (escopo.capital ? notaCapital(escopo, uns) : "");
    status.textContent = "";
  }

  function htmlPopup(f, u, ents, votosUn, validos, alvo, escopo) {
    const titulo = `${Util.esc(f.properties.nome)}${escopo.uf === "BR" && f.properties.uf ? ` · ${Util.esc(f.properties.uf)}` : ""}`;
    const ordenados = [...votosUn].sort((a, b) => b.v - a.v).filter((x) => x.v > 0);
    const top = ordenados.slice(0, 5);
    if (alvo) {
      const kAlvo = ents.indexOf(alvo);
      if (kAlvo >= 0 && !top.some((x) => x.k === kAlvo)) {
        const pos = ordenados.findIndex((x) => x.k === kAlvo);
        if (pos >= 0) top.push({ ...ordenados[pos], pos: pos + 1 });
      }
    }
    const linhas = top
      .map((x) => {
        const e = ents[x.k];
        const destaque = alvo && e === alvo ? " class=\"popup-alvo\"" : "";
        const pos = x.pos ? `${x.pos}º ` : "";
        return `<tr${destaque}><td><span class="swatch" style="background:${e.cor}"></span></td>
          <td>${pos}${Util.esc(e.rotulo)}</td><td class="num">${Util.pctBr(validos ? x.v / validos : 0)}</td>
          <td class="num suave">${Math.round(x.v).toLocaleString("pt-BR")}</td></tr>`;
      })
      .join("");
    const detalhe = f.properties.detalhe ? `<div class="popup-nota">${Util.esc(f.properties.detalhe)}</div>` : "";
    return `<div class="popup"><b>${titulo}</b>${detalhe}
      <div class="popup-nota">${Math.round(validos).toLocaleString("pt-BR")} votos válidos · ${Util.esc(CARGOS[estado.cargo])}</div>
      <table>${linhas}</table></div>`;
  }

  // --- legendas -------------------------------------------------------------------
  // Tom de cada candidato líder: dentro de cada partido, o que lidera em mais
  // unidades fica com a cor cheia e os seguintes alternam clareado/escurecido.
  function tonsCandidatos(ents, lideres) {
    const cont = contarLideres(lideres);
    const porPartido = new Map();
    [...cont.entries()].sort((a, b) => b[1] - a[1]).forEach(([k]) => {
      const s = ents[k].sigla;
      if (!porPartido.has(s)) porPartido.set(s, []);
      porPartido.get(s).push(k);
    });
    const VARIACOES = [
      (c) => c, (c) => Cores.interpolarComBranco(c, 0.45), (c) => Cores.escurecer(c, 0.4),
      (c) => Cores.interpolarComBranco(c, 0.7), (c) => Cores.escurecer(c, 0.6), (c) => Cores.interpolarComBranco(c, 0.25),
    ];
    const tons = new Map();
    porPartido.forEach((ks) => ks.forEach((k, i) => tons.set(k, VARIACOES[i % VARIACOES.length](ents[k].cor))));
    return tons;
  }

  function contarLideres(lideres) {
    const cont = new Map();
    lideres.forEach((l) => {
      if (l) cont.set(l.k, (cont.get(l.k) || 0) + 1);
    });
    return cont;
  }

  function legendaLider(ents, lideres, tons) {
    const cont = contarLideres(lideres);
    const nome = rotuloUnidade(estado.unidade, true);
    const itens = [...cont.entries()]
      .sort((a, b) => b[1] - a[1])
      .map(([k, n]) => `<div class="item"><span class="swatch" style="background:${tons ? tons.get(k) : Cores.escurecer(ents[k].cor, 0.25)}"></span>
        <span>${Util.esc(ents[k].rotulo)}</span><span class="n">${n}</span></div>`)
      .join("");
    const nota = tons
      ? "Cada candidato com um tom da cor do partido. A folga sobre o 2º colocado aparece ao clicar na unidade."
      : "Tom mais escuro = folga maior sobre o 2º colocado (acima da mediana das vitórias daquele partido); mais claro = folga menor.";
    return `<div class="legenda-cabecalho"><span>Lidera em</span><span>${Util.esc(nome)}</span></div>${itens}
      <div class="legenda-nota">${nota}</div>`;
  }

  function legendaContinuo(alvo, max) {
    if (!alvo) return "";
    const grad = [0, 0.25, 0.5, 0.75, 1].map((t) => Cores.interpolarComBranco(alvo.cor, t)).join(",");
    return `<div class="escala" style="background:linear-gradient(90deg,${grad})"></div>
      <div class="escala-rotulos"><span>0%</span><span>≥ ${Util.pctBr(max)}</span></div>
      <div class="legenda-nota">% dos votos válidos em cada ${Util.esc(rotuloUnidade(estado.unidade).toLowerCase())}.
      No escopo: <b>${Util.pctBr(alvo.fracEscopo)}</b> (${Math.round(alvo.total).toLocaleString("pt-BR")} votos).
      A cor satura no percentil 98, para um reduto isolado não apagar o resto do mapa.</div>`;
  }

  function legendaLisa(classes, tema) {
    const cont = {};
    classes.forEach((c) => {
      cont[c] = (cont[c] || 0) + 1;
    });
    const itens = LISA.NIVEIS.map((n) => `<div class="item"><span class="swatch" style="background:${Cores.corLisa(n, tema)}"></span>
      <span>${LISA.nome(n)}</span><span class="n">${cont[n] || 0}</span></div>`).join("");
    const um = rotuloUnidade(estado.unidade).toLowerCase();
    const varios = rotuloUnidade(estado.unidade, true);
    return `${itens}<div class="legenda-nota">Tipologia de Terron (2009) sobre o Moran local do % dos válidos por
      ${Util.esc(um)} (vizinhança queen, p &lt; 0,05). Território forte: votação alta cercada de ${Util.esc(varios)}
      também altos; território fraco: baixa cercada de baixos; forte isolado: alta cercada de baixos; fraco isolado:
      baixa cercada de altos.</div>`;
  }

  // Fonte e cobertura das visões da capital.
  function notaCapital(escopo, uns) {
    const cap = capitalDe(estado.uf);
    const n = escopo.n;
    let texto;
    if (estado.unidade === "local") {
      const fora = n - uns.n;
      texto = `${uns.n.toLocaleString("pt-BR")} locais de votação de ${Util.esc(cap.nome)}, círculo proporcional ao
        eleitorado (cadastro do TSE)${fora > 0 ? `; ${fora} sem coordenada ficam fora do mapa, mas entram no resumo` : ""}.`;
    } else {
      const sem = Array.from(uns.unidadeDe).filter((u) => u < 0).length;
      texto = `Soma dos locais de votação que caem em cada ${Util.esc(rotuloUnidade("subdivisao").toLowerCase())}
        (malha do IBGE, Censo 2022); cinza = sem local de votação${
          sem > 0 ? `. ${sem} de ${n} locais ficam fora de todos (área rural, ilha ou sem coordenada) e só entram no resumo` : ""
        }.`;
    }
    return `<div class="legenda-nota">${texto} Votos por seção do TSE.</div>`;
  }

  function renderResumo(t) {
    const comp = t.aptos ? t.comparecimento / t.aptos : 0;
    const votos = t.validos + t.brancos + t.nulos;
    el("resumo-mapa").innerHTML = `
      <span title="Comparecimento sobre o eleitorado apto">Comparecimento <b>${Util.pctBr(comp)}</b></span>
      <span>Válidos <b>${Math.round(t.validos).toLocaleString("pt-BR")}</b></span>
      <span>Brancos <b>${Util.pctBr(votos ? t.brancos / votos : 0)}</b></span>
      <span>Nulos <b>${Util.pctBr(votos ? t.nulos / votos : 0)}</b></span>`;
  }

  // --- painel da direita --------------------------------------------------------
  // Contínuo/LISA de um candidato: card dele. Quem lidera: ranking dos mais
  // votados no escopo (senador: eleitos primeiro). Contínuo/LISA de partido
  // ou federação: ranking dos candidatos dele. Clicar num nome abre o mapa
  // contínuo do candidato.
  const N_RANKING = 10;

  function renderDireito(escopo, ents, alvo, validosEscopo) {
    const painel = el("painel-direito");
    const ehCand = alvo && alvo.info;
    Card.renderizar(el("card-mapa"), { sq: ehCand ? alvo.chave : null, uf: estado.uf, meta });
    if (ehCand) {
      el("direito-titulo").innerHTML = "";
      el("ranking-mapa").innerHTML = "";
      painel.hidden = false;
      return;
    }
    const membros = alvo ? new Set(alvo.membros) : null;
    const linhas = (escopo.uf === "BR" ? linhasBrasil(escopo, membros) : linhasEscopo(escopo, membros, validosEscopo))
      .map((l, k) => ({ ...l, pos: k + 1 })); // posição no escopo (eleitos e demais seguem a mesma)
    const onde = escopo.uf === "BR" ? "Brasil" : escopo.capital ? escopo.votos.nome : NOMES_UF[escopo.uf];
    const deQuem = alvo ? ` · ${Util.esc(alvo.rotulo)}` : "";
    el("direito-titulo").innerHTML = `Mais votados${deQuem}
      <span class="sub">${Util.esc(CARGOS[estado.cargo])} · ${Util.esc(onde)}</span>`;
    const lista = (itens) => `<ol class="ranking">${itens.map(htmlLinhaRanking).join("")}</ol>`;
    let html;
    if (linhas.length === 0) {
      html = `<p class="legenda-nota">Nenhum candidato ${alvo ? "deste partido " : ""}entre os mais votados.</p>`;
    } else if (estado.cargo === "senador" && !alvo) {
      const eleitos = linhas.filter((l) => l.situacao === "eleito");
      const demais = linhas.filter((l) => l.situacao !== "eleito").slice(0, N_RANKING);
      html = `<div class="ranking-secao">Eleitos</div>${lista(eleitos)}${
        demais.length ? `<div class="ranking-secao">Demais candidatos</div>${lista(demais)}` : ""
      }`;
    } else {
      html = lista(linhas.slice(0, N_RANKING));
    }
    const nota = escopo.uf === "BR"
      ? `<p class="legenda-nota">% sobre os votos válidos da UF de cada candidato.</p>`
      : "";
    el("ranking-mapa").innerHTML = html + nota;
    el("ranking-mapa").querySelectorAll("li[data-sq]").forEach((li) => {
      const abrir = () => mostrarCandidato({ cargo: estado.cargo, uf: li.dataset.uf, sq: li.dataset.sq });
      li.addEventListener("click", abrir);
      li.addEventListener("keydown", (ev) => {
        if (ev.key === "Enter" || ev.key === " ") {
          ev.preventDefault();
          abrir();
        }
      });
    });
    painel.hidden = false;
  }

  // Candidatos do escopo (UF ou capital), do mais ao menos votado ali. O
  // pipeline exporta os 10 mais votados de cada UF e de cada capital, então o
  // topo do ranking está completo mesmo entre não eleitos.
  function linhasEscopo(escopo, membros, validosEscopo) {
    return Analise.entidades(escopo, estado.cargo, "candidato", meta)
      .filter((e) => !membros || membros.has(e.sigla))
      .map((e) => ({
        sq: e.chave, uf: escopo.uf, nome: e.nome, sigla: e.sigla, foto: e.info.foto,
        situacao: e.info.situacao, ordem_suplente: e.info.ordem_suplente,
        votos: e.total, pct: validosEscopo > 0 ? e.total / validosEscopo : 0,
      }));
  }

  // Visão Brasil: ranking nacional pronto no BR.json (sem candidatos por UF).
  function linhasBrasil(escopo, membros) {
    return ((escopo.votos.ranking || {})[estado.cargo] || [])
      .filter((r) => !membros || membros.has(r.sigla))
      .map((r) => ({ ...r, pct: r.pct_uf }));
  }

  function htmlLinhaRanking(l) {
    const p = meta.partidos[l.sigla] || { cor: "#999999", rotulo: l.sigla };
    const sit = rotuloSituacao(l);
    const ufTxt = estado.uf === "BR" ? ` · ${Util.esc(l.uf)}` : "";
    return `<li data-sq="${Util.esc(l.sq)}" data-uf="${Util.esc(l.uf)}" tabindex="0"
        class="${l.situacao === "eleito" ? "rk-eleito" : ""}" title="Ver no mapa">
      <span class="rk-pos">${l.pos}</span>
      ${Card.htmlFoto({ sq: l.sq, nome: l.nome, foto: l.foto }, p.cor)}
      <span><span class="rk-nome">${Util.esc(l.nome)}</span>
        <span class="rk-sub"><span class="swatch" style="background:${Util.esc(p.cor)}"></span>${Util.esc(p.rotulo)}${ufTxt} · ${sit}</span></span>
      <span class="rk-num"><b>${Util.pctBr(l.pct)}</b><span>${Math.round(l.votos).toLocaleString("pt-BR")}</span></span>
    </li>`;
  }

  // No celular (painel principal como faixa inferior) o painel da direita
  // entra no fim do painel principal; no desktop flutua à direita.
  function posicionarDireito() {
    const painel = el("painel-direito");
    const celular = window.matchMedia("(max-width: 700px)");
    const posicionar = () => {
      if (celular.matches) el("painel-mapa").appendChild(painel);
      else document.body.appendChild(painel);
    };
    celular.addEventListener("change", posicionar);
    posicionar();
  }

  // --- API ------------------------------------------------------------------------
  function iniciar(inicial, metaCarregado, capitaisCarregado, callbackEstado) {
    meta = metaCarregado;
    capitais = capitaisCarregado || {};
    aoMudarEstado = callbackEstado || aoMudarEstado;
    ["cargo", "uf", "unidade", "agrupar", "modo", "alvo"].forEach((k) => {
      if (inicial[k]) estado[k] = inicial[k];
    });
    ligarControles();
    posicionarDireito();
    Mapa.definirAoRedesenhar(() => atualizar({ manterVista: true }));
    return atualizar();
  }

  // Vindo do hemiciclo ou do ranking: mapa contínuo do candidato, na UF
  // dele. Se já estava em bairros/locais da capital dessa UF, continua lá.
  function mostrarCandidato({ cargo, uf, sq }) {
    const unidade = uf === estado.uf && DA_CAPITAL.has(estado.unidade) ? estado.unidade : "municipio";
    Object.assign(estado, { cargo, uf, unidade, agrupar: "candidato", modo: "continuo", alvo: sq });
    return atualizar();
  }

  function estadoUrl() {
    return { ...estado };
  }

  return { iniciar, mostrarCandidato, estadoUrl };
})();
