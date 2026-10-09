/**
 * Lombadas, postos policiais rodoviários e praças de pedágio, por estado, a partir do
 * OpenStreetMap (ODbL) via Overpass API.
 *
 * Saída: public/pois/<UF>.json.gz = { v, uf, d } com pontos ordenados e
 * compactados: d = [dLat, dLng, tipo, ...] (diferenças em 1e-5 grau),
 * tipo 1 = lombada / faixa elevada, 2 = posto policial rodoviário,
 * 3 = praça de pedágio (moto paga ou não informado), 4 = pedágio com moto isenta.
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
  for (const e of elements) {
    const t = e.tags || {};
    const lat = e.lat ?? e.center?.lat, lng = e.lon ?? e.center?.lon;
    if (!isFinite(lat) || !isFinite(lng)) continue;
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
  const d = [];
  let pLat = 0, pLng = 0, bumps = 0, police = 0, tolls = 0;
  const box = [Infinity, Infinity, -Infinity, -Infinity];
  for (const [lat, lng, type] of pts) {
    d.push(lat - pLat, lng - pLng, type);
    pLat = lat;
    pLng = lng;
    if (type === 1) bumps++; else if (type === 2) police++; else tolls++;
    box[0] = Math.min(box[0], lat / 1e5); box[1] = Math.min(box[1], lng / 1e5);
    box[2] = Math.max(box[2], lat / 1e5); box[3] = Math.max(box[3], lng / 1e5);
  }
  return { d, bumps, police, tolls, bbox: pts.length ? box.map((v) => +v.toFixed(2)) : null };
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
    // Refaz também os gerados antes dos pedágios existirem (sem "tolls").
    .filter((uf) => !ufs[uf] || ufs[uf].tolls === undefined ||
      Date.now() - (ufs[uf].version || 0) > week)
    .sort((a, b) => (ufs[a]?.version || 0) - (ufs[b]?.version || 0));
  let changed = 0;
  for (const uf of due) {
    if (Date.now() - start > budgetMs) break;
    try {
      const { d, bumps, police, tolls, bbox } = compact(await fetchUf(uf));
      const gz = zlib.gzipSync(JSON.stringify({ v: 1, uf, d }), { level: 9 });
      await save(uf, gz);
      ufs[uf] = { bbox, bumps, police, tolls, bytes: gz.length, version: Date.now() };
      changed++;
      log(`POIs ${uf}: ${bumps} lombadas, ${police} postos, ${tolls} pedágios, ${(gz.length / 1024).toFixed(0)} KB`);
    } catch (e) {
      log(`POIs ${uf}: falhou (${e.message})`);
    }
    await new Promise((r) => setTimeout(r, 5000)); // respeita o Overpass
  }
  return { ufs, changed };
}

module.exports = { buildPois, compact, ROAD_POLICE };
