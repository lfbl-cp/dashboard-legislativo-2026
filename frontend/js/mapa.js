// Mapa Leaflet em tela cheia. Por enquanto só o mapa-base do Brasil; as
// camadas de resultado por município entram na Fase 4.
const TILES = {
  // CartoDB Dark Matter passou a exigir API key (ver CLAUDE.md do
  // painel-eleicoes-2026); Esri World Dark Gray Base não exige.
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

  function iniciar() {
    mapa = L.map("map", { zoomControl: false }).setView([-14.5, -52], 4);
    L.control.zoom({ position: "bottomright" }).addTo(mapa);
    return mapa;
  }

  function definirTema(tema) {
    if (!mapa) return;
    const config = TILES[tema] || TILES.escuro;
    if (camadaTiles) mapa.removeLayer(camadaTiles);
    camadaTiles = L.tileLayer(config.url, { attribution: config.attribution, maxZoom: 18 }).addTo(mapa);
  }

  // O Leaflet mede o contêiner ao iniciar; se ele estava oculto (aba
  // Composição), precisa remedir ao voltar a ficar visível.
  function aoMostrar() {
    if (mapa) mapa.invalidateSize();
  }

  return { iniciar, definirTema, aoMostrar };
})();
