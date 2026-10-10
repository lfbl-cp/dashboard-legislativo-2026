// Camada de dados: busca e cacheia os JSON de output/. "BASE" assume que a
// página é servida de frontend/, com output/ como pasta irmã (na raiz do
// projeto) -- igual ao painel-eleicoes-2026.
const BASE = "..";

const Dados = (() => {
  const cache = new Map();

  async function carregarJson(caminho) {
    if (cache.has(caminho)) return cache.get(caminho);
    const promessa = fetch(`${BASE}/${caminho}`).then((resp) => {
      if (!resp.ok) throw new Error(`Falha ao carregar ${caminho}: ${resp.status}`);
      return resp.json();
    });
    cache.set(caminho, promessa);
    try {
      return await promessa;
    } catch (e) {
      cache.delete(caminho);
      throw e;
    }
  }

  function urlFoto(sq) {
    return `${BASE}/output/fotos/${sq}.jpg`;
  }

  return { carregarJson, urlFoto };
})();
