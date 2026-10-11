/**
 * Monta a tabela de praças de pedágio usada no custo da viagem (baixada pelo
 * app e consultada no celular):
 *
 * 1. Praças: as do OpenStreetMap (barrier=toll_booth), já baixadas por
 *    pois.js para os arquivos public/pois/{UF}.json.gz. Cabines vizinhas
 *    (até 400 m) viram uma praça só.
 * 2. Preço (só rodovias federais, dados abertos da ANTT):
 *    - valor do carro = receita da praça no mês ÷ veículos equivalentes no
 *      mês × multiplicador do carro (cada categoria paga "multiplicador ×
 *      tarifa básica"; o carro é 1, ou 2 onde se cobra num sentido só);
 *    - moto: multiplicador da categoria moto naquela praça (0 = isenta,
 *      0,5 = metade).
 *    Os órgãos estaduais não publicam tarifas em dados abertos: nessas
 *    praças o app avisa que o valor não foi fornecido.
 *
 * Arquivo: { builtAt, month, p: [[lat, lng, carro|null, moto|null, raio, ...pontos]] }
 *   carro = R$ por passagem; moto = multiplicador sobre a tarifa básica
 *   convertido em fração do carro (0, 0,5...), ou null se não informado;
 *   raio = distância máxima (m) da rota até um ponto da praça.
 */

const CKAN = "https://dados.antt.gov.br/api/3/action/package_show?id=";

async function fetchBytes(url, tries = 3) {
  let last;
  for (let i = 0; i < tries; i++) {
    try {
      const res = await fetch(url, { signal: AbortSignal.timeout(300000) });
      if (!res.ok) throw new Error(`HTTP ${res.status} em ${url}`);
      return Buffer.from(await res.arrayBuffer());
    } catch (e) {
      last = e;
      await new Promise((r) => setTimeout(r, 3000 * (i + 1)));
    }
  }
  throw last;
}

/** As planilhas da ANTT vêm em UTF-8 ou em Latin-1, conforme o arquivo. */
function decodeText(buf) {
  const utf8 = buf.toString("utf8");
  return utf8.includes("�") ? new TextDecoder("latin1").decode(buf) : utf8;
}

/** CSV com ";" e aspas, como os da ANTT. Devolve objetos pelo cabeçalho. */
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
    else if (c === ";") { row.push(cell); cell = ""; }
    else if (c === "\n") { row.push(cell); rows.push(row); row = []; cell = ""; }
    else if (c !== "\r" && c !== "﻿") cell += c;
  }
  if (cell || row.length) { row.push(cell); rows.push(row); }
  const head = rows.shift().map((h) => h.trim().toLowerCase());
  return rows.filter((r) => r.length >= head.length)
    .map((r) => Object.fromEntries(head.map((h, i) => [h, r[i].trim()])));
}

/** "1.234,56" -> 1234.56 */
const num = (s) => {
  if (!s) return 0;
  const v = Number(s.includes(",") ? s.replace(/\./g, "").replace(",", ".") : s);
  return isFinite(v) ? v : 0;
};

const plain = (s) => s.normalize("NFD").replace(/[̀-ͯ�]/g, "").toUpperCase();

/** Nome da concessionária comparável entre planilhas ("RIO-SP" = "RIOSP"). */
function concKey(s) {
  return plain(s).replace(/CONCESSIONARIA|RODOVIAS|S\/A|\bSA\b|\bDO\b|\bDA\b|\bDE\b/g, "")
    .replace(/[^A-Z0-9]/g, "");
}

/** Palavras do nome da praça, sem km/rodovia (para comparar). */
function plazaWords(s) {
  return plain(s).replace(/BR-?\d+(\/[A-Z]{2})?|\d+[.,]?\d*\s*KM|KM\s*\d+[.,]?\d*/g, " ")
    .split(/[^A-Z0-9]+/).filter((w) => w.length > 1 && !/^P\d+$/.test(w) && w !== "DO" && w !== "DE" && w !== "DA");
}

/** Número da praça ("P01", "P1 -", "3 (Cambuí)"), se houver. */
function plazaCode(s) {
  const m = plain(s).match(/^\s*P?\s*0*(\d+)\b/);
  return m ? Number(m[1]) : null;
}

/** Semelhança entre nomes de concessionária (0..1). */
function concSimilar(a, b) {
  if (a === b) return 1;
  if (a.includes(b) || b.includes(a)) return 0.9;
  // Letras em comum na ordem (ECOVIASRIOMINAS x ECORIOMINAS).
  const m = Array.from({ length: a.length + 1 }, () => new Array(b.length + 1).fill(0));
  for (let i = 1; i <= a.length; i++) {
    for (let j = 1; j <= b.length; j++) {
      m[i][j] = a[i - 1] === b[j - 1] ? m[i - 1][j - 1] + 1 : Math.max(m[i - 1][j], m[i][j - 1]);
    }
  }
  return (2 * m[a.length][b.length]) / (a.length + b.length);
}

/**
 * Praças de [candidates] que são a mesma de [name]. Uma planilha às vezes
 * separa por sentido ("Moreira César Norte" e "Sul") e a outra junta
 * ("Moreira César"): nesse caso devolve as partes, para somar.
 */
function matchPlazas(name, candidates) {
  const code = plazaCode(name);
  const words = plazaWords(name);
  if (words.length) {
    const parts = candidates.filter((c) => {
      const cw = new Set(plazaWords(c));
      const cc = plazaCode(c);
      return words.every((w) => cw.has(w)) && (code == null || cc == null || code === cc) &&
        cw.size - words.length <= 1 && [...cw].every((w) => words.includes(w) || SIDE.test(w));
    });
    if (parts.length) return parts;
  }
  const one = matchPlaza(name, candidates);
  return one ? [one] : [];
}

const SIDE = /^(NORTE|SUL|LESTE|OESTE|A|B|I|II|PISTA|CENTRAL|MARGINAL)$/;

/** Acha, entre as praças de [candidates], a mesma de [name]. */
function matchPlaza(name, candidates) {
  const code = plazaCode(name);
  const words = new Set(plazaWords(name));
  let best = null, bestScore = 0;
  for (const c of candidates) {
    const cw = plazaWords(c);
    const common = cw.filter((w) => words.has(w)).length;
    const union = new Set([...cw, ...words]).size || 1;
    let score = common / union;
    const cc = plazaCode(c);
    if (code != null && cc != null) score += code === cc ? 0.5 : -0.5;
    if (score > bestScore) { bestScore = score; best = c; }
  }
  return bestScore >= 0.5 ? best : null;
}

const toRad = (d) => (d * Math.PI) / 180;
function distanceMeters(lat1, lng1, lat2, lng2) {
  const dLat = toRad(lat2 - lat1), dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 6371000 * 2 * Math.asin(Math.sqrt(a));
}

/**
 * Preço por praça federal a partir das planilhas da ANTT de um mês.
 * [rec] = linhas de "Receita por Praça"; [eq] = "Volume de Tráfego
 * Equivalente". Devolve [{ lat, lng, car, moto, name }].
 */
function priceFederal(rec, eq, month) {
  // Volume equivalente e multiplicadores por concessionária/praça.
  const byConc = new Map();
  for (const r of eq) {
    if (r.mes_ano !== month) continue;
    const ck = concKey(r.concessionaria);
    if (!byConc.has(ck)) byConc.set(ck, new Map());
    const plazas = byConc.get(ck);
    const name = r.praca;
    if (!plazas.has(name)) plazas.set(name, { veq: 0, moto: new Set(), car: new Map() });
    const p = plazas.get(name);
    const vol = num(r.volume_total), mult = num(r.multiplicador_de_tarifa);
    p.veq += num(r.volume_veiculo_equivalente);
    if (vol <= 0) continue;
    if (r.tipo_de_veiculo === "Moto") p.moto.add(mult);
    if (r.tipo_de_veiculo === "Passeio" && r.categoria_eixo === "2" && mult > 0) {
      p.car.set(mult, (p.car.get(mult) || 0) + vol);
    }
  }
  const concs = [...byConc.keys()];
  // Receita por praça (somando os sentidos, se vierem em linhas separadas).
  const recByPlaza = new Map();
  for (const r of rec) {
    if (r.mes_ano !== month) continue;
    const k = `${r.concessionaria}|${r.praca_de_pedagio}`;
    const prev = recByPlaza.get(k);
    if (prev) prev.receita += num(r.receita_praca_de_pedagio);
    else recByPlaza.set(k, { ...r, receita: num(r.receita_praca_de_pedagio) });
  }
  const out = [];
  for (const r of recByPlaza.values()) {
    const ck = concKey(r.concessionaria);
    let best = null, bestSim = 0;
    for (const c of concs) {
      const s = concSimilar(ck, c);
      if (s > bestSim) { bestSim = s; best = c; }
    }
    if (!best || bestSim < 0.75) continue;
    const plazas = byConc.get(best);
    const names = matchPlazas(r.praca_de_pedagio, [...plazas.keys()]);
    if (!names.length) continue;
    const p = { veq: 0, moto: new Set(), car: new Map() };
    for (const n of names) {
      const q = plazas.get(n);
      p.veq += q.veq;
      q.moto.forEach((m) => p.moto.add(m));
      q.car.forEach((v, m) => p.car.set(m, (p.car.get(m) || 0) + v));
    }
    const lat = num(r.latitude), lng = num(r.longitude);
    const revenue = r.receita;
    if (!p.veq || !revenue || !lat || !lng) continue;
    const base = revenue / p.veq; // tarifa básica (multiplicador 1)
    // Multiplicador do carro: o da maioria das passagens de carro.
    const carMult = p.car.size ? [...p.car].sort((a, b) => b[1] - a[1])[0][0] : 1;
    const car = Math.round(base * carMult * 10) / 10;
    if (car < 1 || car > 60) continue; // dado estranho: melhor não mostrar
    // Moto: se alguma passagem de moto pagou, vale esse multiplicador.
    const motoMult = p.moto.size ? Math.max(...p.moto) : null;
    out.push({
      lat, lng, car,
      moto: motoMult == null ? null : Math.min(1, Math.round((motoMult / carMult) * 100) / 100),
      name: `${r.concessionaria} ${r.praca_de_pedagio}`,
    });
  }
  return out;
}

/** Cabines do OSM -> praças (cabines a até 400 m viram uma praça). */
function clusterBooths(points) {
  const plazas = [];
  for (const [lat, lng, motoFree] of points) {
    const near = plazas.find((p) => p.pts.some(([a, b]) => distanceMeters(lat, lng, a, b) < 400));
    if (near) {
      near.pts.push([lat, lng]);
      near.motoFree = near.motoFree || motoFree;
    } else {
      plazas.push({ pts: [[lat, lng]], motoFree });
    }
  }
  return plazas;
}

/** Junta as praças do OSM com os preços federais (até 2 km de distância). */
function mergePlazas(osm, federal) {
  const out = osm.map((p) => ({ ...p, car: null, moto: p.motoFree ? 0 : null, radius: 40 }));
  let matched = 0;
  for (const f of federal) {
    let best = null, bestD = 2000;
    for (const p of out) {
      for (const [a, b] of p.pts) {
        const d = distanceMeters(f.lat, f.lng, a, b);
        if (d < bestD) { bestD = d; best = p; }
      }
    }
    if (best) {
      best.car = f.car;
      if (f.moto != null) best.moto = f.moto;
      matched++;
    } else {
      // Praça sem cabine no OSM (ex.: free flow): posição da ANTT, menos exata.
      out.push({ pts: [[f.lat, f.lng]], car: f.car, moto: f.moto, radius: 250 });
    }
  }
  return { plazas: out, matched };
}

/** Pontos de pedágio de um arquivo compacto de pois.js. */
function boothsFromPois(d) {
  const out = [];
  let lat = 0, lng = 0;
  for (let i = 0; i + 2 < d.length; i += 3) {
    lat += d[i];
    lng += d[i + 1];
    if (d[i + 2] === 3 || d[i + 2] === 4) out.push([lat / 1e5, lng / 1e5, d[i + 2] === 4]);
  }
  return out;
}

/** Recurso CSV mais recente de um conjunto da ANTT (por ano no nome). */
async function latestCsv(dataset, filter = () => true) {
  const meta = JSON.parse((await fetchBytes(CKAN + dataset)).toString("utf8")).result;
  const csvs = meta.resources
    .filter((r) => (r.format || "").toUpperCase() === "CSV" && filter(r))
    .map((r) => ({ ...r, year: Number((r.name.match(/20\d\d/) || [0])[0]) }))
    .sort((a, b) => b.year - a.year);
  return csvs;
}

/**
 * Monta a tabela. [booths] = cabines do OSM ([lat, lng, motoIsenta]).
 */
async function buildTolls({ booths, log = () => {} }) {
  const recs = await latestCsv("receita-por-praca");
  const rec = parseCsv(decodeText(await fetchBytes(recs[0].url)));
  const months = [...new Set(rec.map((r) => r.mes_ano))]
    .sort((a, b) => a.slice(3) + a.slice(0, 2) < b.slice(3) + b.slice(0, 2) ? 1 : -1);
  const month = months[0];
  const year = Number(month.slice(3));
  const eqs = await latestCsv("volume-trafego-equivalente-praca-pedagio",
    (r) => /mensal/i.test(r.name));
  const eqRes = eqs.find((r) => r.year === year);
  if (!eqRes) throw new Error(`Sem volume equivalente de ${year}`);
  const eq = parseCsv(decodeText(await fetchBytes(eqRes.url)));
  const federal = priceFederal(rec, eq, month);
  log(`Pedágios ANTT ${month}: ${federal.length} praças com preço`);
  const osm = clusterBooths(booths);
  const { plazas, matched } = mergePlazas(osm, federal);
  log(`Pedágios: ${osm.length} praças do OSM, ${matched} com preço federal, ${plazas.length} no total`);
  const r5 = (x) => Math.round(x * 1e5) / 1e5;
  return {
    builtAt: new Date().toISOString(),
    month,
    priced: federal.length,
    p: plazas.map((p) => [
      ...p.pts[0].map(r5), p.car, p.moto, p.radius,
      ...p.pts.slice(1).flat().map(r5),
    ]),
  };
}

module.exports = {
  buildTolls, priceFederal, clusterBooths, mergePlazas, boothsFromPois,
  parseCsv, concKey, matchPlaza, matchPlazas, concSimilar,
};
