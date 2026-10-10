// Aba Composição: hemiciclo da Casa escolhida (Câmara, Senado ou
// Assembleia de uma UF), agrupado por partido ou federação, com destaque de
// bancada estadual, destaque de grupo (clique na legenda) e card do eleito
// (clique na cadeira). Dados: output/composicao.json (cadeiras) + meta
// (partidos/federações); o card vem de Card (candidatos/{UF}.json).
const Composicao = (() => {
  let dados = null;
  let meta = null;
  let desenho = null; // retorno de Hemiciclo.desenhar()
  const estado = { casa: "camara", uf: "SP", destaque: "", agrupar: "partido", grupo: null, sq: null };
  let aoMudarEstado = () => {};

  const el = (id) => document.getElementById(id);

  function idCasa() {
    return estado.casa === "assembleia" ? `assembleia_${estado.uf}` : estado.casa;
  }

  // --- grupos (fatias do hemiciclo) ---------------------------------------
  function grupoDaCadeira(c) {
    const p = meta.partidos[c.sigla];
    if (estado.agrupar === "federacao" && p.federacao) {
      const f = meta.federacoes[p.federacao];
      return { chave: `F${p.federacao}`, rotulo: f.sigla, nome: f.nome, cor: f.cor, ideologia: f.ideologia };
    }
    return { chave: c.sigla, rotulo: p.rotulo, nome: null, cor: p.cor, ideologia: p.ideologia };
  }

  const ideologiaOrd = (v) => (v === null || v === undefined ? Infinity : v);

  function montarGrupos(cadeiras) {
    const porChave = new Map();
    cadeiras.forEach((c) => {
      const g = grupoDaCadeira(c);
      if (!porChave.has(g.chave)) porChave.set(g.chave, { ...g, cadeiras: [] });
      porChave.get(g.chave).cadeiras.push(c);
    });
    const grupos = [...porChave.values()].sort(
      (a, b) => ideologiaOrd(a.ideologia) - ideologiaOrd(b.ideologia) || a.rotulo.localeCompare(b.rotulo)
    );
    // Dentro do grupo: partidos da federação contíguos (esquerda->direita),
    // depois eleitos de 2026 antes dos de 2022 (Senado), UF e nome.
    grupos.forEach((g) => {
      g.cadeiras.sort((a, b) => {
        const pa = meta.partidos[a.sigla];
        const pb = meta.partidos[b.sigla];
        return (
          ideologiaOrd(pa.ideologia) - ideologiaOrd(pb.ideologia) ||
          a.sigla.localeCompare(b.sigla) ||
          b.ano - a.ano ||
          a.uf.localeCompare(b.uf) ||
          a.nome.localeCompare(b.nome)
        );
      });
    });
    return grupos;
  }

  // --- render ---------------------------------------------------------------
  function render() {
    const casa = dados.casas[idCasa()];
    const grupos = montarGrupos(casa.cadeiras);
    const ehSenado = estado.casa === "senado";

    el("label-uf-casa").hidden = estado.casa !== "assembleia";
    el("label-destaque").hidden = estado.casa === "assembleia";

    let titulo = casa.nome;
    if (estado.destaque && estado.casa !== "assembleia") {
      const n = casa.cadeiras.filter((c) => c.uf === estado.destaque).length;
      titulo += ` — bancada de ${NOMES_UF[estado.destaque]} (${n})`;
    }
    el("hemiciclo-titulo").textContent = titulo;
    el("hemiciclo-nota").textContent = ehSenado
      ? `Círculo cheio: eleito em ${meta.ano} (mandato até 2035). Vazado: eleito em ${meta.ano_senado_anterior} (mandato até 2031), pelo partido da eleição.`
      : "";

    desenho = Hemiciclo.desenhar(el("hemiciclo-svg"), grupos, {
      vazada: (c) => ehSenado && c.ano === meta.ano_senado_anterior,
    });
    desenho.circulos.forEach((item) => {
      item.el.addEventListener("mouseenter", (ev) => mostrarTooltip(ev, item));
      item.el.addEventListener("mousemove", posicionarTooltip);
      item.el.addEventListener("mouseleave", esconderTooltip);
      item.el.addEventListener("click", () => selecionar(item.cadeira.sq));
    });

    aplicarDestaques();
    renderLegenda(grupos, casa);
    renderCard();
    aoMudarEstado();
  }

  function apagada(item) {
    if (estado.destaque && estado.casa !== "assembleia" && item.cadeira.uf !== estado.destaque) return true;
    if (estado.grupo && item.grupo.chave !== estado.grupo) return true;
    return false;
  }

  function aplicarDestaques() {
    desenho.circulos.forEach((item) => item.el.classList.toggle("apagada", apagada(item)));
    desenho.marcar(desenho.circulos.find((item) => item.cadeira.sq === estado.sq) || null);
  }

  function renderLegenda(grupos, casa) {
    const cont = el("legenda-composicao");
    const filtroUf = estado.destaque && estado.casa !== "assembleia" ? estado.destaque : null;
    const conta = (lista) => (filtroUf ? lista.filter((c) => c.uf === filtroUf).length : lista.length);
    const total = conta(casa.cadeiras);

    let html = `<div class="legenda-cabecalho"><span>Esquerda → direita</span><span>${
      filtroUf ? `bancada ${filtroUf}` : "cadeiras"
    }</span></div>`;
    grupos.forEach((g) => {
      const n = conta(g.cadeiras);
      const classes = ["legenda-grupo"];
      if ((estado.grupo && estado.grupo !== g.chave) || n === 0) classes.push("apagado");
      let membros = "";
      if (g.chave.startsWith("F")) {
        const porPartido = {};
        g.cadeiras.forEach((c) => {
          if (!filtroUf || c.uf === filtroUf) porPartido[c.sigla] = (porPartido[c.sigla] || 0) + 1;
        });
        membros = `<span class="membros">${Object.entries(porPartido)
          .map(([s, k]) => `${Util.esc(meta.partidos[s].rotulo)} ${k}`)
          .join(" · ")}</span>`;
      }
      html += `<button type="button" class="${classes.join(" ")}" data-grupo="${Util.esc(g.chave)}"
        title="${Util.esc(g.nome || g.rotulo)}" aria-pressed="${estado.grupo === g.chave}">
        <span class="swatch" style="background:${g.cor}"></span>
        <span>${Util.esc(g.rotulo)}</span>
        <span class="n">${n}</span>
        <span class="pct">${total ? Util.pct(n / total) : ""}</span>
        ${membros}
      </button>`;
    });
    if (estado.grupo) {
      html += `<div class="legenda-acoes"><button type="button" class="link-botao" id="btn-limpar-grupo">Mostrar todos</button></div>`;
    }
    cont.innerHTML = html;

    cont.querySelectorAll(".legenda-grupo").forEach((b) => {
      b.addEventListener("click", () => {
        estado.grupo = estado.grupo === b.dataset.grupo ? null : b.dataset.grupo;
        aplicarDestaques();
        renderLegenda(grupos, casa);
        aoMudarEstado();
      });
    });
    const limpar = el("btn-limpar-grupo");
    if (limpar) {
      limpar.addEventListener("click", () => {
        estado.grupo = null;
        aplicarDestaques();
        renderLegenda(grupos, casa);
        aoMudarEstado();
      });
    }
  }

  // --- tooltip e card ----------------------------------------------------------
  function mostrarTooltip(ev, item) {
    const c = item.cadeira;
    const tip = el("tooltip");
    tip.innerHTML = `${Card.htmlFoto(c, item.grupo.cor)}<div><b>${Util.esc(c.nome)}</b><br>${Util.esc(
      meta.partidos[c.sigla].rotulo
    )} · ${Util.esc(c.uf)}</div>`;
    tip.hidden = false;
    posicionarTooltip(ev);
  }

  function posicionarTooltip(ev) {
    const tip = el("tooltip");
    const x = Math.min(ev.clientX + 14, window.innerWidth - tip.offsetWidth - 8);
    const y = Math.min(ev.clientY + 14, window.innerHeight - tip.offsetHeight - 8);
    tip.style.left = `${x}px`;
    tip.style.top = `${y}px`;
  }

  function esconderTooltip() {
    el("tooltip").hidden = true;
  }

  function selecionar(sq) {
    estado.sq = estado.sq === sq ? null : sq;
    aplicarDestaques();
    renderCard();
    aoMudarEstado();
  }

  function renderCard() {
    const c = estado.sq && dados.casas[idCasa()].cadeiras.find((x) => x.sq === estado.sq);
    Card.renderizar(el("card-eleito"), {
      sq: c ? c.sq : null,
      uf: c ? c.uf : null,
      meta,
      aoFechar: () => selecionar(estado.sq),
    });
  }

  // --- seletores --------------------------------------------------------------
  function popularSeletores() {
    el("sel-uf-casa").innerHTML = UFS.map((uf) => `<option value="${uf}">${NOMES_UF[uf]}</option>`).join("");
    el("sel-destaque").innerHTML =
      `<option value="">Todas as UFs</option>` + UFS.map((uf) => `<option value="${uf}">${NOMES_UF[uf]}</option>`).join("");
  }

  function sincronizarControles() {
    el("sel-casa").value = estado.casa;
    el("sel-uf-casa").value = estado.uf;
    el("sel-destaque").value = estado.destaque;
    el("seg-agrupar").querySelectorAll("button").forEach((b) => {
      b.setAttribute("aria-pressed", String(b.dataset.valor === estado.agrupar));
    });
  }

  function ligarControles() {
    el("sel-casa").addEventListener("change", (e) => {
      estado.casa = e.target.value;
      estado.grupo = null;
      estado.sq = null;
      render();
    });
    el("sel-uf-casa").addEventListener("change", (e) => {
      estado.uf = e.target.value;
      estado.grupo = null;
      estado.sq = null;
      render();
    });
    el("sel-destaque").addEventListener("change", (e) => {
      estado.destaque = e.target.value;
      render();
    });
    el("seg-agrupar").querySelectorAll("button").forEach((b) => {
      b.addEventListener("click", () => {
        if (estado.agrupar === b.dataset.valor) return;
        estado.agrupar = b.dataset.valor;
        estado.grupo = null;
        sincronizarControles();
        render();
      });
    });
  }

  // inicial: valores lidos da URL (validados aqui; inválido cai no padrão).
  // metaCarregado: output/meta.json (carregado uma vez em main.js, comum ao mapa).
  async function iniciar(inicial, metaCarregado, callbackEstado) {
    aoMudarEstado = callbackEstado || aoMudarEstado;
    meta = metaCarregado;
    dados = await Dados.carregarJson("output/composicao.json");
    if (["camara", "senado", "assembleia"].includes(inicial.casa)) estado.casa = inicial.casa;
    if (UFS.includes(inicial.uf)) estado.uf = inicial.uf;
    if (UFS.includes(inicial.destaque)) estado.destaque = inicial.destaque;
    if (["partido", "federacao"].includes(inicial.agrupar)) estado.agrupar = inicial.agrupar;
    el("fonte-ideologia").textContent = `Ordem esquerda → direita: ${meta.fonte_ideologia}.`;
    popularSeletores();
    sincronizarControles();
    ligarControles();
    render();
  }

  function estadoUrl() {
    return {
      casa: estado.casa,
      uf: estado.casa === "assembleia" ? estado.uf : "",
      destaque: estado.casa !== "assembleia" ? estado.destaque : "",
      agrupar: estado.agrupar === "partido" ? "" : estado.agrupar,
    };
  }

  return { iniciar, estadoUrl };
})();
