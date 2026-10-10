// Mapa Leaflet em tela cheia: troca a camada de unidades conforme a seleção,
// sem recarregar a página, com um contorno de UF por cima (como no clone).
// Renderizador canvas: a visão Brasil tem 5.571 polígonos.
const TILES = {
  // CartoDB Dark Matter passou a exigir API key (ver CLAUDE.md do clone);
  // Esri não exige. Claro também Esri (a política do OSM não admite tráfego
  // alto).
  escuro: {
    url: "https://services.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Dark_Gray_Base/MapServer/tile/{z}/{y}/{x}",
    attribution: "© Esri, HERE, Garmin, © OpenStreetMap contributors, GIS User Community",
  },
  claro: {
    url: "https://services.arcgisonline.com/ArcGIS/rest/services/Canvas/World_Light_Gray_Base/MapServer/tile/{z}/{y}/{x}",
    attribution: "© Esri, HERE, Garmin, © OpenStreetMap contributors, GIS User Community",
  },
};

const Mapa = (() => {
  let mapa = null;
  let camadaTiles = null;
  let camada = null;
  let camadaContorno = null;
  let renderer = null;
  let ultimo = null;
  let temaAtual = "escuro";
  let aoRedesenhar = null;

  // Linha mais fina com menos zoom (os 5.571 municípios do Brasil inteiro
  // não viram uma mancha de contorno) e mais grossa ao aproximar; contorno
  // de UF ~3x mais grosso, com teto (valores validados no clone).
  function pesoLinha(ehContorno) {
    const zoom = mapa.getZoom();
    const base = Math.max(0.15, Math.min(0.7, 0.15 + (zoom - 4) * 0.08));
    return ehContorno ? Math.min(base * 3.15, 1.98) : base;
  }

  // Locais de votação (pontos): borda fina fixa, para círculos vizinhos não
  // virarem uma mancha branca.
  function pesoFeicao(f) {
    return f.geometry.type === "Point" ? 0.5 : pesoLinha(false);
  }

  function corLinha() {
    return "#ffffff"; // como no clone (validado pelo usuário nos dois temas)
  }

  function iniciar() {
    renderer = L.canvas({ padding: 0.5 });
    // Zoom só inteiro (padrão do Leaflet): com zoomSnap fracionário os tiles
    // do mapa-base são escalados e aparecem costuras de 1 px entre blocos de
    // tiles (testado: some sem os tiles; nem sobrepor meio pixel nem
    // mix-blend-mode resolveram).
    mapa = L.map("map", { zoomControl: false, renderer }).setView([-14.5, -52], 4);
    L.control.zoom({ position: "bottomright" }).addTo(mapa);
    mapa.on("zoomend", () => {
      if (camada) camada.setStyle((f) => ({ weight: pesoFeicao(f) }));
      if (camadaContorno) camadaContorno.setStyle({ weight: pesoLinha(true) });
    });
    return mapa;
  }

  function definirTema(tema) {
    temaAtual = tema;
    if (!mapa) return;
    const config = TILES[tema] || TILES.escuro;
    if (camadaTiles) mapa.removeLayer(camadaTiles);
    camadaTiles = L.tileLayer(config.url, { attribution: config.attribution, maxZoom: 18 }).addTo(mapa);
    camadaTiles.bringToBack();
    // Estilos que dependem do tema (linha, "Não significante" do LISA)
    // são recalculados por quem desenhou (painel do mapa).
    if (ultimo && aoRedesenhar) aoRedesenhar();
  }

  // features: GeoJSON das unidades (polígonos, ou pontos com
  // properties.raio para locais de votação); estilo(feature) -> {fillColor,
  // fillOpacity}; popup(feature) -> HTML; contorno: features das UFs (ou o
  // limite da capital).
  function renderizar({ features, estilo, popup, contorno, ajustarVista = true }) {
    ultimo = { features };
    if (camada) mapa.removeLayer(camada);
    camada = L.geoJSON({ type: "FeatureCollection", features }, {
      renderer,
      pointToLayer: (f, latlng) => L.circleMarker(latlng, { renderer, radius: f.properties.raio || 4 }),
      style: (f) => ({ ...estilo(f), color: corLinha(), weight: pesoFeicao(f), opacity: 1 }),
      onEachFeature: (f, layer) => layer.bindPopup(() => popup(f), { maxWidth: 300 }),
    }).addTo(mapa);

    if (camadaContorno) mapa.removeLayer(camadaContorno);
    camadaContorno = contorno
      ? L.geoJSON({ type: "FeatureCollection", features: contorno }, {
          renderer,
          interactive: false,
          style: () => ({ fill: false, color: "#ffffff", weight: pesoLinha(true), opacity: 1 }),
        }).addTo(mapa)
      : null;

    if (ajustarVista) enquadrar();
  }

  // Com o mapa oculto (aba Composição) o Leaflet não sabe o tamanho do
  // contêiner: o enquadramento fica pendente até a aba aparecer.
  let enquadramentoPendente = false;
  function enquadrar() {
    if (!camada) return;
    if (mapa.getContainer().offsetWidth === 0) {
      enquadramentoPendente = true;
      return;
    }
    enquadramentoPendente = false;
    const limites = camada.getBounds();
    if (limites.isValid()) mapa.fitBounds(limites, margensSemPainel());
  }

  // O painel flutua sobre o mapa: à esquerda no desktop, embaixo no celular.
  // A área enquadrada desconta o pedaço que ele cobre.
  function margensSemPainel() {
    const p = document.getElementById("controles").getBoundingClientRect();
    const m = 16;
    if (p.right < window.innerWidth / 2) return { paddingTopLeft: [p.right + m, m], paddingBottomRight: [m, m] };
    return { paddingTopLeft: [m, m], paddingBottomRight: [m, window.innerHeight - p.top + m] };
  }

  function tema() {
    return temaAtual;
  }

  // O Leaflet mede o contêiner ao iniciar; se ele estava oculto (aba
  // Composição), precisa remedir ao voltar a ficar visível.
  function aoMostrar() {
    if (!mapa) return;
    mapa.invalidateSize();
    if (enquadramentoPendente) enquadrar();
  }

  function definirAoRedesenhar(fn) {
    aoRedesenhar = fn;
  }

  // Quantas unidades estão desenhadas (usado pelo QA, tests/qa_frontend.R).
  function nFeicoes() {
    return ultimo ? ultimo.features.length : 0;
  }

  // Posição na tela (px do contêiner) do centro da k-ésima unidade desenhada
  // (usado pelo QA para clicar num local de votação).
  function pontoTela(k) {
    const layer = camada && camada.getLayers()[k];
    if (!layer) return null;
    const ll = layer.getLatLng ? layer.getLatLng() : layer.getBounds().getCenter();
    const p = mapa.latLngToContainerPoint(ll);
    return [p.x, p.y];
  }

  return { iniciar, definirTema, renderizar, aoMostrar, tema, definirAoRedesenhar, nFeicoes, pontoTela };
})();
