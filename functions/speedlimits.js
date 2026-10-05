/**
 * Limites de velocidade das vias, por estado, para o velocímetro do app.
 *
 * Fonte: projeto aberto Pardal (ODbL): limites oficiais (ANTT, DERs) e do
 * OpenStreetMap; quando a via não tem placa mapeada, o Pardal estima pelo
 * tipo de via ("estimated" = 1). https://github.com/Murkiriel/pardal
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
  pts.sort((a, b) => a[0] - b[0] || a[1] - b[1]);
  const d = [];
  let pLat = 0, pLng = 0;
  for (const [lat, lng, lim, est, dir] of pts) {
    d.push(lat - pLat, lng - pLng, lim, est, dir);
    pLat = lat;
    pLng = lng;
  }
  return { count: pts.length, d };
}

/**
 * Gera os arquivos dos estados que mudaram desde a última vez.
 * [previous] = meta/limits atual ({ ufs: { SC: { sha, ... } } }).
 * [save] = (uf, gzBuffer) => Promise.
 */
async function buildSpeedLimits({ previous = {}, save, log = console.log }) {
  const catalog = JSON.parse(await fetchText(`${BASE}/catalogo.json`));
  const ufs = {};
  let changed = 0;
  for (const [uf, info] of Object.entries(catalog.ufs || {})) {
    // "BR" é o arquivo do país inteiro: o app baixa só o estado onde está.
    if (!/^[A-Z]{2}$/.test(uf) || uf === "BR" || !info.limits) continue;
    const old = previous.ufs && previous.ufs[uf];
    if (old && old.sha === info.limits.sha256) {
      ufs[uf] = old;
      continue;
    }
    const { count, d } = compactLimits(await fetchText(`${BASE}/${info.limits.file}`));
    const gz = zlib.gzipSync(JSON.stringify({ v: 1, uf, d }), { level: 9 });
    await save(uf, gz);
    ufs[uf] = {
      sha: info.limits.sha256,
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

module.exports = { buildSpeedLimits, compactLimits };
