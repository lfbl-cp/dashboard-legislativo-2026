// Orquestração: abas (Mapa | Composição), tema e estado na URL. Uma tela só:
// a aba decide se o mapa ou o hemiciclo ocupa a tela inteira.
(async function main() {
  const status = document.getElementById("status");
  const inicial = Util.lerEstado();
  let abaAtual = inicial.aba === "composicao" ? "composicao" : "mapa";
  let prontos = false;

  function gravarUrl() {
    if (!prontos) return;
    const doPainel = abaAtual === "composicao" ? Composicao.estadoUrl() : PainelMapa.estadoUrl();
    Util.gravarEstado({ aba: abaAtual, ...doPainel });
  }

  function mostrarAba(aba) {
    abaAtual = aba;
    document.body.dataset.aba = aba;
    document.querySelectorAll(".abas button").forEach((b) => {
      b.setAttribute("aria-selected", String(b.dataset.aba === aba));
    });
    document.querySelectorAll("[data-aba-painel]").forEach((s) => {
      s.hidden = s.dataset.abaPainel !== aba;
    });
    document.getElementById("map").hidden = aba !== "mapa";
    document.getElementById("hemiciclo").hidden = aba !== "composicao";
    if (aba === "mapa") Mapa.aoMostrar();
    gravarUrl();
  }

  document.querySelectorAll(".abas button").forEach((b) => {
    b.addEventListener("click", () => mostrarAba(b.dataset.aba));
  });

  Mapa.iniciar();
  Tema.iniciar();
  Card.instalarFallbackFotos();

  // O painel flutua sobre o mapa: sem isso, clicar/rolar nele também
  // arrasta/dá zoom no mapa por baixo.
  const painel = document.getElementById("controles");
  L.DomEvent.disableClickPropagation(painel);
  L.DomEvent.disableScrollPropagation(painel);

  mostrarAba(abaAtual);
  status.textContent = "Carregando...";
  try {
    const [meta, capitais] = await Promise.all([
      Dados.carregarJson("output/meta.json"),
      // Piloto de bairros/locais (Fase 5); sem ele, o mapa só perde essas unidades.
      Dados.carregarJson("output/capitais/index.json").catch(() => ({})),
    ]);
    // Cada painel lê da URL só o que é dele; o da aba fora de foco começa
    // no padrão.
    const doMapa = abaAtual === "mapa" ? inicial : {};
    const daComposicao = abaAtual === "composicao" ? inicial : {};
    await Promise.all([
      PainelMapa.iniciar(doMapa, meta, capitais, gravarUrl),
      Composicao.iniciar(daComposicao, meta, gravarUrl, async (alvo) => {
        mostrarAba("mapa");
        await PainelMapa.mostrarCandidato(alvo);
      }),
    ]);
    prontos = true;
    gravarUrl();
    status.textContent = "";
  } catch (e) {
    status.textContent = `Erro ao carregar dados: ${e.message}`;
    throw e;
  }
})();
