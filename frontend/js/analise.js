// Cálculos do mapa no navegador, sobre os votos inteiros por município
// exportados pelo pipeline (votos/{UF}.json ou votos/BR.json):
//   - unidades: município, ou micro/meso/UF fundidos a partir dos municípios
//     (topojson.merge) -- o pipeline só exporta a malha municipal;
//   - entidades: partidos, federações (soma dos partidos membros) ou
//     candidatos, com votos por município;
//   - agregação por unidade, %, líder (com margem) e LISA.
const Analise = (() => {
  const cacheUnidades = new Map();
  const cacheEntidades = new Map();

  // --- escopo (uma UF, "BR" ou a capital de uma UF) -------------------------
  async function carregarEscopo(uf) {
    const [votos, topo, candidatos] = await Promise.all([
      Dados.carregarJson(`output/votos/${uf}.json`),
      Dados.carregarJson(`output/geo/municipios_${uf}.topojson`),
      uf === "BR" ? Promise.resolve(null) : Dados.carregarJson(`output/candidatos/${uf}.json`),
    ]);
    const idxMuni = new Map(votos.municipios.map((c, i) => [c, i]));
    return { uf, chave: uf, votos, topo, candidatos, idxMuni, n: votos.municipios.length };
  }

  // Capital (Fase 5): a "unidade básica" é o local de votação, no lugar do
  // município; bairros/distritos/RAs juntam os locais que caem neles. O
  // arquivo tem o mesmo formato de votos/{UF}.json, indexado por local.
  async function carregarCapital(uf, infoCapital) {
    const [votos, topoUf, candidatos, topo] = await Promise.all([
      Dados.carregarJson(`output/capitais/${uf}.json`),
      Dados.carregarJson(`output/geo/municipios_${uf}.topojson`),
      Dados.carregarJson(`output/candidatos/${uf}.json`),
      infoCapital.subdivisao ? Dados.carregarJson(`output/geo/subdivisoes_${uf}.topojson`) : Promise.resolve(null),
    ]);
    return { uf, chave: `${uf}:capital`, capital: true, votos, topo, topoUf, candidatos, n: votos.locais.nome.length };
  }

  // --- unidades ---------------------------------------------------------------
  const PROP_UNIDADE = { microrregiao: "code_micro", mesorregiao: "code_meso", uf: "uf" };

  function nomeUnidade(unidade, chave, props, meta) {
    if (unidade === "municipio") return props.name_muni;
    if (unidade === "microrregiao") return meta.microrregioes[chave] || chave;
    if (unidade === "mesorregiao") return meta.mesorregioes[chave] || chave;
    return NOMES_UF[chave] || chave;
  }

  // {features, unidadeDe (índice do município -> índice da unidade), n}
  function unidades(escopo, unidade, meta) {
    const chaveCache = `${escopo.chave}:${unidade}`;
    if (cacheUnidades.has(chaveCache)) return cacheUnidades.get(chaveCache);
    const unidadeDe = new Int32Array(escopo.n).fill(-1);
    let features;

    if (escopo.capital) {
      features = unidade === "local" ? feicoesLocais(escopo, unidadeDe) : feicoesSubdivisoes(escopo, unidadeDe);
      const out = { features, unidadeDe, n: features.length, unidade };
      cacheUnidades.set(chaveCache, out);
      return out;
    }

    const objeto = escopo.topo.objects.municipios;
    if (unidade === "municipio") {
      features = topojson.feature(escopo.topo, objeto).features;
      features.forEach((f, u) => {
        const i = escopo.idxMuni.get(f.properties.code_muni);
        if (i !== undefined) unidadeDe[i] = u;
        f.properties.chave = String(f.properties.code_muni);
        f.properties.nome = f.properties.name_muni;
      });
    } else {
      const prop = PROP_UNIDADE[unidade];
      const grupos = new Map();
      objeto.geometries.forEach((g) => {
        const k = String(g.properties[prop]);
        if (!grupos.has(k)) grupos.set(k, []);
        grupos.get(k).push(g);
      });
      features = [];
      grupos.forEach((geoms, k) => {
        const u = features.length;
        geoms.forEach((g) => {
          const i = escopo.idxMuni.get(g.properties.code_muni);
          if (i !== undefined) unidadeDe[i] = u;
        });
        features.push({
          type: "Feature",
          properties: { chave: k, nome: nomeUnidade(unidade, k, geoms[0].properties, meta) },
          geometry: topojson.merge(escopo.topo, geoms),
        });
      });
    }
    const out = { features, unidadeDe, n: features.length, unidade };
    cacheUnidades.set(chaveCache, out);
    return out;
  }

  // Locais com coordenada viram pontos (sem coordenada: ficam no total da
  // capital, fora do mapa). Raio pela raiz do eleitorado do local (área do
  // círculo proporcional), de 2 a 9 px.
  function feicoesLocais(escopo, unidadeDe) {
    const l = escopo.votos.locais;
    const aptos = escopo.votos.aptos;
    const max = Math.max(1, ...aptos);
    const features = [];
    for (let i = 0; i < escopo.n; i++) {
      if (l.lat[i] === null || l.lon[i] === null) continue;
      features.push({
        i,
        type: "Feature",
        properties: {
          chave: String(i),
          nome: Util.titulo(l.nome[i]),
          // endereço e bairro como declarados no cadastro do TSE
          detalhe: [l.endereco[i], l.bairro[i]].filter(Boolean).map(Util.titulo).join(" · "),
          raio: 2 + 7 * Math.sqrt(aptos[i] / max),
        },
        geometry: { type: "Point", coordinates: [l.lon[i], l.lat[i]] },
      });
    }
    // Maiores primeiro: os círculos pequenos ficam por cima e clicáveis.
    features.sort((a, b) => b.properties.raio - a.properties.raio);
    features.forEach((f, u) => {
      unidadeDe[f.i] = u;
    });
    return features;
  }

  // Subdivisões na ordem do TopoJSON; cada local vai para a subdivisão em
  // que cai (`subdiv`, índice `i` das propriedades); -1 = fora de todas.
  function feicoesSubdivisoes(escopo, unidadeDe) {
    const features = topojson.feature(escopo.topo, escopo.topo.objects.subdivisoes).features;
    const posDe = new Map(features.map((f, u) => [f.properties.i, u]));
    features.forEach((f) => {
      f.properties.chave = String(f.properties.i);
    });
    escopo.votos.locais.subdiv.forEach((s, i) => {
      if (s >= 0 && posDe.has(s)) unidadeDe[i] = posDe.get(s);
    });
    return features;
  }

  // Contorno: as UFs do escopo (uma UF, ou as 27 no Brasil); na capital, o
  // limite do município -- nas subdivisões, a união delas (a malha municipal
  // é mais simplificada e não casaria com a borda dos bairros). Só para
  // desenhar.
  function contornoUfs(escopo, meta, unidade) {
    if (escopo.capital && unidade === "subdivisao") {
      const sub = escopo.topo.objects.subdivisoes;
      return [{ type: "Feature", properties: {}, geometry: topojson.merge(escopo.topo, sub.geometries) }];
    }
    if (escopo.capital) {
      const objeto = escopo.topoUf.objects.municipios;
      const geoms = objeto.geometries.filter((g) => g.properties.code_muni === escopo.votos.code_muni);
      return topojson.feature(escopo.topoUf, { type: "GeometryCollection", geometries: geoms }).features;
    }
    return unidades(escopo, "uf", meta).features;
  }

  // --- entidades ----------------------------------------------------------------
  // Densifica pares esparsos [i, votos, i, votos, ...].
  function densoDePares(pares, n) {
    const v = new Float64Array(n);
    for (let k = 0; k < pares.length; k += 2) v[pares[k]] = pares[k + 1];
    return v;
  }

  // [{chave, rotulo, nome, cor, ideologia, total, votos (por município), sigla?}]
  // ordenadas do mais ao menos votado no escopo.
  function entidades(escopo, cargo, agrupar, meta) {
    const chaveCache = `${escopo.uf}:${cargo}:${agrupar}`;
    if (cacheEntidades.has(chaveCache)) return cacheEntidades.get(chaveCache);
    const c = escopo.votos.cargos[cargo];
    const n = escopo.n;
    let lista = [];

    if (agrupar === "candidato") {
      Object.entries(c.candidatos || {}).forEach(([sq, pares]) => {
        const info = escopo.candidatos[sq];
        const p = meta.partidos[info.sigla];
        lista.push({
          chave: sq, rotulo: `${info.nome} (${p.rotulo})`, nome: info.nome, sigla: info.sigla,
          cor: p.cor, ideologia: p.ideologia, info, votos: densoDePares(pares, n),
        });
      });
    } else {
      const porChave = new Map();
      Object.entries(c.partidos).forEach(([sigla, arr]) => {
        const p = meta.partidos[sigla];
        const fed = agrupar === "federacao" && p.federacao ? meta.federacoes[p.federacao] : null;
        const chave = fed ? `F${p.federacao}` : sigla;
        if (!porChave.has(chave)) {
          porChave.set(chave, {
            chave,
            rotulo: fed ? fed.sigla : p.rotulo,
            nome: fed ? fed.nome : p.rotulo,
            cor: fed ? fed.cor : p.cor,
            ideologia: fed ? fed.ideologia : p.ideologia,
            membros: [],
            votos: new Float64Array(n),
          });
        }
        const e = porChave.get(chave);
        e.membros.push(sigla);
        for (let i = 0; i < n; i++) e.votos[i] += arr[i];
      });
      lista = [...porChave.values()];
    }
    lista.forEach((e) => {
      e.total = e.votos.reduce((a, b) => a + b, 0);
    });
    lista = lista.filter((e) => e.total > 0).sort((a, b) => b.total - a.total);
    cacheEntidades.set(chaveCache, lista);
    return lista;
  }

  // --- agregação e indicadores --------------------------------------------------
  function agregar(votosMun, uns) {
    const out = new Float64Array(uns.n);
    for (let i = 0; i < votosMun.length; i++) {
      const u = uns.unidadeDe[i];
      if (u >= 0) out[u] += votosMun[i];
    }
    return out;
  }

  // Totais do cargo por unidade e no escopo inteiro.
  function totais(escopo, cargo, uns) {
    const c = escopo.votos.cargos[cargo];
    const v = escopo.votos;
    const soma = (a) => a.reduce((x, y) => x + y, 0);
    return {
      validos: agregar(c.validos, uns),
      escopo: {
        aptos: soma(v.aptos), comparecimento: soma(v.comparecimento),
        validos: soma(c.validos), brancos: soma(c.brancos), nulos: soma(c.nulos),
      },
    };
  }

  // Fração (0-1) de cada entidade por unidade, relativa aos válidos.
  function fracoes(e, uns, validos) {
    const ag = agregar(e.votos, uns);
    return ag.map((v, u) => (validos[u] > 0 ? v / validos[u] : 0));
  }

  // Líder por unidade, margem sobre o 2º e intensidade (como no clone:
  // "alta" se a margem >= mediana das margens das unidades que aquele líder
  // venceu, senão "baixa").
  function lideres(ents, uns, validos) {
    const fr = ents.map((e) => fracoes(e, uns, validos));
    const out = [];
    for (let u = 0; u < uns.n; u++) {
      let a = -1;
      let b = -1;
      for (let k = 0; k < ents.length; k++) {
        if (a < 0 || fr[k][u] > fr[a][u]) {
          b = a;
          a = k;
        } else if (b < 0 || fr[k][u] > fr[b][u]) {
          b = k;
        }
      }
      if (a < 0 || validos[u] === 0) {
        out.push(null);
        continue;
      }
      out.push({ k: a, frac: fr[a][u], margem: fr[a][u] - (b >= 0 ? fr[b][u] : 0) });
    }
    const margensPorLider = new Map();
    out.forEach((l) => {
      if (!l) return;
      if (!margensPorLider.has(l.k)) margensPorLider.set(l.k, []);
      margensPorLider.get(l.k).push(l.margem);
    });
    const mediana = new Map();
    margensPorLider.forEach((ms, k) => {
      const s = [...ms].sort((x, y) => x - y);
      const m = s.length;
      mediana.set(k, m % 2 ? s[(m - 1) / 2] : (s[m / 2 - 1] + s[m / 2]) / 2);
    });
    out.forEach((l) => {
      if (l) l.intensidade = l.margem >= mediana.get(l.k) ? "alta" : "baixa";
    });
    return { lideres: out, fracoes: fr };
  }

  // Teto robusto da escala contínua: percentil 98 dos valores > 0 (um
  // reduto isolado com 60% não deixa o resto do mapa todo branco).
  function teto(valores) {
    const pos = Array.from(valores).filter((v) => v > 0).sort((a, b) => a - b);
    if (pos.length === 0) return 1;
    return pos[Math.min(pos.length - 1, Math.floor(0.98 * (pos.length - 1)))] || pos[pos.length - 1];
  }

  function lisa(escopo, fracMun) {
    return LISA.classificar(fracMun, escopo.votos.vizinhos);
  }

  // LISA das subdivisões da capital, sobre o % por subdivisão (`fr`, na
  // ordem das feições). Subdivisão sem local de votação (parque, área sem
  // eleitor) não tem valor: sai do grafo de vizinhança e fica null.
  function lisaSubdivisoes(escopo, uns, fr, validos) {
    const viz = escopo.votos.vizinhos;
    const posDe = uns.features.map((f) => f.properties.i);
    const uDe = new Map(posDe.map((i, u) => [i, u]));
    const comDado = posDe.map((i, u) => validos[u] > 0);
    // índices (i) com dado -> posição compacta
    const compacto = new Map();
    posDe.forEach((i, u) => {
      if (comDado[u]) compacto.set(i, compacto.size);
    });
    const valores = new Array(compacto.size);
    const vizC = new Array(compacto.size);
    compacto.forEach((c, i) => {
      valores[c] = fr[uDe.get(i)];
      vizC[c] = (viz[i] || []).filter((j) => compacto.has(j)).map((j) => compacto.get(j));
    });
    const classes = LISA.classificar(valores, vizC);
    return posDe.map((i) => (compacto.has(i) ? classes[compacto.get(i)] : null));
  }

  return {
    carregarEscopo, carregarCapital, unidades, contornoUfs, entidades, agregar, totais, fracoes, lideres, teto, lisa,
    lisaSubdivisoes,
  };
})();
