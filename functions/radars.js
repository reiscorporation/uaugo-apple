/**
 * Monta o arquivo de radares usado pelo app (baixado uma vez e consultado
 * offline no celular):
 *
 * 1. Radares fixos, de trecho (velocidade média) e de avanço de sinal do
 *    Brasil inteiro, do projeto aberto Pardal (ODbL), que reúne DNIT, ANTT,
 *    DERs, prefeituras e OpenStreetMap: https://github.com/Murkiriel/pardal
 * 2. Trechos onde a PRF pode fiscalizar com radar portátil (lista oficial,
 *    Resolução CONTRAN 798/20). A PRF informa só UF, BR e km; o traçado
 *    vem da malha oficial do DNIT (SNV) pelo serviço WFS do INDE.
 */

const PARDAL_CSV =
  "https://raw.githubusercontent.com/Murkiriel/pardal/main/brasil/radares.csv";
const PRF_PAGE =
  "https://www.gov.br/prf/pt-br/assuntos/fiscalizacao-de-velocidade/trechos-criticos";
const SNV_WFS = "https://geoservicos.inde.gov.br/geoserver/DNIT/ows";
const SNV_LAYER = "DNIT:snv_202507a";

const KIND = { FIXED: 0, SECTION: 1, RED_LIGHT: 2 };

async function fetchText(url, tries = 3) {
  let last;
  for (let i = 0; i < tries; i++) {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(90000) });
      if (!res.ok) throw new Error(`HTTP ${res.status} em ${url}`);
      return await res.text();
    } catch (e) {
      last = e;
      await new Promise((r) => setTimeout(r, 2000 * (i + 1)));
    }
  }
  throw last;
}

/** CSV simples com aspas (as planilhas usam "90,0"). */
function parseCsv(text) {
  const rows = [];
  let row = [], cell = "", q = false;
  for (let i = 0; i < text.length; i++) {
    const c = text[i];
    if (q) {
      if (c === '"' && text[i + 1] === '"') { cell += '"'; i++; }
      else if (c === '"') q = false;
      else cell += c;
    } else if (c === '"') q = true;
    else if (c === ",") { row.push(cell); cell = ""; }
    else if (c === "\n") { row.push(cell); rows.push(row); row = []; cell = ""; }
    else if (c !== "\r") cell += c;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  return rows;
}

const round5 = (x) => Math.round(x * 1e5) / 1e5;

// ------------------------------------------------------------ 1. Pardal

async function loadFixedRadars() {
  const rows = parseCsv(await fetchText(PARDAL_CSV));
  const head = rows.shift().map((h) => h.trim());
  const col = (n) => head.indexOf(n);
  const [iLat, iLng, iKind, iLim, iAct, iELat, iELng, iDir, iSrc] = [
    "lat", "lng", "kind", "limit_kmh", "active", "end_lat", "end_lng", "direction_deg",
    "source",
  ].map(col);
  const out = [];
  const official = [];
  for (const r of rows) {
    if (r.length < head.length || r[iAct] === "0") continue;
    const k = KIND[r[iKind]];
    const lat = parseFloat(r[iLat]), lng = parseFloat(r[iLng]);
    if (k === undefined || !isFinite(lat) || !isFinite(lng)) continue;
    const lim = parseInt(r[iLim], 10);
    const dir = parseFloat(r[iDir]);
    const eLat = parseFloat(r[iELat]), eLng = parseFloat(r[iELng]);
    // [lat, lng, tipo, limite (0 = ?), sentido (-1 = ambos), fimLat, fimLng]
    const item = [round5(lat), round5(lng), k, isFinite(lim) ? lim : 0,
      isFinite(dir) ? Math.round(dir) : -1];
    if (k === KIND.SECTION && isFinite(eLat) && isFinite(eLng)) {
      item.push(round5(eLat), round5(eLng));
    }
    out.push(item);
    // Fonte oficial (ANTT, DNIT, DER...) tem posição mais confiável que o OSM.
    official.push(iSrc >= 0 && /ANTT|DNIT|DER|PRF|DETRAN|PREF/i.test(r[iSrc] || ""));
  }
  return mergeDuplicates(out, official);
}

/**
 * A base junta várias fontes: a mesma câmera aparece 2–3 vezes a poucos
 * metros. Junta as do mesmo tipo a até 40 m (e mesmo sentido, quando
 * informado) num radar só, com a posição da fonte oficial quando houver e o
 * limite/sentido de quem informar.
 */
function mergeDuplicates(items, official) {
  const order = items.map((_, i) => i).sort((a, b) => items[a][0] - items[b][0]);
  const used = new Uint8Array(items.length);
  const out = [];
  // distM recebe [lng, lat]; os itens são [lat, lng, ...].
  const near = (a, b) => distM([a[1], a[0]], [b[1], b[0]]) <= 40;
  const sameWay = (a, b) => a[4] < 0 || b[4] < 0 ||
    Math.abs(((a[4] - b[4] + 540) % 360) - 180) <= 45;
  for (let x = 0; x < order.length; x++) {
    const i = order[x];
    if (used[i]) continue;
    used[i] = 1;
    const group = [i];
    for (let y = x + 1; y < order.length; y++) {
      const j = order[y];
      if (items[j][0] - items[i][0] > 0.0004) break; // ~45 m ao norte
      if (used[j] || items[j][2] !== items[i][2]) continue;
      if (near(items[i], items[j]) && sameWay(items[i], items[j])) {
        used[j] = 1;
        group.push(j);
      }
    }
    const best = group.find((g) => official[g]) ?? group[0];
    const m = items[best].slice();
    for (const g of group) {
      if (!m[3] && items[g][3]) m[3] = items[g][3];
      if (m[4] < 0 && items[g][4] >= 0) m[4] = items[g][4];
    }
    out.push(m);
  }
  return out;
}

// ------------------------------------------------------------ 2. PRF

const parseBrDate = (s) => {
  const m = /(\d{2})\/(\d{2})\/(\d{4})/.exec(s);
  return m ? new Date(Date.UTC(+m[3], +m[2] - 1, +m[1])) : null;
};

/** Escolhe a planilha vigente hoje na página da PRF. */
async function findCurrentPrfSheet(today = new Date()) {
  const html = await fetchText(PRF_PAGE);
  const re = /<a[^>]+href="(https:\/\/docs\.google\.com\/spreadsheets\/[^"]+)"[^>]*>([\s\S]*?)<\/a>/g;
  const lists = [];
  let m;
  while ((m = re.exec(html))) {
    const label = m[2].replace(/<[^>]+>/g, "").replace(/\s+/g, " ").trim();
    const dates = label.match(/\d{2}\/\d{2}\/\d{4}/g) || [];
    const from = parseBrDate(dates[0] || "");
    if (!from) continue;
    const to = dates[1] ? parseBrDate(dates[1]) : null;
    lists.push({ url: m[1].replace(/&amp;/g, "&"), label, from, to });
  }
  const day = new Date(Date.UTC(today.getUTCFullYear(), today.getUTCMonth(), today.getUTCDate()));
  const valid = lists
    .filter((l) => l.from <= day && (!l.to || day <= l.to))
    .sort((a, b) => b.from - a.from);
  const pick = valid[0] || lists.sort((a, b) => b.from - a.from)[0];
  if (!pick) throw new Error("Nenhuma lista da PRF encontrada na página");
  return pick;
}

function sheetCsvUrl(pubUrl) {
  // .../pubhtml?gid=X&single=true  ->  .../pub?gid=X&single=true&output=csv
  const u = new URL(pubUrl);
  u.pathname = u.pathname.replace(/\/pubhtml$/, "/pub");
  u.searchParams.set("output", "csv");
  return u.toString();
}

const brNum = (s) => parseFloat(String(s).trim().replace(/\./g, "").replace(",", "."));

async function loadPrfStretches(sheet) {
  const rows = parseCsv(await fetchText(sheetCsvUrl(sheet.url)));
  const hi = rows.findIndex((r) => r.some((c) => /UF/i.test(c)) && r.some((c) => /KM INICIAL/i.test(c)));
  if (hi < 0) throw new Error("Cabeçalho da planilha da PRF não encontrado");
  const out = [];
  for (const r of rows.slice(hi + 1)) {
    const uf = (r[0] || "").trim().toUpperCase();
    const br = (r[1] || "").replace(/\D/g, "").padStart(3, "0");
    const a = brNum(r[2]), b = brNum(r[3]);
    if (!/^[A-Z]{2}$/.test(uf) || br === "000" || !isFinite(a) || !isFinite(b)) continue;
    out.push({ uf, br, a: Math.min(a, b), b: Math.max(a, b) });
  }
  return out;
}

// ------------------------------------------------------------ geometria

function distM(a, b) {
  const R = 6371000, toR = Math.PI / 180;
  const dLat = (b[1] - a[1]) * toR, dLng = (b[0] - a[0]) * toR;
  const x = Math.sin(dLat / 2) ** 2 +
    Math.cos(a[1] * toR) * Math.cos(b[1] * toR) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(x));
}

/** Junta as partes de uma MultiLineString numa linha só, na ordem. */
function mergeParts(parts) {
  const rest = parts.filter((p) => p.length >= 2).map((p) => p.slice());
  if (!rest.length) return [];
  let line = rest.shift();
  while (rest.length) {
    let best = 0, bestD = Infinity, rev = false, atStart = false;
    rest.forEach((p, i) => {
      const cands = [
        [distM(line[line.length - 1], p[0]), false, false],
        [distM(line[line.length - 1], p[p.length - 1]), true, false],
        [distM(line[0], p[p.length - 1]), false, true],
        [distM(line[0], p[0]), true, true],
      ];
      for (const [d, r, s] of cands) if (d < bestD) { bestD = d; best = i; rev = r; atStart = s; }
    });
    let p = rest.splice(best, 1)[0];
    if (rev) p = p.reverse();
    line = atStart ? p.concat(line) : line.concat(p);
  }
  return line;
}

/** Recorta a parte da linha entre as frações f0 e f1 do comprimento. */
function sliceLine(line, f0, f1) {
  const cum = [0];
  for (let i = 1; i < line.length; i++) cum.push(cum[i - 1] + distM(line[i - 1], line[i]));
  const total = cum[cum.length - 1];
  if (total === 0) return [line[0]];
  const at = (f) => {
    const d = f * total;
    let i = cum.findIndex((c) => c >= d);
    if (i <= 0) return [0, line[0]];
    const t = (d - cum[i - 1]) / (cum[i] - cum[i - 1] || 1);
    return [i, [line[i - 1][0] + t * (line[i][0] - line[i - 1][0]),
      line[i - 1][1] + t * (line[i][1] - line[i - 1][1])]];
  };
  const [i0, p0] = at(f0), [i1, p1] = at(f1);
  return [p0, ...line.slice(i0, i1), p1];
}

/** Mantém um ponto a cada ~150 m (suficiente para o aviso de proximidade). */
function thin(line, step = 150) {
  if (line.length <= 2) return line;
  const out = [line[0]];
  for (let i = 1; i < line.length - 1; i++) {
    if (distM(out[out.length - 1], line[i]) >= step) out.push(line[i]);
  }
  out.push(line[line.length - 1]);
  return out;
}

/** Google encoded polyline (lat, lng). */
function encodePolyline(points) {
  let out = "", pLat = 0, pLng = 0;
  const enc = (v) => {
    let x = v < 0 ? ~(v << 1) : v << 1;
    while (x >= 0x20) { out += String.fromCharCode((0x20 | (x & 0x1f)) + 63); x >>= 5; }
    out += String.fromCharCode(x + 63);
  };
  for (const [lng, lat] of points) {
    const la = Math.round(lat * 1e5), lo = Math.round(lng * 1e5);
    enc(la - pLat); enc(lo - pLng);
    pLat = la; pLng = lo;
  }
  return out;
}

/** Eixo principal de uma BR numa UF: segmentos com km e traçado. */
async function loadSnvRoad(uf, br) {
  const params = new URLSearchParams({
    service: "WFS", version: "1.0.0", request: "GetFeature",
    typeName: SNV_LAYER, outputFormat: "application/json", srsName: "EPSG:4326",
    CQL_FILTER: `sg_uf='${uf}' AND vl_br='${br}' AND sg_tipo_tr='B'`,
  });
  const json = JSON.parse(await fetchText(`${SNV_WFS}?${params}`));
  const segs = (json.features || [])
    .filter((f) => f.geometry)
    .map((f) => ({
      a: +f.properties.vl_km_inic,
      b: +f.properties.vl_km_fina,
      line: mergeParts(f.geometry.type === "LineString"
        ? [f.geometry.coordinates] : f.geometry.coordinates),
    }))
    .filter((s) => s.line.length >= 2 && s.b > s.a)
    .sort((x, y) => x.a - y.a);
  // Orienta cada segmento no sentido crescente do km, pelos vizinhos.
  const near = (p, line) =>
    Math.min(distM(p, line[0]), distM(p, line[line.length - 1]));
  for (let i = 0; i < segs.length; i++) {
    const s = segs[i], line = s.line;
    if (i === 0) {
      // O 1º segmento termina perto de alguma ponta do seguinte.
      if (segs[1] && near(line[0], segs[1].line) < near(line[line.length - 1], segs[1].line)) {
        s.line = line.reverse();
      }
      continue;
    }
    // Os demais começam perto do fim do anterior (já orientado).
    const ref = segs[i - 1].line[segs[i - 1].line.length - 1];
    if (distM(line[line.length - 1], ref) < distM(line[0], ref)) s.line = line.reverse();
  }
  return segs;
}

function stretchGeometry(segs, a, b) {
  const pts = [];
  for (const s of segs) {
    if (s.b <= a || s.a >= b) continue;
    const f0 = (Math.max(a, s.a) - s.a) / (s.b - s.a);
    const f1 = (Math.min(b, s.b) - s.a) / (s.b - s.a);
    pts.push(...sliceLine(s.line, f0, f1));
  }
  return thin(pts);
}

async function mapLimit(items, limit, fn) {
  const out = new Array(items.length);
  let i = 0;
  await Promise.all(Array.from({ length: limit }, async () => {
    while (i < items.length) {
      const k = i++;
      out[k] = await fn(items[k]);
    }
  }));
  return out;
}

// ------------------------------------------------------------ montagem

async function buildRadarData({ log = console.log, today = new Date() } = {}) {
  const radars = await loadFixedRadars();
  log(`Pardal: ${radars.length} radares`);

  let prf = null;
  try {
    const sheet = await findCurrentPrfSheet(today);
    const list = await loadPrfStretches(sheet);
    log(`PRF: ${sheet.label} – ${list.length} trechos`);
    const keys = [...new Set(list.map((s) => `${s.uf}|${s.br}`))];
    const roads = new Map();
    await mapLimit(keys, 6, async (k) => {
      const [uf, br] = k.split("|");
      try {
        roads.set(k, await loadSnvRoad(uf, br));
      } catch (e) {
        log(`SNV ${k} falhou: ${e.message}`);
        roads.set(k, []);
      }
    });
    const stretches = [];
    let missing = 0;
    for (const s of list) {
      const pts = stretchGeometry(roads.get(`${s.uf}|${s.br}`) || [], s.a, s.b);
      if (pts.length < 2) { missing++; continue; }
      stretches.push([s.uf, s.br, s.a, s.b, encodePolyline(pts)]);
    }
    log(`PRF: ${stretches.length} trechos no mapa, ${missing} sem traçado no SNV`);
    prf = {
      label: sheet.label,
      validFrom: sheet.from.toISOString().slice(0, 10),
      validTo: sheet.to ? sheet.to.toISOString().slice(0, 10) : null,
      stretches,
    };
  } catch (e) {
    // Sem a PRF ainda vale publicar os radares fixos.
    log(`PRF indisponível: ${e.message}`);
  }

  return {
    v: 1,
    builtAt: new Date().toISOString(),
    attribution:
      "Radares fixos: projeto Pardal (ODbL) – DNIT, ANTT, DERs, prefeituras e " +
      "© colaboradores do OpenStreetMap. Trechos de radar portátil: Polícia " +
      "Rodoviária Federal; traçado: DNIT/SNV.",
    radars,
    prf,
  };
}

module.exports = {
  loadFixedRadars,
  mergeDuplicates,
  buildRadarData,
  // exportados para testes
  parseCsv, sheetCsvUrl, findCurrentPrfSheet, stretchGeometry, encodePolyline, brNum,
};
