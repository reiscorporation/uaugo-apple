/**
 * Lombadas, postos policiais rodoviários e praças de pedágio, por estado, a partir do
 * OpenStreetMap (ODbL) via Overpass API.
 *
 * Saída, por estado (pontos ordenados e compactados em diferenças de 1e-5 grau):
 *   public/pois/<UF>.json.gz      = { v, uf, d }  d = [dLat, dLng, tipo, ...]
 *     tipo 2 = posto policial rodoviário, 3 = praça de pedágio (moto paga ou
 *     não informado), 4 = pedágio com moto isenta. Sempre baixado pelo app.
 *   public/lombadas/<UF>.json.gz  = { v, uf, d }  tipo 1 = lombada / faixa elevada
 *   public/semaforos/<UF>.json.gz = { v, uf, s }  s = [dLat, dLng, ...]
 *     Lombadas e semáforos são opcionais: o app só baixa se o piloto ligar
 *     o aviso (Configurações → Outros avisos).
 */

const zlib = require("zlib");

const UFS = ["AC", "AL", "AM", "AP", "BA", "CE", "DF", "ES", "GO", "MA", "MG",
  "MS", "MT", "PA", "PB", "PE", "PI", "PR", "RJ", "RN", "RO", "RR", "RS", "SC",
  "SE", "SP", "TO"];

const OVERPASS = [
  "https://overpass-api.de/api/interpreter",
  "https://overpass.kumi.systems/api/interpreter",
];

/** Posto da PRF / polícia rodoviária estadual (não delegacia da cidade). */
const ROAD_POLICE = /rodovi|PRF|PMRv|BPRv|CPRv|posto policial|posto da pol/i;

function query(uf) {
  return `[out:json][timeout:600];
area["ISO3166-2"="BR-${uf}"][admin_level=4]->.a;
(
  node["traffic_calming"~"^(bump|hump|table|cushion)$"](area.a);
  node["amenity"="police"](area.a);
  way["amenity"="police"](area.a);
  node["barrier"="toll_booth"](area.a);
  node["highway"="traffic_signals"](area.a);
);
out center tags;`;
}

async function fetchUf(uf) {
  let last;
  // O Overpass às vezes responde 429/504 (ocupado): até 3 rodadas pelos dois
  // servidores, esperando 20 s, 40 s entre elas.
  for (let round = 0; round < 3; round++) {
    if (round > 0) await new Promise((r) => setTimeout(r, 20000 * round));
  for (const url of OVERPASS) {
    try {
      const res = await fetch(url, {
        method: "POST",
        headers: {
          "content-type": "application/x-www-form-urlencoded",
          "user-agent": "UauGo/1.0 (app de viagens; contato HelpAITech)",
        },
        body: "data=" + encodeURIComponent(query(uf)),
        signal: AbortSignal.timeout(700000),
      });
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      return (await res.json()).elements || [];
    } catch (e) {
      last = e;
    }
  }
  }
  throw last;
}

function compact(elements) {
  const pts = [];
  const sig = [];
  for (const e of elements) {
    const t = e.tags || {};
    const lat = e.lat ?? e.center?.lat, lng = e.lon ?? e.center?.lon;
    if (!isFinite(lat) || !isFinite(lng)) continue;
    // Semáforos: lista à parte ("s"), para a voz dizer "no semáforo, vire".
    // (Separados para versões antigas do app não lerem como lombada.)
    if (t.highway === "traffic_signals") {
      sig.push([Math.round(lat * 1e5), Math.round(lng * 1e5)]);
      continue;
    }
    let type = 0;
    if (t.traffic_calming) type = 1;
    else if (t.barrier === "toll_booth") {
      // Isenção de moto, quando o OSM informa (toll:motorcycle=no etc.).
      const free = [t["toll:motorcycle"], t["motorcycle:toll"], t["fee:motorcycle"]]
        .some((v) => v === "no");
      type = free ? 4 : 3;
    }
    else if (t.amenity === "police" &&
      ROAD_POLICE.test(`${t.name || ""} ${t.operator || ""} ${t.official_name || ""}`)) type = 2;
    if (!type) continue;
    pts.push([Math.round(lat * 1e5), Math.round(lng * 1e5), type]);
  }
  pts.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  sig.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const box = [Infinity, Infinity, -Infinity, -Infinity];
  for (const [lat, lng] of [...pts, ...sig]) {
    box[0] = Math.min(box[0], lat / 1e5); box[1] = Math.min(box[1], lng / 1e5);
    box[2] = Math.max(box[2], lat / 1e5); box[3] = Math.max(box[3], lng / 1e5);
  }
  // Diferenças acumuladas (com o tipo, se [withType]).
  const delta = (list, withType) => {
    const out = [];
    let pLat = 0, pLng = 0;
    for (const [lat, lng, type] of list) {
      out.push(lat - pLat, lng - pLng);
      if (withType) out.push(type);
      pLat = lat;
      pLng = lng;
    }
    return out;
  };
  const bumpPts = pts.filter((p) => p[2] === 1);
  const rest = pts.filter((p) => p[2] !== 1);
  return {
    d: delta(rest, true),
    b: delta(bumpPts, true),
    s: delta(sig, false),
    bumps: bumpPts.length,
    police: rest.filter((p) => p[2] === 2).length,
    tolls: rest.filter((p) => p[2] !== 2).length,
    signals: sig.length,
    bbox: pts.length || sig.length ? box.map((v) => +v.toFixed(2)) : null,
  };
}

/**
 * Atualiza os estados mais antigos (mais de 6 dias) até acabar o tempo:
 * roda todo dia e, ao longo da semana, passa por todos os estados.
 */
async function buildPois({ previous = {}, save, budgetMs = 420000, log = console.log }) {
  const ufs = { ...(previous.ufs || {}) };
  const start = Date.now();
  const week = 6 * 24 * 3600 * 1000;
  const due = UFS
    // Refaz também os gerados antes dos pedágios/semáforos existirem.
    .filter((uf) => !ufs[uf] || ufs[uf].tolls === undefined || ufs[uf].signals === undefined ||
      Date.now() - (ufs[uf].version || 0) > week)
    .sort((a, b) => (ufs[a]?.version || 0) - (ufs[b]?.version || 0));
  let changed = 0;
  for (const uf of due) {
    if (Date.now() - start > budgetMs) break;
    try {
      const { d, b, s, bumps, police, tolls, signals, bbox } = compact(await fetchUf(uf));
      const gz = (o) => zlib.gzipSync(JSON.stringify({ v: 2, uf, ...o }), { level: 9 });
      const main = gz({ d }), bumpGz = gz({ d: b }), sigGz = gz({ s });
      await save("pois", uf, main);
      await save("lombadas", uf, bumpGz);
      await save("semaforos", uf, sigGz);
      ufs[uf] = {
        bbox, bumps, police, tolls, signals, version: Date.now(),
        bytes: main.length, bumpBytes: bumpGz.length, signalBytes: sigGz.length,
      };
      changed++;
      log(`POIs ${uf}: ${police} postos, ${tolls} pedágios (${(main.length / 1024).toFixed(0)} KB); ` +
        `${bumps} lombadas (${(bumpGz.length / 1024).toFixed(0)} KB); ` +
        `${signals} semáforos (${(sigGz.length / 1024).toFixed(0)} KB)`);
    } catch (e) {
      log(`POIs ${uf}: falhou (${e.message})`);
    }
    await new Promise((r) => setTimeout(r, 5000)); // respeita o Overpass
  }
  return { ufs, changed };
}

module.exports = { buildPois, compact, ROAD_POLICE };
