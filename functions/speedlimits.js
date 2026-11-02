/**
 * Limites de velocidade das vias, por estado, para o velocímetro do app.
 *
 * Fonte: projeto aberto Pardal (ODbL): limites oficiais (ANTT, DERs) e do
 * OpenStreetMap; quando a via não tem placa mapeada, o Pardal estima pelo
 * tipo de via ("estimated" = 1). https://github.com/Murkiriel/pardal
 *
 * Complemento: public/limites-osm/<UF>.json.gz (scripts/limites-osm.py), com
 * o `maxspeed` do OpenStreetMap onde o Pardal não tem ou só estima.
 *
 * Saída: public/limites/<UF>.json.gz com pontos ordenados e compactados:
 *   d = [dLat, dLng, limite, estimado (0/1), sentido (-1 = ambos), ...]
 * onde dLat/dLng são diferenças (em 1e-5 grau) para o ponto anterior.
 */

const zlib = require("zlib");

const BASE = "https://raw.githubusercontent.com/Murkiriel/pardal/main";

async function fetchText(url, tries = 3) {
  let last;
  for (let i = 0; i < tries; i++) {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(120000) });
      if (!res.ok) throw new Error(`HTTP ${res.status} em ${url}`);
      return await res.text();
    } catch (e) {
      last = e;
      await new Promise((r) => setTimeout(r, 2000 * (i + 1)));
    }
  }
  throw last;
}

/** Lista de pontos [lat, lng, limite, estimado, sentido] -> formato compacto. */
function compact(list) {
  const pts = [...list].sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const d = [];
  let pLat = 0, pLng = 0;
  for (const [lat, lng, lim, est, dir] of pts) {
    d.push(lat - pLat, lng - pLng, lim, est, dir);
    pLat = lat;
    pLng = lng;
  }
  return { count: pts.length, d };
}

/** Formato compacto -> lista de pontos. */
function expand(d) {
  const pts = [];
  let lat = 0, lng = 0;
  for (let i = 0; i + 4 < d.length; i += 5) {
    lat += d[i];
    lng += d[i + 1];
    pts.push([lat, lng, d[i + 2], d[i + 3], d[i + 4]]);
  }
  return pts;
}

const CELL = 150; // ~165 m (1e-5 grau)
const metersE5 = (a, b) => Math.hypot(a[0] - b[0], (a[1] - b[1]) * 0.93) * 1.113;
const sameWay = (a, b) => {
  if (a[4] < 0 || b[4] < 0) return true;
  const x = Math.abs(a[4] - b[4]) % 360;
  return Math.min(x, 360 - x) <= 30;
};

/**
 * Junta os pontos do OpenStreetMap aos do Pardal: entram onde não há limite,
 * e no lugar de estimado da mesma via. Placa real do Pardal não muda.
 */
function mergeLimits(base, extra) {
  const grid = new Map();
  const key = (p, i, j) =>
    (Math.floor(p[0] / CELL) + i) * 1e6 + Math.floor(p[1] / CELL) + j;
  for (const p of base) {
    const k = key(p, 0, 0);
    if (!grid.has(k)) grid.set(k, []);
    grid.get(k).push(p);
  }
  const drop = new Set();
  const add = [];
  for (const q of extra) {
    let keep = true;
    const near = [];
    for (let i = -1; i <= 1; i++) {
      for (let j = -1; j <= 1; j++) {
        for (const p of grid.get(key(q, i, j)) || []) {
          if (metersE5(p, q) > 150 || !sameWay(p, q)) continue;
          if (p[3] === 1) near.push(p);
          else keep = false;
        }
      }
    }
    if (!keep) continue;
    add.push(q);
    for (const p of near) drop.add(p);
  }
  return [...base.filter((p) => !drop.has(p)), ...add];
}

/** Converte o CSV de limites de um estado no formato compacto. */
function compactLimits(csv) {
  const lines = csv.split("\n");
  const head = lines.shift().trim().split(",");
  const col = (n) => head.indexOf(n);
  const [iLat, iLng, iLim, iEst, iDir] =
    ["lat", "lng", "limit_kmh", "estimated", "direction_deg"].map(col);
  const pts = [];
  for (const line of lines) {
    if (!line) continue;
    const c = line.split(",");
    const lat = Math.round(parseFloat(c[iLat]) * 1e5);
    const lng = Math.round(parseFloat(c[iLng]) * 1e5);
    const lim = parseInt(c[iLim], 10);
    if (!isFinite(lat) || !isFinite(lng) || !(lim > 0 && lim <= 140)) continue;
    const dir = parseFloat(c[iDir]);
    pts.push([lat, lng, lim, c[iEst] === "1" ? 1 : 0,
      isFinite(dir) ? Math.round(dir) % 360 : -1]);
  }
  return compact(pts);
}

/**
 * Gera os arquivos dos estados que mudaram desde a última vez.
 * [previous] = meta/limits atual ({ ufs: { SC: { sha, ... } } }).
 * [save] = (uf, gzBuffer) => Promise.
 * [loadExtra] = (uf) => Promise<{ id, gz } | null>, complemento do estado.
 */
async function buildSpeedLimits({ previous = {}, save, loadExtra, log = console.log }) {
  const catalog = JSON.parse(await fetchText(`${BASE}/catalogo.json`));
  const ufs = {};
  let changed = 0;
  for (const [uf, info] of Object.entries(catalog.ufs || {})) {
    // "BR" é o arquivo do país inteiro: o app baixa só o estado onde está.
    if (!/^[A-Z]{2}$/.test(uf) || uf === "BR" || !info.limits) continue;
    const old = previous.ufs && previous.ufs[uf];
    const extra = loadExtra ? await loadExtra(uf) : null;
    const sha = extra ? `${info.limits.sha256}+${extra.id}` : info.limits.sha256;
    if (old && old.sha === sha) {
      ufs[uf] = old;
      continue;
    }
    let { count, d } = compactLimits(await fetchText(`${BASE}/${info.limits.file}`));
    if (extra) {
      const more = JSON.parse(zlib.gunzipSync(extra.gz).toString()).d;
      ({ count, d } = compact(mergeLimits(expand(d), expand(more))));
    }
    const gz = zlib.gzipSync(JSON.stringify({ v: 1, uf, d }), { level: 9 });
    await save(uf, gz);
    ufs[uf] = {
      sha,
      bbox: info.bbox, // [latMin, lngMin, latMax, lngMax]
      count,
      bytes: gz.length,
      version: Date.now(),
    };
    changed++;
    log(`Limites ${uf}: ${count} pontos, ${(gz.length / 1024).toFixed(0)} KB`);
  }
  return { ufs, changed };
}

module.exports = { buildSpeedLimits, compactLimits, mergeLimits, expand, compact };
